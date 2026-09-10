"""Versioned review orchestration; raw credentials/content never enter telemetry."""
import hashlib
import json
import re
import time

from app.models import Diagnostic, FirestoreResumeReviewResponse, ReviewQuestion, SentenceReview

PROMPT_VERSION = 'resume-v5-natural-korean-proofread'
CRITERIA = ('aspiration', 'emotion', 'abstract_result', 'ordering', 'relevance', 'duplication', 'company_fit')


class ReviewConflict(Exception):
    pass


class ReviewInputError(Exception):
    pass


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, default=str).encode()).hexdigest()


def redact(text):
    text = re.sub(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}', '[연락처 삭제]', text)
    return re.sub(r'(?<!\d)(?:\+82[- .]?|0)(?:10|11|16|17|18|19|2|[3-6][1-5])[- .]?\d{3,4}[- .]?\d{4}(?!\d)', '[연락처 삭제]', text)


def normalize_confirmed_answer(text):
    """Remove requests to fabricate; only user-confirmed facts may ground edits."""
    cleaned = redact(text.strip())
    fabrication_request = re.search(
        r'(지어\s*내|꾸며\s*(?:내|줘|작성)|허구|가짜|임의로\s*(?:만들|작성)|만들어\s*줘)',
        cleaned,
        re.IGNORECASE,
    )
    if fabrication_request:
        return '사용자가 확인 가능한 추가 사실이 없다고 답했습니다.'
    return cleaned


_RECRUITING_TITLE_SUFFIX = re.compile(
    r'\s*(?:을|를)?\s*(?:찾고\s*있(?:어요|습니다)|모십니다|모집합니다|채용합니다|채용|모집)\s*[.!]?$',
    re.IGNORECASE,
)
_RECRUITING_TITLE_PREFIX = re.compile(
    r'^(?:(?:에서|와|과)\s*)?(?:함께할|함께\s*일할|모실)\s*',
    re.IGNORECASE,
)


def job_role_title(company, posting_title):
    """사람인 전체 공고 제목에서 이력서에 넣을 실제 직무명만 추린다."""
    company = str(company or '').strip()
    title = re.sub(r'\s+', ' ', str(posting_title or '')).strip()
    if not title:
        return ''

    role = title
    if company:
        role = re.sub(re.escape(company), ' ', role, flags=re.IGNORECASE)
    role = re.sub(r'^\s*(?:에서|와|과)\s*', '', role)
    role = _RECRUITING_TITLE_PREFIX.sub('', role)
    role = _RECRUITING_TITLE_SUFFIX.sub('', role)
    role = re.sub(r'^[\s|·:/_-]+|[\s|·:/_-]+$', '', role)
    # 붙여 쓰인 대표 직무 표기는 이력서에서 읽기 좋은 형태로 통일한다.
    role = re.sub(r'(?i)(AI|ML|IT)\s*(엔지니어|개발자)', r'\1 \2', role)
    return re.sub(r'\s+', ' ', role).strip() or title


def review_job_prompt_text(job_text, job_source):
    """Mark selected-job identity as trusted context, separate from resume facts."""
    if not job_text:
        return '제공되지 않음'
    if not job_source:
        return job_text
    company = str(job_source.get('company') or '').strip() or '확인 불가'
    title = str(job_source.get('title') or '').strip() or '확인 불가'
    role_title = str(job_source.get('role_title') or '').strip() or job_role_title(company, title)
    return (
        '[선택 공고 식별 정보 — 사용자가 선택한 확정값]\n'
        f'회사명: {company}\n'
        f'직무명: {role_title}\n'
        f'공고 제목: {title}\n\n'
        '[공고 원문]\n'
        f'{job_text}'
    )


_IDENTITY_QUESTION_PATTERN = re.compile(r'(회사명|회사\s*이름|지원\s*회사|직무명|직무\s*이름|지원\s*직무)')
_PROJECT_TIME_QUESTION_PATTERN = re.compile(r'(시작일|종료일|기간|진행\s*상태|진행\s*여부|미래\s*기간|완료\s*여부)')


def project_time_context(content):
    """Return recorded project periods without inferring their present status."""
    entries = []
    for index, project in enumerate((content or {}).get('projects') or []):
        if not isinstance(project, dict):
            continue
        start = str(project.get('startDate') or '').strip()
        end = str(project.get('endDate') or '').strip()
        if not start or not end:
            continue
        entries.append({
            'field_prefix': f'projects[{index}]',
            'name': str(project.get('name') or '').strip() or f'프로젝트 {index + 1}',
            'start': start,
            'end': end,
        })
    if not entries:
        return '확정 가능한 프로젝트 기간이 없습니다.'
    return '\n'.join(
        f"{entry['field_prefix']} {entry['name']}: {entry['start']} ~ {entry['end']} (이력서 기록값)"
        for entry in entries
    )


def filter_verified_project_time_questions(generation, context):
    """Do not ask the user to reconfirm a project period already calculated."""
    verified_prefixes = {
        line.split(' ', 1)[0]
        for line in context.splitlines()
        if line.startswith('projects[') and '이력서 기록값' in line
    }
    if not verified_prefixes:
        return
    generation.questions = [
        question for question in generation.questions
        if not (
            any(question.field_path.startswith(prefix) for prefix in verified_prefixes)
            and _PROJECT_TIME_QUESTION_PATTERN.search(question.question)
        )
    ]


def apply_selected_job_identity_revisions(generation, fields, job_source):
    """Replace resume placeholders from the selected job without asking the user.

    Company and role are selected-job facts, not resume facts. They are safe to use
    only for the literal placeholders, and must not depend on an LLM following a
    prompt instruction.
    """
    company = str(job_source.get('company') or '').strip()
    posting_title = str(job_source.get('title') or '').strip()
    title = str(job_source.get('role_title') or '').strip() or job_role_title(
        company,
        posting_title,
    )
    replacements = {}
    for field_path, original in fields.items():
        revised = original
        changed = []
        if company and '[회사명]' in revised:
            revised = revised.replace('[회사명]', company)
            changed.append('회사명')
        if title and '[직무명]' in revised:
            revised = revised.replace('[직무명]', title)
            changed.append('직무명')
        # 구 버전에서 [직무명] 자리에 전체 공고 제목을 넣은 이력서도 복구한다.
        if posting_title and title and posting_title != title and posting_title in revised:
            revised = revised.replace(posting_title, title)
            if '직무명' not in changed:
                changed.append('직무명')
        if changed:
            replacements[field_path] = (original, revised, '·'.join(changed))
    if not replacements:
        return

    # The deterministic replacement is the only edit for its field. Otherwise a
    # model-generated whole-field rewrite could overwrite it during apply.
    generation.sentence_reviews = [
        review for review in generation.sentence_reviews
        if review.field_path not in replacements
    ]
    for field_path, (original, revised, changed) in replacements.items():
        generation.sentence_reviews.append(SentenceReview(
            field_path=field_path,
            original_quote=original,
            suggested_revision=revised,
            reason=f'선택한 공고의 {changed} 확정값을 자리표시자에 반영했습니다.',
            evidence_quotes=[original],
            status='improved',
            edit_type='content',
        ))

    # The company/title are already supplied above; never ask the user for them.
    generation.questions = [
        question for question in generation.questions
        if not _IDENTITY_QUESTION_PATTERN.search(question.question)
    ]
    generation.confirmation_questions = [
        question for question in generation.confirmation_questions
        if not _IDENTITY_QUESTION_PATTERN.search(question)
    ]
    for review in generation.sentence_reviews:
        if review.confirmation_question and _IDENTITY_QUESTION_PATTERN.search(review.confirmation_question):
            review.confirmation_question = None


def group(path):
    return path.rsplit('.', 1)[0]


def item_references(content, fields):
    refs = {}
    for path in fields:
        match = re.match(r'^(\w+)\[(\d+)\]', path)
        if not match:
            refs[path] = group(path)
            continue
        section, index = match.groups()
        items = content[section]
        item_id = items[int(index)].get('id')
        if not isinstance(item_id, str) or not item_id or sum(i.get('id') == item_id for i in items) != 1:
            refs[path] = 'legacy:' + path  # Answers are explicitly blocked for legacy items.
        else:
            refs[path] = section + ':' + item_id
    return refs


def prepare_answers(request, previous, snapshot_hash, refs):
    if not request.answers:
        from app.models import ConfirmationAnswer
        if previous and previous.get('input_hash') == snapshot_hash:
            return [ConfirmationAnswer.model_validate(a) for a in previous.get('confirmed_answers', [])]
        return []
    if not previous or request.expected_input_hash != snapshot_hash or previous['input_hash'] != snapshot_hash:
        raise ReviewConflict('resume_version_changed: reload the resume and review')
    known = {q['question_id']: q for q in previous.get('questions', [])}
    answers = []
    seen = set()
    for answer in request.answers:
        question = known.get(answer.question_id)
        if not question or question['field_path'] != answer.field_path or answer.question_id in seen:
            raise ReviewInputError('unknown, duplicate or mismatched question')
        if refs.get(answer.field_path, 'legacy:').startswith('legacy:'):
            raise ReviewConflict('stable_item_id_required')
        if previous.get('item_refs', {}).get(answer.field_path) != refs[answer.field_path]:
            raise ReviewConflict('resume_item_changed')
        if not answer.answer.strip():
            raise ReviewInputError('answer is blank')
        seen.add(answer.question_id)
        answers.append(answer.model_copy(update={
            'question': question['question'],
            'answer': normalize_confirmed_answer(answer.answer),
        }))
    # Carry forward previously confirmed facts, but only for an unchanged snapshot.
    from app.models import ConfirmationAnswer
    prior = [ConfirmationAnswer.model_validate(a) for a in previous.get('confirmed_answers', []) if a.get('question_id') not in seen]
    return prior + answers


def normalize_diagnostics(generation, fields, has_job, previous):
    by_key = {d.criterion: d for d in generation.diagnostics}
    for criterion in CRITERIA:
        d = by_key.get(criterion)
        if d is None or any(p not in fields for p in d.field_paths) or (criterion in ('company_fit', 'relevance') and not has_job):
            by_key[criterion] = Diagnostic(criterion=criterion, status='not_evaluated', reason='평가에 필요한 근거 또는 공고가 없습니다.')
        elif d.status == 'issue' and not d.field_paths:
            d.status = 'not_evaluated'
            d.reason = '문제 위치를 확인하지 못했습니다.'
    generation.diagnostics = [by_key[k] for k in CRITERIA]
    generation.star_checks = [s for s in generation.star_checks if s.field_path in fields]
    changes = {'resolved': [], 'unresolved': [], 'new': [], 'not_evaluated': []}
    if previous:
        old = {d['criterion']: d['status'] for d in previous.get('diagnostics', [])}
        for d in generation.diagnostics:
            if d.status == 'not_evaluated':
                changes['not_evaluated'].append(d.criterion)
            elif d.status == 'issue':
                changes['unresolved' if old.get(d.criterion) == 'issue' else 'new'].append(d.criterion)
            elif old.get(d.criterion) == 'issue':
                changes['resolved'].append(d.criterion)
    return changes


def normalize_questions(generation, fields, answers, review_id):
    candidates = list(generation.questions)
    for sentence in generation.sentence_reviews:
        if sentence.confirmation_question:
            candidates.append(ReviewQuestion(field_path=sentence.field_path, topic='other', question=sentence.confirmation_question, reason=sentence.reason))
    answered = {(a.field_path, re.sub(r'\W', '', a.question)) for a in answers}
    seen = set()
    questions = []
    for q in sorted(candidates, key=lambda q: q.priority):
        text_key = re.sub(r'\W', '', q.question)
        key = (group(q.field_path), q.topic) if q.topic != 'other' else (group(q.field_path), text_key)
        if q.field_path not in fields or not q.question.strip() or key in seen or (q.field_path, text_key) in answered:
            continue
        seen.add(key)
        q.question_id = digest([review_id, q.field_path, q.topic, text_key])[:24]
        questions.append(q)
    generation.questions = questions[:10]
    generation.confirmation_questions = [q.question for q in generation.questions[:3]]


def run_review(service, id_token, request):
    # Import here to keep pure helpers independent of model/provider construction.
    from app.resume_review import extract_review_fields, enforce_resume_review_grounding, ground_sentences, require_answer_reflection
    db = service._firebase
    uid = db.verify_id_token(id_token)
    resume = db.get_owned_resume(request.cohort_id, request.resume_id, uid)
    raw_content = resume.get('content') or {}
    fields, excluded = extract_review_fields(raw_content)
    refs = item_references(raw_content, fields)
    snapshot_hash = digest(raw_content)
    time_context = project_time_context(raw_content)
    fields = {key: redact(value) for key, value in fields.items()}
    if not fields or not any(len(v.strip()) >= 3 for v in fields.values()):
        raise ReviewInputError('resume is empty')
    text = json.dumps(fields, ensure_ascii=False)
    if len(text) > 50000:
        raise ReviewInputError('resume exceeds 50000 characters')
    previous = None
    if request.previous_review_id:
        previous = db.get_ai_review(request.cohort_id, request.resume_id, uid, request.previous_review_id)
    if request.expected_input_hash and request.expected_input_hash != snapshot_hash:
        raise ReviewConflict('resume_version_changed')
    job_source = {}
    job_text = request.job_posting_text
    if request.review_mode == 'general' and (request.selected_job_id or job_text):
        raise ReviewInputError('general_review_cannot_include_job')
    if request.selected_job_id:
        from app.matching_handoff import load_selected_job
        if request.job_posting_text:
            raise ReviewInputError('selected_job_and_client_text_are_mutually_exclusive')
        job = load_selected_job(service._settings.matching_job_store_path, request.selected_job_id)
        job_source, job_text = job['source'], job['text']
        if request.expected_job_hash and request.expected_job_hash != job_source['snapshot_hash']:
            raise ReviewConflict('selected_job_changed')
    answers = prepare_answers(request, previous, snapshot_hash, refs)
    if len(answers) > 30:
        raise ReviewInputError('too many accumulated answers')
    current_answer_ids = {answer.question_id for answer in request.answers}
    current_answers = [answer for answer in answers if answer.question_id in current_answer_ids]
    fingerprint = digest([uid, request.model_dump(), snapshot_hash, job_source, PROMPT_VERSION])
    state = db.claim_review(request.cohort_id, request.resume_id, uid, request.request_id, fingerprint)
    if state.get('response'):
        return FirestoreResumeReviewResponse.model_validate(state['response'])
    telemetry = {'model': service._settings.openai_model, 'prompt_version': PROMPT_VERSION,
                 'input_tokens': None, 'output_tokens': None, 'elapsed_ms': None, 'status': 'processing'}
    started = time.monotonic()
    try:
        generated = service._generator({
            'resume_text': text,
            'confirmed_answers': json.dumps([a.model_dump(exclude={'question_id'}) for a in answers], ensure_ascii=False),
            'current_turn_answers': json.dumps(
                [a.model_dump(exclude={'question_id'}) for a in current_answers],
                ensure_ascii=False,
            ),
            'job_posting_text': redact(review_job_prompt_text(job_text, job_source)),
            'resume_time_context': time_context,
            'review_mode': (
                '일반 이력서 첨삭 — 공고 없이 문장·경험·역할·성과 근거를 검토'
                if request.review_mode == 'general'
                else '공고 맞춤 첨삭 — 선택 공고와 이력서 원문을 비교'
            ),
            'review_focus': redact(request.review_focus or '전체 검토'),
        })
        # Structured output with include_raw preserves usage without logging content.
        if isinstance(generated, dict) and 'parsed' in generated:
            raw = generated.get('raw')
            usage = getattr(raw, 'usage_metadata', None) or {}
            telemetry.update(input_tokens=usage.get('input_tokens'), output_tokens=usage.get('output_tokens'))
            if generated.get('parsing_error') or generated.get('parsed') is None:
                raise RuntimeError('invalid structured model response')
            generated = generated['parsed']
        grounded, warnings = enforce_resume_review_grounding('\n'.join(fields.values()), generated)
        warnings.extend(ground_sentences(fields, answers, grounded))
        warnings.extend(require_answer_reflection(grounded, current_answers))
        apply_selected_job_identity_revisions(grounded, fields, job_source)
        changes = normalize_diagnostics(grounded, fields, bool(job_text), previous)
        normalize_questions(grounded, fields, answers, request.request_id)
        filter_verified_project_time_questions(grounded, time_context)
        telemetry.update(status='complete', elapsed_ms=round((time.monotonic() - started) * 1000))
        response = FirestoreResumeReviewResponse(
            **grounded.model_dump(), review_id=request.request_id, cohort_id=request.cohort_id,
            resume_id=request.resume_id, grounding_warnings=warnings, input_fields=fields,
            input_hash=snapshot_hash, item_refs=refs, excluded_fields=excluded,
            confirmed_answers=answers, changes=changes, telemetry=telemetry, job_source=job_source)
        # Persist the response on the claimed document; repeat requests recover it.
        db.complete_review(request.cohort_id, request.resume_id, uid, request.request_id, response.model_dump())
        return response
    except Exception as exc:
        telemetry.update(status='failed', elapsed_ms=round((time.monotonic() - started) * 1000), error_type=type(exc).__name__)
        # Do not release the claim: uncertain model/save outcomes must not silently rebill.
        try:
            db.fail_review(request.cohort_id, request.resume_id, uid, request.request_id, telemetry)
        except Exception:
            pass
        raise
