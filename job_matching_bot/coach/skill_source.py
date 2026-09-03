"""요구역량을 어디서 뽑을지 고르는 계층.

LLM 추출이 기본이고, 쓸 수 없으면 규칙 기반으로 내려간다. 설계 문서 §14의
"Schema 검증 실패 시 제한된 횟수만 재시도하고, 계속 실패하면 규칙 기반 결과
또는 사용자에게 확인이 필요한 상태로 전환한다"에 해당한다.

어느 경로로 나온 값인지 `method`에 남겨서, 나중에 품질을 따로 집계할 수 있게 한다.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from job_matching_bot.ingestion.skill_extractor import extract_skills

METHOD_LLM = "llm_extraction"
METHOD_RULE = "keyword_extractor"


def _rule_based(title: str, body: str) -> dict[str, Any]:
    """사전 매칭. 필수/우대를 구분하지 못하므로 전부 UNKNOWN으로 둔다."""
    names = extract_skills(f"{title} {body}")
    return {
        "required_skills": [],
        "preferred_skills": [],
        "unknown_skills": names,
        "skills": [
            {
                "name": name,
                "requirement_type": "UNKNOWN",
                "evidence": "",
                "category": "TOOL",
            }
            for name in names
        ],
        "method": METHOD_RULE,
        "confidence": 1.0 if names else 0.0,
        # 규칙 기반은 근거 문장을 남기지 못한다. 사람이 확인할 여지가 있다.
        "needs_review": bool(names),
    }


def extract_requirements(
    title: str,
    body: str,
    *,
    cache_path: Path | None = None,
    extractor: Any = None,
    allow_llm: bool = True,
) -> dict[str, Any]:
    """공고 본문에서 요구역량을 뽑는다.

    LLM을 쓸 수 없거나 호출이 실패하면 규칙 기반 결과를 돌려준다. 어느 쪽이든
    같은 모양의 딕셔너리가 나오므로 호출부는 분기하지 않아도 된다.
    """
    if not body.strip():
        return _rule_based(title, body)

    if allow_llm:
        from job_matching_bot.coach import requirement_extractor as re_mod

        if extractor is None and re_mod.is_configured():
            extractor = re_mod.RequirementExtractor(cache_path=cache_path)
        if extractor is not None:
            try:
                result = extractor.extract(title, body)
                payload = result.to_dict()
                payload.update(
                    {
                        "unknown_skills": [
                            s["name"]
                            for s in payload["skills"]
                            if s["requirement_type"] == "UNKNOWN"
                        ],
                        "method": METHOD_LLM,
                        "confidence": 1.0 if payload["skills"] else 0.0,
                        "needs_review": False,
                    }
                )
                return payload
            except Exception as error:
                # 모델 호출이 실패해도 수집 자체는 멈추지 않는다.
                fallback = _rule_based(title, body)
                fallback["llm_error"] = f"{type(error).__name__}: {error}"
                return fallback

    return _rule_based(title, body)
