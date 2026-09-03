"""파이프라인 결과 딕셔너리를 Markdown 보고서로 변환한다."""

from __future__ import annotations

from typing import Any


def _escape_cell(value: str) -> str:
    """표 안에서 링크 문법이나 열 구분자로 깨지지 않게 만든다."""
    return value.replace("|", "\\|").replace("[", "\\[").replace("]", "\\]")


def _header_lines(result: dict[str, Any]) -> list[str]:
    summary = result["input_summary"]
    resume = result["resume"]
    return [
        "# AI 취업 코치 Vertical Slice 테스트 보고서",
        "",
        f"- 실행 결과: **{result['test_status']}**",
        f"- 기준 시각: `{result['as_of']}`",
        f"- 입력: 잡코리아 수집본 {summary['jobkorea']}건 + Mock {summary['mock']}건",
        f"- 수집 저장소 진행 중 공고: {summary.get('store', 0)}건",
        f"- 정규화/중복 제거 후: {summary['deduplicated']}건",
        f"- IT 직무 필터 통과: {summary['it_jobs']}건 / 제외: {summary['non_it_excluded']}건",
        "- 방식: 외부 API·LLM 호출 없는 재현 가능한 규칙 기반 POC",
        "",
        "## 테스트 이력서",
        "",
        f"- 목표 직무: {', '.join(resume['target_roles'])}",
        f"- 기술: {', '.join(resume['skills'])}",
        f"- 희망 지역: {', '.join(resume['preferred_regions'])}",
        f"- 희망 고용형태: {', '.join(resume['preferred_employment_types'])}",
        f"- 학력/경력: {resume['education_level']} / {resume['career_years']}년",
        "",
    ]


def _it_filter_lines(result: dict[str, Any]) -> list[str]:
    lines = [
        "## IT 직무 사전 필터",
        "",
        "| 공고 | 기업 | 결과 | 근거 |",
        "|---|---|---|---|",
    ]
    for item in result["it_filter_results"]:
        lines.append(
            f"| {_escape_cell(item['title'])} | {_escape_cell(item['company'])} | "
            f"**{item['result']['status']}** | {item['result']['reason']} |"
        )
    return lines


def _hard_filter_lines(result: dict[str, Any]) -> list[str]:
    lines = [
        "",
        "## IT 공고 Hard Filter 결과",
        "",
        "| 공고 | 기업 | 결과 | 실패 또는 확인 필요 사유 |",
        "|---|---|---|---|",
    ]
    for item in result["hard_filter_results"]:
        reasons = item["result"]["failed"] + item["result"]["unknown"]
        lines.append(
            f"| {_escape_cell(item['title'])} | {_escape_cell(item['company'])} | "
            f"**{item['result']['status']}** | {'<br>'.join(reasons) or '없음'} |"
        )
    return lines


def _ranking_lines(result: dict[str, Any]) -> list[str]:
    lines = [
        "",
        "## 추천 Ranking",
        "",
        "> 추천 점수는 합격 확률이 아니라 공고 간 정렬을 위한 POC 점수다.",
        "",
        "| 순위 | 공고 | 기업 | 점수 | 등급 | 조건 상태 | 근거 |",
        "|---:|---|---|---:|---|---|---|",
    ]
    for index, item in enumerate(result["recommendations"], start=1):
        evidence = item["evidence"]
        evidence_text = (
            ", ".join(evidence["matched_skills"] + evidence["role_terms"])
            or "명시 근거 부족"
        )
        url = item["source_url"]
        escaped_title = _escape_cell(item["title"])
        label = f"[{escaped_title}]({url})" if url.startswith("http") else escaped_title
        lines.append(
            f"| {index} | {label} | {_escape_cell(item['company'])} | "
            f"{item['recommendation_score']}점 | {item['grade']} | "
            f"{item['hard_filter']['status']} | {evidence_text} |"
        )
    return lines


def _selected_job_lines(result: dict[str, Any]) -> list[str]:
    selected = result["selected_job"]
    lines = [
        "",
        "## 선택 공고 분석",
        "",
        f"- 공고: **{selected['title']}**",
        f"- 기업: {selected['company']}",
        f"- 필수 기술: {', '.join(selected['required_skills'])}",
        f"- 우대 기술: {', '.join(selected['preferred_skills'])}",
        "",
        "### Skill Evidence",
        "",
        "| 구분 | 역량 | 판정 | 이력서 근거 또는 다음 질문 |",
        "|---|---|---|---|",
    ]
    for item in result["skill_analysis"]["judgements"]:
        details = item["resume_evidence"] or [item["confirmation_question"]]
        lines.append(
            f"| {item['requirement_type']} | {item['criterion']} | "
            f"**{item['judgement']}** | {'<br>'.join(filter(None, details))} |"
        )
    return lines


def _coach_output_lines(result: dict[str, Any]) -> list[str]:
    lines = ["", "### Resume Feedback", ""]
    feedback = result["skill_analysis"]["resume_feedback"]
    lines.extend([f"- {item}" for item in feedback] or ["- 현재 자동 피드백 없음"])

    lines.extend(["", "### Learning Recommendation", ""])
    learning = result["skill_analysis"]["learning_recommendations"]
    if learning:
        for item in learning:
            lines.append(
                f"- {item['skill']}: [{item['title']}]({item['url']}) · {item['level']} · "
                f"{item['estimated_duration']} · 확인값 `{item['last_checked_at']}`"
            )
    else:
        lines.append("- 사용자가 경험 없음으로 확인한 역량 중 Catalog에 있는 항목 없음")
    return lines


def _footer_lines(result: dict[str, Any]) -> list[str]:
    lines = ["", "## 자동 검증", ""]
    for check in result["checks"]:
        lines.append(f"- **{'PASS' if check['passed'] else 'FAIL'}** — {check['name']}")
    lines.extend(
        [
            "",
            "## 이번 POC의 한계",
            "",
            "- Firebase Auth, Firestore, 실제 비동기 API는 연결하지 않았다.",
            "- LLM 대신 근거를 추적할 수 있는 결정론적 규칙을 사용했다.",
            "- 잡코리아 10건 중 이미지·첨부파일에만 있는 직무요건은 OCR하지 않아 요구기술이 비어 있을 수 있다.",
            "- Mock 학습 Catalog의 `TEST_FIXTURE`는 실시간 링크 검증을 의미하지 않는다.",
            "- 추천 가중치는 제품 품질 수치가 아니며 별도 평가 세트로 조정해야 한다.",
            "",
        ]
    )
    return lines


def build_report(result: dict[str, Any]) -> str:
    lines: list[str] = []
    lines.extend(_header_lines(result))
    lines.extend(_it_filter_lines(result))
    lines.extend(_hard_filter_lines(result))
    lines.extend(_ranking_lines(result))
    lines.extend(_selected_job_lines(result))
    lines.extend(_coach_output_lines(result))
    lines.extend(_footer_lines(result))
    return "\n".join(lines)
