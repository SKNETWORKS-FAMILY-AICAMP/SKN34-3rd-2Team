from __future__ import annotations

import re
import json
import hashlib
from collections.abc import Callable
from typing import Any

from langchain_openai import ChatOpenAI

from app.config import Settings
from app.firebase_gateway import FirebaseGateway
from app.models import (
    FirestoreResumeReviewRequest,
    FirestoreResumeReviewResponse,
    ResumeReviewGeneration,
)
from app.prompts import RESUME_REVIEW_PROMPT
from app.service import NUMBER_PATTERN
from app.technology import comparison_terms


SECTION_LABELS = {
    "coreCompetencies": "핵심 역량",
    "experience": "경력",
    "education": "학력",
    "techStack": "기술 스택",
    "certifications": "자격증",
    "awards": "수상",
    "trainingExperience": "교육 경험",
    "otherActivities": "기타 활동",
    "projects": "프로젝트",
    "selfIntroduction": "자기소개서",
}
SECTION_KEY_ALIASES = {label: key for key, label in SECTION_LABELS.items()}
SECTION_KEY_ALIASES.update(
    {
        "핵심역량": "coreCompetencies",
        "기술스택": "techStack",
        "교육": "trainingExperience",
        "활동": "otherActivities",
        "기타활동": "otherActivities",
        "자기소개": "selfIntroduction",
    }
)
FIELD_LABELS = {
    "text": "내용",
    "company": "회사",
    "role": "역할",
    "startDate": "시작일",
    "endDate": "종료일",
    "isCurrent": "재직 중",
    "description": "설명",
    "school": "학교",
    "major": "전공",
    "status": "상태",
    "name": "이름",
    "level": "수준",
    "issuer": "발급기관",
    "acquiredDate": "취득일",
    "organization": "기관",
    "date": "날짜",
    "course": "과정",
    "techStack": "기술 스택",
    "subtitle": "소제목",
    "body": "본문",
}
SELF_INTRO_LABELS = {
    "intro": "자기소개",
    "motivation": "지원동기",
    "challenge": "어려움 극복 경험",
    "growth": "성장과정",
    "strengthsWeaknesses": "성격의 장단점",
    "aspiration": "입사 후 포부",
}
SKIPPED_FIELDS = {"id", "url", "githubUrl", "blogUrl"}


class ResumeReviewService:
    def __init__(
        self,
        settings: Settings,
        firebase: FirebaseGateway,
        generator: Callable[[dict[str, str]], ResumeReviewGeneration] | None = None,
    ) -> None:
        self._settings = settings
        self._firebase = firebase
        self._generator = generator or self._build_generator(settings)

    @staticmethod
    def _build_generator(settings: Settings):
        model = ChatOpenAI(
            model=settings.openai_model,
            api_key=settings.openai_api_key,
            use_responses_api=True,
            reasoning_effort=settings.openai_reasoning_effort,
            max_retries=0,
        )
        return (RESUME_REVIEW_PROMPT | model.with_structured_output(
            ResumeReviewGeneration,
            method="json_schema",
            include_raw=True,
        )).invoke

    def review(self, id_token: str, request: FirestoreResumeReviewRequest) -> FirestoreResumeReviewResponse:
        from app.review_workflow import run_review
        return run_review(self, id_token, request)


def render_resume_content(content: Any) -> str:
    """Render only review-relevant fields; basicInfo/URLs/internal IDs are excluded."""
    if not isinstance(content, dict):
        return ""
    blocks: list[str] = []
    for key, label in SECTION_LABELS.items():
        value = content.get(key)
        lines = _render_value(value, SELF_INTRO_LABELS if key == "selfIntroduction" else {})
        if lines:
            blocks.append(f"## {label}\n" + "\n".join(lines))
    return "\n\n".join(blocks)


def _render_value(value: Any, nested_labels: dict[str, str] | None = None) -> list[str]:
    nested_labels = nested_labels or {}
    if isinstance(value, list):
        lines: list[str] = []
        for index, item in enumerate(value, start=1):
            item_lines = _render_value(item)
            if item_lines:
                lines.append(f"[{index}]")
                lines.extend(item_lines)
        return lines
    if isinstance(value, dict):
        lines = []
        for key, item in value.items():
            if key in SKIPPED_FIELDS or item in (None, "", [], {}, False):
                continue
            label = nested_labels.get(key, FIELD_LABELS.get(key, key))
            if isinstance(item, (dict, list)):
                child_lines = _render_value(item)
                if child_lines:
                    lines.append(f"### {label}")
                    lines.extend(child_lines)
            else:
                lines.append(f"{label}: {str(item).strip()}")
        return lines
    text = str(value).strip() if value is not None else ""
    return [text] if text else []


def enforce_resume_review_grounding(
    resume_text: str,
    generation: ResumeReviewGeneration,
) -> tuple[ResumeReviewGeneration, list[str]]:
    warnings: list[str] = []
    all_questions = list(generation.confirmation_questions)
    allowed_numbers = set(NUMBER_PATTERN.findall(resume_text))
    allowed_sections = set(SECTION_LABELS)

    normalized_reviews = []
    for review in generation.section_reviews:
        review.section_key = SECTION_KEY_ALIASES.get(review.section_key.strip(), review.section_key.strip())
        if review.section_key not in allowed_sections:
            warnings.append(f"알 수 없는 섹션 첨삭을 제거했습니다: {review.section_key}")
            continue

        valid_quotes = [quote.strip() for quote in review.resume_quotes if quote.strip() and quote.strip() in resume_text]
        if len(valid_quotes) != len(review.resume_quotes):
            warnings.append(f"원문에서 확인되지 않은 인용을 제거했습니다: {review.section_key}")
        review.resume_quotes = list(dict.fromkeys(valid_quotes))

        revision = (review.suggested_revision or "").strip()
        invented_numbers = set(NUMBER_PATTERN.findall(revision)) - allowed_numbers
        if revision and (not valid_quotes or invented_numbers):
            reason = "직접 근거가 없어서" if not valid_quotes else "원문에 없는 수치가 있어서"
            warnings.append(f"{review.section_key} 첨삭안을 {reason} 제거했습니다.")
            review.suggested_revision = None
            question = "이 문장을 보완할 실제 행동·방법·결과와 확인 가능한 수치가 있나요?"
            review.confirmation_questions.append(question)
        review.confirmation_questions = _deduplicate(review.confirmation_questions)[:3]
        all_questions.extend(review.confirmation_questions)
        normalized_reviews.append(review)

    generation.section_reviews = normalized_reviews
    generation.confirmation_questions = _deduplicate(all_questions)[:10]
    return generation, _deduplicate(warnings)


def extract_review_fields(content: Any) -> tuple[dict[str, str], list[str]]:
    """Preserve field values and array positions without summarizing source content."""
    fields, excluded = {}, []

    def walk(value, path):
        if isinstance(value, dict):
            for key, child in value.items():
                child_path = f"{path}.{key}" if path else key
                if key in SKIPPED_FIELDS or (not path and key not in SECTION_LABELS):
                    excluded.append(child_path)
                elif key in FIELD_LABELS or key in SELF_INTRO_LABELS or key in SECTION_LABELS:
                    walk(child, child_path)
                else:
                    excluded.append(child_path)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                walk(child, f"{path}[{index}]")
        elif isinstance(value, str) and value.strip():
            fields[path] = value
        elif isinstance(value, bool):
            fields[path] = str(value).lower()

    if isinstance(content, dict):
        walk(content, "")
    return fields, excluded


def _meaning_risks(original, revision):
    """Conservative lexical checks, not a proof of semantic equivalence."""
    patterns = {
        'negation_changed': r'않|못|없|아니|미완료|미구현',
        'work_status_changed': r'예정|계획|진행\s*중|개발\s*중|구현\s*중|검토\s*중|학습\s*중',
        'ownership_changed': r'팀원|공동|협업|보조|지원받|도움|AI 코딩',
    }
    issues = [code for code, pattern in patterns.items()
              if bool(re.search(pattern, original)) != bool(re.search(pattern, revision))]
    # Keep signed quantities distinct; ordinary NUMBER_PATTERN ignores the sign.
    signed = r'(?<!\w)[+−-]\d+(?:[.,]\d+)*(?:%|명|건|개|개월|년|일|시간|분|초|ms)?'
    if set(re.findall(signed, original)) != set(re.findall(signed, revision)):
        issues.append('quantity_sign_changed')
    return issues


def ground_sentences(fields, answers, generation):
    warnings, valid = [], []
    spans = {}
    for item in generation.sentence_reviews:
        item.validation_issues = []
        original = fields.get(item.field_path, "")
        if not item.original_quote.strip() or item.original_quote not in original:
            warnings.append(f"문장 원문 위치 불일치: {item.field_path}")
            continue
        # Never offer ambiguous/overlapping changes that the apply API will reject.
        starts = [m.start() for m in re.finditer('(?=' + re.escape(item.original_quote) + ')', original)]
        if len(starts) != 1:
            warnings.append(f"문장 위치가 여러 곳이라 수정안을 제외했습니다: {item.field_path}")
            continue
        start, end = starts[0], starts[0] + len(item.original_quote)
        if any(start < b and a < end for a, b in spans.get(item.field_path, [])):
            warnings.append(f"중복 또는 겹친 수정안을 제외했습니다: {item.field_path}")
            continue
        from app.review_workflow import group
        source_map = {p: v for p, v in fields.items() if group(p) == group(item.field_path)}
        source_map.update({f'answer:{i}': a.answer for i, a in enumerate(answers) if group(a.field_path) == group(item.field_path)})
        sources = list(source_map.values())
        quotes = list(dict.fromkeys(q for q in item.evidence_quotes if q.strip() and any(q in s for s in sources)))
        # The verified original is always evidence for a minimal language edit.
        if item.original_quote not in quotes:
            quotes.insert(0, item.original_quote)
        revision = item.suggested_revision or ""
        evidence = "\n".join(quotes)
        new_numbers = set(NUMBER_PATTERN.findall(revision)) - set(NUMBER_PATTERN.findall(evidence))
        new_terms = comparison_terms(revision) - comparison_terms(evidence)
        role_expansion = any(term in revision and term not in evidence for term in ("주도", "총괄", "리드", "책임", "달성"))
        if item.suggested_revision is not None and not revision.strip():
            item.validation_issues.append('empty_revision')
        if revision.strip():
            item.validation_issues.extend(_meaning_risks(item.original_quote, revision))
            if new_numbers:
                item.validation_issues.append('unsupported_number')
            if new_terms:
                item.validation_issues.append('unsupported_term')
            if role_expansion:
                item.validation_issues.append('unsupported_role')
            if '[연락처 삭제]' in revision or '[연락처 삭제]' in item.original_quote:
                item.validation_issues.append('redacted_content')
        if item.validation_issues:
            item.suggested_revision = None
            if 'work_status_changed' in item.validation_issues:
                item.confirmation_question = "이 작업은 진행 중인가요, 완료된 상태인가요? 원문 상태를 바꿀 근거를 확인해 주세요."
            elif 'ownership_changed' in item.validation_issues or 'unsupported_role' in item.validation_issues:
                item.confirmation_question = "팀 전체의 작업과 구분하여 본인이 직접 맡은 범위를 알려 주세요."
            elif 'negation_changed' in item.validation_issues:
                item.confirmation_question = "원문의 수행 여부와 수정안의 의미가 달라질 수 있습니다. 실제 수행 여부를 확인해 주세요."
            else:
                item.confirmation_question = "원문 의미를 유지하기 위해 직접 수행한 행동과 확인 가능한 결과를 알려 주세요. 수치는 없어도 됩니다."
            warnings.append(f"문장 근거 검증 보류: {item.field_path}")
        item.evidence_quotes = quotes
        item.evidence_sources = [p for p, value in source_map.items() if any(q in value for q in quotes)]
        if item.suggested_revision is None:
            item.status = 'needs_confirmation' if item.confirmation_question else 'unchanged'
            if item.status == 'unchanged':
                item.edit_type = 'none'
        elif item.suggested_revision.strip() == item.original_quote.strip():
            item.status = 'unchanged'
            item.suggested_revision = None
            item.edit_type = 'none'
            if item.confirmation_question:
                item.status = 'needs_confirmation'
        elif re.sub(r'\s', '', item.suggested_revision) == re.sub(r'\s', '', item.original_quote):
            item.status = 'formatting'
            item.edit_type = 'spelling'
        else:
            item.status = 'formatting' if item.edit_type in ('spelling', 'tone', 'clarity') else 'improved'
            if item.edit_type == 'none':
                item.edit_type = 'content'
        if item.suggested_revision:
            spans.setdefault(item.field_path, []).append((start, end))
        valid.append(item)
    generation.sentence_reviews = valid
    # Legacy whole-section revisions have no field-level provenance: use sentence edits.
    for section in generation.section_reviews:
        section.suggested_revision = None
    return warnings


def _deduplicate(items: list[str]) -> list[str]:
    return list(dict.fromkeys(item.strip() for item in items if item and item.strip()))
