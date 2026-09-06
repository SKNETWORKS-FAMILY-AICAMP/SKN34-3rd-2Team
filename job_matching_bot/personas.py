"""가상 이력서별로 저장소의 공고를 랭킹해 본다.

한 이력서로만 보면 매칭이 "그 사람에게만" 맞게 튜닝돼도 알 수 없다. 여기서는
`schemas.resume.mock_resumes()`의 인물 전부에 대해 같은 저장소를 돌려서,
프론트엔드 신입에게 백엔드 공고가 올라오거나 경력 3년에게 5년 공고가 남는
식의 오류를 한눈에 본다.

    python -m job_matching_bot.personas
    python -m job_matching_bot.personas --resume frontend_entry --top 10
"""

from __future__ import annotations

import argparse
import sys
from collections import Counter
from pathlib import Path

from job_matching_bot.ingestion.job_store import open_store
from job_matching_bot.ingest import DEFAULT_STORE
from job_matching_bot.matching.hard_filter import hard_filter
from job_matching_bot.matching.ranking import rank_jobs
from job_matching_bot.schemas.job_posting import Job
from job_matching_bot.schemas.resume import ResumeProfile, mock_resumes


def open_jobs(store_path: Path) -> list[Job]:
    return open_store(store_path).load().active_jobs()


def describe(name: str, resume: ResumeProfile, jobs: list[Job], top: int) -> list[str]:
    lines = [
        f"### {name}",
        f"희망 {', '.join(resume.target_roles)} | 경력 {resume.career_years}년 | "
        f"{resume.education_level} | {', '.join(resume.preferred_regions)}",
        f"기술 {', '.join(resume.skills)}",
    ]
    # 탈락 사유 분포. 어떤 조건이 가장 많이 거르는지 본다.
    fail_reasons: Counter[str] = Counter()
    for job in jobs:
        result = hard_filter(job, resume)
        if result["status"] == "FAIL":
            for reason in result["failed"]:
                fail_reasons[reason.split(":")[0]] += 1
    ranked = rank_jobs(jobs, resume)
    lines.append(
        f"공고 {len(jobs)}건 → 랭킹 {len(ranked)}건 "
        f"(탈락 {len(jobs) - len(ranked)}건: {dict(fail_reasons.most_common(3)) or '없음'})"
    )
    for item in ranked[:top]:
        detail = item["score_detail"]
        matched = ", ".join(item["evidence"]["matched_skills"]) or "-"
        lines.append(
            f"  {item['recommendation_score']:5.1f} {item['grade']} "
            f"[{item['hard_filter']['status']}] "
            f"직무 {detail['role']:.2f} 기술 {detail['skills']:.2f}"
            f"({len(item['evidence']['matched_skills'])}/{detail['skills_total']}) "
            f"| {item['title'][:34]} | {matched}"
        )
    return lines


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="가상 이력서별 랭킹 확인")
    parser.add_argument("--store", type=Path, default=DEFAULT_STORE)
    parser.add_argument("--resume", choices=sorted(mock_resumes()), default=None)
    parser.add_argument("--top", type=int, default=5)
    args = parser.parse_args()

    if not args.store.exists():
        print(f"저장소가 없습니다: {args.store}")
        print("먼저 `python -m job_matching_bot.ingest --source SARAMIN_POC`를 실행하세요.")
        return 1

    jobs = open_jobs(args.store)
    resumes = mock_resumes()
    names = [args.resume] if args.resume else list(resumes)
    for name in names:
        print("\n".join(describe(name, resumes[name], jobs, args.top)))
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
