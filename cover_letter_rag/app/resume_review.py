from __future__ import annotations

import re
import json
import hashlib
from difflib import SequenceMatcher
from collections.abc import Callable
from typing import Any

from langchain_openai import ChatOpenAI

from app.config import Settings
from app.firebase_gateway import FirebaseGateway
from app.models import (
    FirestoreResumeReviewRequest,
    FirestoreResumeReviewResponse,
    ResumeReviewGeneration,
    SentenceReview,
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
    generation.confirmation_questions = _deduplicate(all_questions)[:30]
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


def _fact_anchors(text: str) -> list[str]:
    """Return only deterministic anchors that must survive a sentence rewrite.

    Korean free text is intentionally not tokenized here: an imprecise tokenizer could
    label ordinary wording as a protected fact. Numbers and technology/English tokens
    are stable enough to verify locally.
    """
    numbers = set(NUMBER_PATTERN.findall(text))
    terms = {term.removeprefix('tech:') for term in comparison_terms(text)}
    return sorted(numbers | terms, key=str.casefold)


def _change_rate(original: str, revision: str) -> float:
    source = re.sub(r'\s+', '', original)
    target = re.sub(r'\s+', '', revision)
    if not source and not target:
        return 0.0
    return round(1 - SequenceMatcher(a=source, b=target, autojunk=False).ratio(), 3)


_DUPLICATE_TOKEN_SUFFIX = re.compile(
    r'(?:으로|에서|에게|까지|부터|처럼|보다|하고|하며|해서|하여|되는|되던|되도록|'
    r'했습니다|하였다|합니다|된다|되며|되어|된|하는|한|할|했던|했다|을|를|은|는|이|가|과|와|의|에|로)$'
)
_DUPLICATE_TOKEN_STOPWORDS = {
    '사용자', '내용', '기능', '과정', '결과', '문장', '이력서', '프로젝트',
    '개발', '구현', '확인', '수정', '적용', '통해', '위해', '대한', '관련',
    '있습니다', '했습니다', '합니다', '것입니다', '수있습니다',
}


def _duplicate_content_tokens(text: str) -> set[str]:
    tokens = set()
    for token in re.findall(r'[가-힣A-Za-z][가-힣A-Za-z0-9·-]{1,}', text.lower()):
        normalized = _DUPLICATE_TOKEN_SUFFIX.sub('', token).strip('·-')
        if len(normalized) >= 2 and normalized not in _DUPLICATE_TOKEN_STOPWORDS:
            tokens.add(normalized)
    return tokens


def _answer_reflection_anchors(text: str) -> tuple[set[str], set[str]]:
    """Return stable facts and tolerant Korean content tokens from an answer."""
    stable = comparison_terms(text) | set(NUMBER_PATTERN.findall(text))
    return stable, _duplicate_content_tokens(text)


def _answer_is_reflected(original: str, revision: str, answer: str) -> bool:
    """Allow an answer-backed paraphrase without requiring a verbatim quote."""
    answer_stable, answer_content = _answer_reflection_anchors(answer)
    original_stable, original_content = _answer_reflection_anchors(original)
    revision_stable, revision_content = _answer_reflection_anchors(revision)
    new_stable = answer_stable - original_stable
    new_content = answer_content - original_content
    if new_stable & revision_stable:
        return True
    return len(new_content & revision_content) >= 2


def _paragraphs(text: str) -> list[str]:
    return [part.strip() for part in re.split(r'\n\s*\n', text) if len(part.strip()) >= 40]


def _adds_duplicate_paragraph(original: str, revision: str) -> bool:
    """Detect a newly appended paragraph that merely repeats an existing one.

    This intentionally targets long additions. Short wording corrections and a
    single new fact remain eligible for review.
    """
    source_paragraphs = _paragraphs(original)
    revised_paragraphs = _paragraphs(revision)
    if not source_paragraphs or len(revised_paragraphs) < 2:
        return False
    for candidate in revised_paragraphs:
        if len(candidate) < 100:
            continue
        compact_candidate = re.sub(r'\s+', '', candidate)
        candidate_tokens = _duplicate_content_tokens(candidate)
        if len(candidate_tokens) < 8:
            continue
        for source in source_paragraphs:
            # Retaining an unchanged source paragraph in a whole-field edit is
            # normal. Only inspect a genuinely new paragraph.
            if SequenceMatcher(
                a=compact_candidate,
                b=re.sub(r'\s+', '', source),
                autojunk=False,
            ).ratio() >= 0.88:
                continue
            shared = candidate_tokens & _duplicate_content_tokens(source)
            if len(shared) >= 6 and len(shared) / len(candidate_tokens) >= 0.32:
                return True
    return False


def require_answer_reflection(generation, answers):
    """Reject a follow-up edit that ignores the fact the user just confirmed.

    A confirmation question is for adding/verifying a fact, not a trigger for
    an unrelated grammar rewrite.  We deliberately use a conservative lexical
    check: if no newly supplied factual token survives in the revision, do not
    offer it as an answer-derived suggestion.
    """
    warnings = []
    if not answers:
        return warnings

    by_path = {}
    for answer in answers:
        by_path.setdefault(answer.field_path, []).append(answer)
    for item in generation.sentence_reviews:
        revision = (item.suggested_revision or '').strip()
        provided = by_path.get(item.field_path, [])
        if not revision or not provided:
            continue
        reflects_answer = any(
            _answer_is_reflected(item.original_quote, revision, answer.answer)
            for answer in provided
        )
        role_boundary_question = any(
            re.search(r'(팀원|담당\s*범위|역할\s*구분)', answer.question)
            for answer in provided
        )
        exposes_team_detail = bool(
            role_boundary_question
            and re.search(r'(팀원은|팀원이|팀원의\s*담당|다른\s*팀원)', revision)
        )
        if exposes_team_detail or not reflects_answer:
            item.suggested_revision = None
            item.status = 'unchanged'
            item.edit_type = 'none'
            item.confirmation_question = None
            issue = 'team_scope_exposed' if exposes_team_detail else 'answer_not_reflected'
            item.validation_issues = [*item.validation_issues, issue]
            warnings.append(f'답변 근거를 반영하지 않은 수정안을 제외했습니다: {item.field_path}')
    return warnings


def _merge_original_with_confirmed_answer(original: str, confirmed: str) -> str:
    """Keep only original sentences whose facts are not already in the answer."""
    confirmed = re.sub(r'[ \t]+', ' ', confirmed).strip()
    answer_stable, answer_content = _answer_reflection_anchors(confirmed)
    original_stable, original_content = _answer_reflection_anchors(original)
    overall_overlap = (
        len(original_content & answer_content) / len(original_content)
        if original_content
        else 0
    )
    # A detailed answer that covers most of the original paragraph is already
    # the integrated replacement. Keeping old sentences would merely repeat it.
    stable_overlap = original_stable & answer_stable
    if overall_overlap >= 0.3 and (
        not original_stable or stable_overlap or len(answer_content) >= 12
    ):
        return confirmed
    preserved = []
    for sentence in re.split(r'(?<=[.!?])\s+', original.strip()):
        sentence = sentence.strip()
        if not sentence:
            continue
        sentence_stable, sentence_content = _answer_reflection_anchors(sentence)
        stable_covered = bool(sentence_stable) and sentence_stable <= answer_stable
        shared = sentence_content & answer_content
        content_covered = bool(sentence_content) and (
            len(shared) / len(sentence_content) >= 0.45
        )
        if not stable_covered and not content_covered:
            preserved.append(sentence)
    parts = [*preserved, confirmed]
    return ' '.join(dict.fromkeys(part for part in parts if part))


def add_substantive_answer_fallback(generation, fields, answers):
    """Add a safe proposal if the model drops a substantive confirmed answer."""
    warnings = []
    negative_answer = re.compile(
        r'(모르겠|기억(?:이\s*)?나지|없습니다|없어요|하지\s*않았|못했|해본\s*적\s*없)'
    )
    for answer_index, answer in enumerate(answers):
        path = answer.field_path
        original = fields.get(path, '').strip()
        confirmed = answer.answer.strip()
        already_present = bool(original) and (
            re.sub(r'\s+', '', confirmed) in re.sub(r'\s+', '', original)
        )
        if already_present:
            warnings.append(f'answer_already_present:{path}')
            continue
        if (
            not original
            or len(confirmed) < 80
            or negative_answer.search(confirmed)
            or any(
                item.field_path == path and item.suggested_revision
                for item in generation.sentence_reviews
            )
        ):
            continue
        stable, content = _answer_reflection_anchors(confirmed)
        has_action = bool(
            re.search(
                r'(구현|개발|적용|측정|분석|확인|운영|설계|수정|개선|구축|처리|줄였|단축)',
                confirmed,
            )
        )
        if not has_action or (not stable and len(content) < 6):
            continue
        revision = _merge_original_with_confirmed_answer(original, confirmed)
        if re.sub(r'\s+', '', revision) == re.sub(r'\s+', '', original):
            warnings.append(f'answer_already_present:{path}')
            continue
        generation.sentence_reviews.append(
            SentenceReview(
                field_path=path,
                original_quote=original,
                reason='사용자가 확인한 직접 행동과 결과를 기존 내용에 보완했습니다.',
                suggested_revision=revision,
                evidence_quotes=[original, confirmed],
                status='improved',
                edit_type='content',
                evidence_sources=[path, f'answer:{answer_index}'],
                fact_anchors=_fact_anchors(original),
                change_rate=_change_rate(original, revision),
            )
        )
    return warnings


def ground_sentences(fields, answers, generation):
    warnings, valid = [], []
    spans = {}
    for item in generation.sentence_reviews:
        item.validation_issues = []
        item.fact_anchors = []
        item.change_rate = None
        item.change_rate_notice = None
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
        answer_source_map = {
            f'answer:{i}': a.answer
            for i, a in enumerate(answers)
            if group(a.field_path) == group(item.field_path)
        }
        source_map.update(answer_source_map)
        sources = list(source_map.values())
        quotes = list(dict.fromkeys(q for q in item.evidence_quotes if q.strip() and any(q in s for s in sources)))
        # The verified original is always evidence for a minimal language edit.
        if item.original_quote not in quotes:
            quotes.insert(0, item.original_quote)
        revision = item.suggested_revision or ""
        # Confirmed answers are grounding even when the model paraphrases them or
        # forgets to repeat the answer verbatim in evidence_quotes.
        evidence = "\n".join([*quotes, *answer_source_map.values()])
        new_numbers = set(NUMBER_PATTERN.findall(revision)) - set(NUMBER_PATTERN.findall(evidence))
        new_terms = comparison_terms(revision) - comparison_terms(evidence)
        original_terms = comparison_terms(item.original_quote)
        # A user-confirmed replacement can legitimately restate the field without
        # repeating every token in the abbreviated original quote.
        answer_restates_revision = any(revision.strip() and revision.strip() in answer.answer for answer in answers)
        missing_terms = set() if answer_restates_revision else original_terms - comparison_terms(revision)
        role_expansion = any(term in revision and term not in evidence for term in ("주도", "총괄", "리드", "책임", "달성"))
        if item.suggested_revision is not None and not revision.strip():
            item.validation_issues.append('empty_revision')
        if revision.strip():
            if _adds_duplicate_paragraph(original, revision):
                item.validation_issues.append('duplicate_existing_content')
            item.validation_issues.extend(_meaning_risks(item.original_quote, revision))
            if new_numbers:
                item.validation_issues.append('unsupported_number')
            if new_terms:
                item.validation_issues.append('unsupported_term')
            if missing_terms:
                item.validation_issues.append('missing_fact_anchor')
            if role_expansion:
                item.validation_issues.append('unsupported_role')
            if '[연락처 삭제]' in revision or '[연락처 삭제]' in item.original_quote:
                item.validation_issues.append('redacted_content')
        if item.validation_issues:
            item.suggested_revision = None
            if 'duplicate_existing_content' in item.validation_issues:
                # Repeating an existing paragraph is not a missing-fact problem.
                item.confirmation_question = None
                warnings.append(f"기존 문단과 중복된 수정안을 제외했습니다: {item.field_path}")
            elif 'work_status_changed' in item.validation_issues:
                item.confirmation_question = "이 작업은 진행 중인가요, 완료된 상태인가요? 원문 상태를 바꿀 근거를 확인해 주세요."
            elif 'ownership_changed' in item.validation_issues or 'unsupported_role' in item.validation_issues:
                item.confirmation_question = "팀 전체의 작업과 구분하여 본인이 직접 맡은 범위를 알려 주세요."
            elif 'negation_changed' in item.validation_issues:
                item.confirmation_question = "원문의 수행 여부와 수정안의 의미가 달라질 수 있습니다. 실제 수행 여부를 확인해 주세요."
            else:
                item.confirmation_question = "원문 의미를 유지하기 위해 직접 수행한 행동과 확인 가능한 결과를 알려 주세요. 수치는 없어도 됩니다."
            if 'duplicate_existing_content' not in item.validation_issues:
                warnings.append(f"문장 근거 검증 보류: {item.field_path}")
        item.evidence_quotes = quotes
        item.evidence_sources = [p for p, value in source_map.items() if any(q in value for q in quotes)]
        if revision.strip():
            item.evidence_sources.extend(
                source_path
                for source_path, answer_text in answer_source_map.items()
                if _answer_is_reflected(item.original_quote, revision, answer_text)
                and source_path not in item.evidence_sources
            )
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
            item.fact_anchors = _fact_anchors(item.original_quote)
            item.change_rate = _change_rate(item.original_quote, item.suggested_revision)
            # A warning is informational only. The user still chooses whether to apply it.
            if item.change_rate > 0.3:
                item.change_rate_notice = '원문 대비 변경 폭이 큽니다. 적용 전 문장 의미와 사실 앵커를 다시 확인해 주세요.'
            spans.setdefault(item.field_path, []).append((start, end))
        valid.append(item)
    generation.sentence_reviews = valid
    # Legacy whole-section revisions have no field-level provenance: use sentence edits.
    for section in generation.section_reviews:
        section.suggested_revision = None
    return warnings


def _deduplicate(items: list[str]) -> list[str]:
    return list(dict.fromkeys(item.strip() for item in items if item and item.strip()))
