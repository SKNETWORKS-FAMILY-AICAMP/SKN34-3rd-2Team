"""실험: 규칙 점수 없이 이력서 전문 ↔ 공고 전문 임베딩 유사도만으로 순위를 매겨 본다.

    python -m job_matching_bot.experiments.embedding_only_ranking [--top 5] [--no-cache]

- 이력서: scripts/resume_mocks.json 의 5개 페르소나를 평문으로 만든다(앱의 buildResumeText 와 같은 형식).
- 공고: artifacts/collected_it_jobs.json (수집 IT 공고). 제목·회사·조건·기술·본문을 한 문서로 만든다.
- 임베딩: OpenAI text-embedding-3-small. 결과는 artifacts/embedding_cache.json 에 캐시해 재실행 비용을 없앤다.
- 비교: 같은 페르소나로 규칙 랭킹(rank_jobs)을 돌려 두 순위를 나란히 보여준다.

이 스크립트는 산출물을 앱에 반영하지 않는다. 임베딩만으로 추천하면 어떤 순위가 나오는지
눈으로 보기 위한 것이다.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any

from job_matching_bot.config import ARTIFACTS_DIR, DEFAULT_COLLECTION_OUTPUT, DEFAULT_RESUME_MOCKS_INPUT
from job_matching_bot.coach import openai_client
from job_matching_bot.matching.ranking import rank_jobs
from job_matching_bot.schemas.job_posting import Job
from job_matching_bot.schemas.resume import mock_resumes

CACHE_PATH = ARTIFACTS_DIR / "embedding_cache.json"


# ── 텍스트 만들기 ──

def _period(start: str, end: str) -> str:
    s, e = (start or "").strip(), (end or "").strip()
    return f" ({s} ~ {e})" if (s or e) else ""


def resume_text(content: dict[str, Any]) -> str:
    """앱의 buildResumeText 와 같은 라벨 형식으로 이력서 전문을 만든다."""
    out: list[str] = []

    def section(title: str, lines: list[str]) -> None:
        lines = [l.strip() for l in lines if l and l.strip()]
        if not lines:
            return
        if out:
            out.append("")
        out.append(f"[{title}]")
        out.extend(lines)

    section("핵심역량", [(content.get("coreCompetencies") or {}).get("text", "")])
    section("기술스택", [
        f"{t.get('name','').strip()} ({t.get('level','').strip()})" if t.get("level") else t.get("name", "").strip()
        for t in content.get("techStack") or []
    ])
    project_lines: list[str] = []
    for p in content.get("projects") or []:
        project_lines.append(f"- {p.get('name','').strip()}{_period(p.get('startDate',''), p.get('endDate',''))}")
        if p.get("role"):
            project_lines.append(f"  역할: {p['role'].strip()}")
        if p.get("techStack"):
            project_lines.append(f"  기술: {p['techStack'].strip()}")
        if p.get("description"):
            project_lines.append(f"  {p['description'].strip()}")
    section("프로젝트 경험", project_lines)
    exp_lines: list[str] = []
    for e in content.get("experience") or []:
        head = f"- {e.get('company','').strip()}"
        if e.get("role"):
            head += f" / {e['role'].strip()}"
        head += _period(e.get("startDate", ""), "재직 중" if e.get("isCurrent") else e.get("endDate", ""))
        exp_lines.append(head)
        if e.get("description"):
            exp_lines.append(f"  {e['description'].strip()}")
    section("경력사항", exp_lines)
    section("학력사항", [
        f"- {e.get('school','').strip()} {e.get('major','').strip()}".strip()
        for e in content.get("education") or []
    ])
    section("자격사항", [f"- {c.get('name','').strip()}" for c in content.get("certifications") or []])
    intro_lines: list[str] = []
    labels = {
        "intro": "자기소개", "motivation": "지원동기", "challenge": "직무와 관련된 경험 중 어려움을 극복한 사례",
        "growth": "성장과정", "strengthsWeaknesses": "직무와 관련된 성격의 장단점", "aspiration": "지원한 회사에 대한 포부",
    }
    for key, label in labels.items():
        sec = (content.get("selfIntroduction") or {}).get(key) or {}
        if sec.get("body"):
            intro_lines.append(f"({label}) {sec.get('subtitle','').strip()}".strip())
            intro_lines.append(sec["body"].strip())
    section("자기소개서", intro_lines)
    return "\n".join(out).strip()


def job_text(record: dict[str, Any]) -> str:
    """수집 레코드를 공고 전문 한 문서로 만든다."""
    parts = [
        f"회사: {record.get('company','')}",
        f"직무: {record.get('position','')}",
        f"근무지: {record.get('location','')}",
        f"고용형태: {record.get('employment_type','')}",
        f"경력: {record.get('career_type','')} {record.get('min_career_years') or ''}".strip(),
        f"학력: {record.get('education','')}",
    ]
    if record.get("required_skills"):
        parts.append("필수 기술: " + ", ".join(record["required_skills"]))
    if record.get("preferred_skills"):
        parts.append("우대 기술: " + ", ".join(record["preferred_skills"]))
    if record.get("tech_stack"):
        parts.append("기술 태그: " + ", ".join(record["tech_stack"]))
    parts.append("")
    parts.append((record.get("description") or "").strip())
    return "\n".join(parts).strip()


# ── 임베딩 (캐시) ──

def _key(text: str, model: str) -> str:
    return hashlib.sha256(f"{model}\n{text}".encode("utf-8")).hexdigest()


def embed_all(texts: list[str], *, use_cache: bool) -> list[list[float]]:
    model = openai_client.DEFAULT_EMBEDDING_MODEL
    cache: dict[str, list[float]] = {}
    if use_cache and CACHE_PATH.exists():
        cache = json.loads(CACHE_PATH.read_text(encoding="utf-8"))
    missing = [t for t in texts if _key(t, model) not in cache]
    if missing:
        client = openai_client.OpenAIChatModel()
        # 한 번에 너무 많이 보내지 않도록 나눠 보낸다.
        for start in range(0, len(missing), 32):
            batch = missing[start:start + 32]
            for text, vector in zip(batch, client.embed(batch, model=model)):
                cache[_key(text, model)] = vector
        if use_cache:
            CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
            CACHE_PATH.write_text(json.dumps(cache), encoding="utf-8")
    return [cache[_key(t, model)] for t in texts]


def cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    return dot / (na * nb) if na and nb else 0.0


# ── 규칙 랭킹 비교용 ──

def _job_from_record(record: dict[str, Any]) -> Job:
    return Job(
        job_id=record["id"],
        source=record.get("source", ""),
        source_job_id=record["id"].split("-")[-1],
        source_url=record.get("source_url", ""),
        company=record.get("company", ""),
        company_type="",
        title=record.get("position", ""),
        description=record.get("description", ""),
        required_skills=list(record.get("required_skills") or []),
        preferred_skills=list(record.get("preferred_skills") or []),
        tech_stack=list(record.get("tech_stack") or []),
        career_type=record.get("career_type", "ANY"),
        min_career_years=record.get("min_career_years"),
        education=record.get("education", "학력무관"),
        region=record.get("location", "미기재"),
        employment_type=record.get("employment_type") or "미기재",
        posted_at=None,
        deadline=record.get("deadline"),
        status=record.get("status", "OPEN"),
        content_hash="",
        parser_version="experiment",
        field_provenance={},
        body_is_image=bool(record.get("body_is_image")),
    )


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--top", type=int, default=5)
    parser.add_argument("--no-cache", action="store_true")
    parser.add_argument("--jobs", type=Path, default=DEFAULT_COLLECTION_OUTPUT)
    parser.add_argument("--resumes", type=Path, default=DEFAULT_RESUME_MOCKS_INPUT)
    args = parser.parse_args()

    if not openai_client.is_configured():
        print("OPENAI_API_KEY 가 없어 임베딩을 만들 수 없습니다.")
        return 1

    records = json.loads(args.jobs.read_text(encoding="utf-8"))
    personas = json.loads(args.resumes.read_text(encoding="utf-8"))["personas"]
    rule_profiles = mock_resumes()

    job_docs = [job_text(r) for r in records]
    resume_docs = {key: resume_text(p.get("content", p)) for key, p in personas.items()}
    vectors = embed_all(job_docs + list(resume_docs.values()), use_cache=not args.no_cache)
    job_vectors = vectors[: len(job_docs)]
    resume_vectors = dict(zip(resume_docs, vectors[len(job_docs):]))

    jobs = [_job_from_record(r) for r in records]
    print(f"공고 {len(records)}건 × 이력서 {len(personas)}개, 모델 {openai_client.DEFAULT_EMBEDDING_MODEL}\n")
    for key, vector in resume_vectors.items():
        title = personas[key].get("title", key)
        sims = sorted(
            ((cosine(vector, jv), r) for jv, r in zip(job_vectors, records)),
            key=lambda item: item[0],
            reverse=True,
        )
        rule = rank_jobs(jobs, rule_profiles[key]) if key in rule_profiles else []
        rule_rank = {item["job_id"]: i + 1 for i, item in enumerate(rule)}
        print(f"== {title} ({key}) ==")
        print(f"  {'임베딩':>4} {'유사도':>6} {'규칙':>4}  공고")
        for i, (sim, r) in enumerate(sims[: args.top], start=1):
            rr = rule_rank.get(r["id"], "탈락" if rule else "-")
            note = " [이미지]" if r.get("body_is_image") else ""
            print(f"  {i:>4} {sim:>6.3f} {str(rr):>4}  {r['company']} · {r['position'][:40]}{note}")
        if rule:
            print("  규칙 상위:", ", ".join(f"{i+1}.{item['company']}" for i, item in enumerate(rule[: args.top])))
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
