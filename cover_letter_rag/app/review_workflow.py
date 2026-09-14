"""Versioned review orchestration; raw credentials/content never enter telemetry."""
import hashlib
import json
import re
import time

from app.models import Diagnostic, FirestoreResumeReviewResponse, ReviewQuestion, SentenceReview
from app.technology import technology_mentions

PROMPT_VERSION = 'resume-v11-role-linked-motivation'
CRITERIA = ('aspiration', 'emotion', 'abstract_result', 'ordering', 'relevance', 'duplication', 'company_fit')
MISSING_JOB_TECH_REASON = '공고에 언급된 기술의 실제 사용 프로젝트를 확인합니다.'


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


def _has_final_consonant(text):
    """Return whether the final Hangul syllable has a 받침.

    English/acronym-ending role names have no reliable Korean particle rule, so
    use the vowel-ending form as the least intrusive fallback.
    """
    match = re.search(r'[가-힣]$', str(text or '').strip())
    return bool(match and (ord(match.group()) - ord('가')) % 28)


def _job_role_with_particle(role, particle):
    """Attach a natural Korean particle to a selected-job role title."""
    has_batchim = _has_final_consonant(role)
    if particle in ('은', '는', '이', '가'):
        # 직무 자체를 주어로 쓸 때는 'AI 엔지니어은'이 아니라
        # 'AI 엔지니어 직무는'이 가장 자연스럽다.
        return f'{role} 직무는'
    if particle in ('을', '를'):
        return f"{role}{'을' if has_batchim else '를'}"
    if particle in ('으로', '로'):
        # 받침 ㄹ 뒤에는 '로', 그 밖의 받침 뒤에는 '으로'를 쓴다.
        last = str(role or '').strip()[-1:]
        is_rieul = bool(last and '가' <= last <= '힣' and (ord(last) - ord('가')) % 28 == 8)
        return f"{role}{'로' if not has_batchim or is_rieul else '으로'}"
    return f'{role}{particle}'


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


def apply_selected_job_identity_revisions(
    generation,
    fields,
    job_source,
    *,
    insert_missing_identity=False,
):
    """Replace resume placeholders from the selected job without asking the user.

    Company and role are selected-job facts, not resume facts. Placeholder
    replacement and the optional tailored-resume introduction are deterministic;
    neither depends on an LLM following a prompt instruction.
    """
    company = str(job_source.get('company') or '').strip()
    posting_title = str(job_source.get('title') or '').strip()
    title = str(job_source.get('role_title') or '').strip() or job_role_title(
        company,
        posting_title,
    )
    replacements = {}
    auto_identity_paths = set()
    for field_path, original in fields.items():
        revised = original
        changed = []
        # 자리표시자 뒤의 조사를 직무명 마지막 글자에 맞게 바꾼다.
        # 예: 'AI 엔지니어은' → 'AI 엔지니어 직무는',
        #     'AI 엔지니어으로' → 'AI 엔지니어로'.
        if company and title:
            placeholder_with_particle = re.compile(
                r'\[회사명\]\s*의\s*\[직무명\]\s*(?P<particle>으로|은|는|이|가|을|를|로)'
            )
            if placeholder_with_particle.search(revised):
                revised = placeholder_with_particle.sub(
                    lambda match: f"{company}의 {_job_role_with_particle(title, match.group('particle'))}",
                    revised,
                )
                changed.extend(['회사명', '직무명'])
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
        # 이미 잘못 치환된 이력서도 같은 표현으로 복구한다.
        if company and title:
            role_candidates = [title]
            if posting_title and posting_title != title:
                role_candidates.append(posting_title)
            role_pattern = '|'.join(re.escape(candidate) for candidate in role_candidates)
            job_subject = re.compile(
                rf'{re.escape(company)}\s*의\s*(?:{role_pattern})\s*(?:은|는|이|가)'
            )
            if job_subject.search(revised):
                revised = job_subject.sub(f'{company}의 {title} 직무는', revised)
                if '직무명' not in changed:
                    changed.append('직무명')
        if changed:
            replacements[field_path] = (original, revised, '·'.join(changed))

    # 기본 이력서에 자리표시자를 쓰도록 강요하지 않는다. 공고별 사본의 첫 검토에서만
    # 지원동기(없으면 입사 후 포부) 한 곳에 안전한 독립 문장을 제안한다. 원문과 문장을
    # 억지로 이어 붙이지 않아 어떤 내용이 뒤따라도 조사나 의미가 깨지지 않는다.
    has_identity_replacement = bool(replacements)
    # 'AI 엔지니어' 같은 범용 희망 직무는 기본 이력서에도 흔히 존재한다.
    # 선택 회사명이 실제로 들어간 경우에만 이미 공고 맞춤 반영된 것으로 본다.
    identity_already_written = bool(company) and any(
        company in value for value in fields.values()
    )
    if (
        insert_missing_identity
        and company
        and title
        and not has_identity_replacement
        and not identity_already_written
    ):
        candidate_paths = (
            'selfIntroduction.motivation.body',
            'selfIntroduction.aspiration.body',
        )
        field_path = next(
            (path for path in candidate_paths if str(fields.get(path) or '').strip()),
            None,
        )
        if field_path:
            original = fields[field_path]
            if field_path.endswith('.motivation.body'):
                role_label = title if title.endswith('직무') else f'{title} 직무'
                identity_sentence = f'{company}의 {role_label}에 지원한 이유는 다음과 같습니다.'
            else:
                identity_sentence = (
                    f'{company}에서 {_job_role_with_particle(title, "으로")} '
                    '성장하고 싶습니다.'
                )
            replacements[field_path] = (
                original,
                f'{identity_sentence}\n{original}',
                '회사명·직무명',
            )
            auto_identity_paths.add(field_path)
    if not replacements:
        return

    # The deterministic replacement is the only edit for its field. Otherwise a
    # model-generated whole-field rewrite could overwrite it during apply.
    generation.sentence_reviews = [
        review for review in generation.sentence_reviews
        if review.field_path not in replacements
    ]
    for field_path, (original, revised, changed) in replacements.items():
        reason = (
            '선택한 공고의 회사명·직무명을 공고별 이력서에만 '
            '안전한 문장 패턴으로 추가했습니다.'
            if field_path in auto_identity_paths
            else f'선택한 공고의 {changed} 확정값을 자리표시자에 반영했습니다.'
        )
        generation.sentence_reviews.append(SentenceReview(
            field_path=field_path,
            original_quote=original,
            suggested_revision=revised,
            reason=reason,
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


def focused_followup_context(fields, answers, current_answers):
    """Limit a follow-up model call to the answered resume item.

    Grounding and persistence still receive the complete ``fields`` mapping.
    This only keeps unrelated resume entries out of the next model prompt after
    a user answers a confirmation question.
    """
    target_groups = {group(answer.field_path) for answer in current_answers if answer.field_path in fields}
    if not target_groups:
        return fields, answers, False
    scoped_fields = {
        path: value for path, value in fields.items()
        if group(path) in target_groups
    }
    scoped_answers = [
        answer for answer in answers
        if group(answer.field_path) in target_groups
    ]
    return scoped_fields, scoped_answers, True


def focused_time_context(time_context, current_answers):
    """Keep project-period context aligned with the follow-up resume item."""
    target_groups = {group(answer.field_path) for answer in current_answers}
    if not target_groups:
        return time_context
    lines = [
        line for line in time_context.splitlines()
        if any(line.startswith(target_group + ' ') for target_group in target_groups)
    ]
    return '\n'.join(lines) or '현재 첨삭 항목에 기록된 프로젝트 기간이 없습니다.'


def followup_job_prompt_text(job_text, job_source):
    """Keep selected-job identity in a follow-up without resending its full text."""
    if not job_text:
        return '제공되지 않음'
    if not job_source:
        # Older clients can submit a posting directly without a selected-job id.
        # Preserve a small amount of context, but do not resend a long posting.
        return '[후속 첨삭용 공고 요약]\n' + job_text[:1500]
    company = str(job_source.get('company') or '').strip() or '확인 불가'
    title = str(job_source.get('title') or '').strip() or '확인 불가'
    role_title = str(job_source.get('role_title') or '').strip() or job_role_title(company, title)
    return (
        '[선택 공고 식별 정보 — 사용자가 선택한 확정값]\n'
        f'회사명: {company}\n'
        f'직무명: {role_title}\n'
        f'공고 제목: {title}\n\n'
        '[후속 첨삭용 공고 근거]\n'
        f'{job_text[:2500]}\n\n'
        '[후속 첨삭 범위]\n'
        '위 공고 내용은 회사·직무 맥락에만 사용하고 지원자의 경험으로 쓰지 마세요. '
        '지원자의 경험 근거는 이력서 원문과 이번 사용자 답변에서만 가져오세요.'
    )


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


def _project_description_targets(fields):
    targets = []
    indices = sorted({
        int(match.group(1))
        for path in fields
        if (match := re.fullmatch(r'projects\[(\d+)\]\.description', path))
    })
    for index in indices:
        path = f'projects[{index}].description'
        name = str(fields.get(f'projects[{index}].name') or '').strip()
        targets.append((path, name or f'프로젝트 {index + 1}'))
    return targets


def resolve_missing_technology_project(answer_text, fields):
    """Resolve an explicitly selected project without guessing its ownership."""
    targets = _project_description_targets(fields)
    if not targets:
        return None
    numbered = {
        int(number) - 1
        for number in re.findall(r'(?<!\d)(\d+)\s*번(?:\s*프로젝트)?', answer_text)
    }
    numbered_matches = [target for index, target in enumerate(targets) if index in numbered]
    if len(numbered_matches) == 1:
        return numbered_matches[0][0]

    compact_answer = re.sub(r'\s+', '', answer_text).casefold()
    named_matches = [
        path for path, name in targets
        if len(re.sub(r'\s+', '', name)) >= 2
        and re.sub(r'\s+', '', name).casefold() in compact_answer
    ]
    return named_matches[0] if len(named_matches) == 1 else None


def prepare_answers(request, previous, snapshot_hash, refs, fields=None):
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
        field_path = answer.field_path
        if question.get('reason') == MISSING_JOB_TECH_REASON:
            has_no_experience = bool(re.search(
                r'(사용\s*경험(?:은|이)?\s*없|경험(?:은|이)?\s*없|해본\s*적\s*없|사용하지\s*않)',
                answer.answer,
            ))
            if not has_no_experience:
                field_path = resolve_missing_technology_project(answer.answer, fields or {})
                if field_path is None:
                    raise ReviewInputError(
                        '사용한 프로젝트를 확인할 수 없습니다. 질문에 표시된 번호 또는 프로젝트명을 포함해 주세요.'
                    )
                if refs.get(field_path, 'legacy:').startswith('legacy:'):
                    raise ReviewConflict('stable_item_id_required')
                if previous.get('item_refs', {}).get(field_path) != refs[field_path]:
                    raise ReviewConflict('resume_item_changed')
        answers.append(answer.model_copy(update={
            'field_path': field_path,
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
    generation.questions = questions[:30]
    generation.confirmation_questions = [q.question for q in generation.questions[:3]]


def carry_forward_unanswered_questions(generation, previous, answers):
    """Reissue queued questions on the latest review snapshot.

    The chat can continue through questions returned by the first review while
    each accepted edit rebases the resume.  Reissuing unanswered questions
    gives them a new question_id owned by the latest review, so the next
    answer is verifiable instead of being rejected as stale.
    """
    if not previous:
        return
    answered_ids = {answer.question_id for answer in answers}
    known = {
        (question.field_path, question.topic, re.sub(r'\W', '', question.question))
        for question in generation.questions
    }
    for raw_question in previous.get('questions', []):
        if raw_question.get('question_id') in answered_ids:
            continue
        question = ReviewQuestion.model_validate(raw_question)
        key = (question.field_path, question.topic, re.sub(r'\W', '', question.question))
        if key in known:
            continue
        generation.questions.append(question.model_copy(update={'question_id': ''}))
        known.add(key)


def add_thin_self_introduction_questions(generation, fields):
    """Guarantee follow-up for self-introduction answers with too little detail.

    A model can return one strong project question and miss several thin
    자기소개서 문항.  Those fields must not silently turn the whole review into
    "complete".  We add grounded, fact-seeking questions only for non-empty
    bodies that the model did not already target.  A self-introduction answer
    needs more room than a project bullet to explain its context and evidence.
    """
    existing_paths = {question.field_path for question in generation.questions}
    followups = []
    for path, body in fields.items():
        if not re.fullmatch(r'selfIntroduction\.[^.]+\.body', path):
            continue
        if len(re.sub(r'\s+', '', body)) >= 280 or path in existing_paths:
            continue
        section = path.split('.')[1]
        label = {
            'intro': '자기소개',
            'motivation': '지원동기',
            'challenge': '어려움 극복 경험',
            'growth': '성장과정',
            'strengthsWeaknesses': '성격의 장단점',
            'aspiration': '입사 후 포부',
        }.get(section, '자기소개서')
        followups.append(ReviewQuestion(
            field_path=path,
            topic='action',
            question=(
                f'{label} 문항에서 본인이 직접 한 행동이나 경험을 조금 더 '
                '구체적으로 알려 주세요. 결과·배운 점이 있다면 함께 적어 주세요.'
            ),
            reason='문항 내용이 충분하지 않아 경험의 근거와 직무 연관성을 확인하기 어렵습니다.',
            priority=1,
        ))
        existing_paths.add(path)
    # Preserve these coverage questions when the model already used its full
    # question budget for another section.
    generation.questions = followups + generation.questions


def add_missing_job_technology_question(generation, fields, job_text):
    """Turn a selected posting's missing technical evidence into one question.

    Job text is never evidence that the applicant has a skill.  This only asks
    whether an omitted, real experience exists, before any tailored revision
    may use it.
    """
    job_terms = technology_mentions(job_text or '')
    resume_terms = technology_mentions('\n'.join(fields.values()))
    missing_terms = sorted(job_terms - resume_terms, key=str.casefold)
    if not missing_terms:
        return
    if any(question.reason.startswith('공고에 언급된 기술') for question in generation.questions):
        return
    targets = _project_description_targets(fields)
    if not targets:
        return
    target_path = targets[0][0]  # Transport path only; the answer reroutes it.
    named_terms = ', '.join(missing_terms[:3])
    project_options = ', '.join(
        f'{index + 1}번 {name}' for index, (_, name) in enumerate(targets)
    )
    generation.questions.insert(0, ReviewQuestion(
        field_path=target_path,
        topic='scope',
        question=(
            f'선택 공고에 언급된 {named_terms}을(를) 실제로 사용했다면 어느 '
            f'프로젝트에서 사용했나요? 프로젝트 번호 또는 이름({project_options})과 '
            '본인이 직접 수행한 작업을 함께 알려 주세요. 사용 경험이 없다면 없다고 답해 주세요.'
        ),
        reason=MISSING_JOB_TECH_REASON,
        priority=1,
    ))


def prefer_project_evidence_over_surface_edit(generation, fields, answers):
    """Ask for missing project evidence instead of offering a cosmetic rewrite.

    A one-line project description can always be made grammatically smoother,
    but that does not make it a stronger application record.  Until the user
    confirms the problem, personal scope, or result, job-tailored review keeps
    the conversation focused on evidence rather than sentence endings.
    """
    answered_paths = {
        answer.field_path for answer in answers if str(answer.answer).strip()
    }
    questioned_paths = {question.field_path for question in generation.questions}
    for review in generation.sentence_reviews:
        path = review.field_path
        original = fields.get(path, '')
        is_short_project_description = (
            bool(re.fullmatch(r'projects\[\d+\]\.description', path)) and
            len(re.sub(r'\s+', '', original)) < 160
        )
        is_surface_edit = review.edit_type in {'spelling', 'tone', 'clarity'}
        if (
            not is_short_project_description or
            not is_surface_edit or
            not review.suggested_revision or
            path in answered_paths
        ):
            continue
        review.suggested_revision = None
        review.status = 'needs_confirmation'
        review.edit_type = 'none'
        review.reason = '표현 교정보다 프로젝트의 문제·담당 범위·확인 결과를 먼저 확인하는 편이 좋습니다.'
        if path not in questioned_paths and not review.confirmation_question:
            review.confirmation_question = (
                '이 프로젝트에서 해결하려던 기존 문제와 본인이 맡은 구현 범위, '
                '확인한 결과를 알려 주세요.'
            )
            questioned_paths.add(path)


def run_review(service, id_token, request):
    # Import here to keep pure helpers independent of model/provider construction.
    from app.resume_review import (
        add_substantive_answer_fallback,
        extract_review_fields,
        enforce_resume_review_grounding,
        ground_sentences,
        require_answer_reflection,
    )
    db = service._firebase
    uid = db.verify_id_token(id_token)
    if request.tailored_resume_id and request.review_mode != 'job':
        raise ReviewInputError('tailored_resume_requires_job_review')
    if request.tailored_resume_id:
        resume = db.get_owned_tailored_resume(
            request.cohort_id,
            request.resume_id,
            request.tailored_resume_id,
            uid,
        )
    else:
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
        if request.tailored_resume_id:
            previous = db.get_ai_review(
                request.cohort_id,
                request.resume_id,
                uid,
                request.previous_review_id,
                request.tailored_resume_id,
            )
        else:
            previous = db.get_ai_review(
                request.cohort_id, request.resume_id, uid, request.previous_review_id
            )
    is_gap_audit = request.review_phase == 'gap_audit'
    if is_gap_audit and (previous is None or request.answers):
        raise ReviewInputError('gap_audit_requires_previous_review_without_answers')
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
        if request.tailored_resume_id and resume.get('jobId') != request.selected_job_id:
            raise ReviewConflict('tailored_resume_job_mismatch')
        if request.tailored_resume_id and resume.get('jobSnapshotHash') != job_source['snapshot_hash']:
            raise ReviewConflict('tailored_resume_job_changed')
    elif request.tailored_resume_id:
        raise ReviewInputError('tailored_resume_requires_selected_job')
    answers = prepare_answers(request, previous, snapshot_hash, refs, fields)
    if len(answers) > 30:
        raise ReviewInputError('too many accumulated answers')
    current_answer_ids = {answer.question_id for answer in request.answers}
    current_answers = [answer for answer in answers if answer.question_id in current_answer_ids]
    prompt_fields, prompt_answers, is_focused_followup = focused_followup_context(
        fields, answers, current_answers,
    )
    prompt_resume_text = json.dumps(prompt_fields, ensure_ascii=False)
    prompt_job_text = (
        followup_job_prompt_text(job_text, job_source)
        if is_focused_followup
        else review_job_prompt_text(job_text, job_source)
    )
    prompt_time_context = (
        focused_time_context(time_context, current_answers)
        if is_focused_followup
        else time_context
    )
    fingerprint = digest([uid, request.model_dump(), snapshot_hash, job_source, PROMPT_VERSION])
    if request.tailored_resume_id:
        state = db.claim_review(
            request.cohort_id,
            request.resume_id,
            uid,
            request.request_id,
            fingerprint,
            request.tailored_resume_id,
        )
    else:
        state = db.claim_review(
            request.cohort_id, request.resume_id, uid, request.request_id, fingerprint
        )
    if state.get('response'):
        return FirestoreResumeReviewResponse.model_validate(state['response'])
    telemetry = {'model': service._settings.openai_model, 'prompt_version': PROMPT_VERSION,
                 'input_tokens': None, 'output_tokens': None, 'elapsed_ms': None, 'status': 'processing'}
    started = time.monotonic()
    try:
        generated = service._generator({
            'resume_text': prompt_resume_text,
            'confirmed_answers': json.dumps(
                [a.model_dump(exclude={'question_id'}) for a in prompt_answers], ensure_ascii=False,
            ),
            'current_turn_answers': json.dumps(
                [a.model_dump(exclude={'question_id'}) for a in current_answers],
                ensure_ascii=False,
            ),
            'job_posting_text': redact(prompt_job_text),
            'resume_time_context': prompt_time_context,
            'review_scope': (
                '누락 점검 단계입니다. 기존 첨삭을 다시 쓰거나 수정안을 만들지 마세요. '
                '확인된 답변을 존중하고, 아직 확인되지 않은 중요한 사실만 새로운 질문으로 만드세요.'
                if is_gap_audit
                else (
                    '첫 검토입니다. 이력서 전체와 선택 공고를 비교해 검토하세요.'
                    if not is_focused_followup
                    else '후속 첨삭입니다. 이번 답변의 field_path와 같은 이력서 항목만 수정하세요. '
                    '다른 항목의 새 진단·수정·질문은 만들지 마세요.'
                )
            ),
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
        if is_gap_audit:
            # A final audit may discover questions only. It must never replace
            # an already accepted edit with a different model rewrite.
            generated.sentence_reviews = []
            for section in generated.section_reviews:
                section.suggested_revision = None
        grounded, warnings = enforce_resume_review_grounding('\n'.join(fields.values()), generated)
        warnings.extend(ground_sentences(fields, answers, grounded))
        warnings.extend(require_answer_reflection(grounded, current_answers))
        if not is_gap_audit:
            review_count_before_fallback = len(grounded.sentence_reviews)
            warnings.extend(
                add_substantive_answer_fallback(grounded, fields, current_answers)
            )
            if len(grounded.sentence_reviews) > review_count_before_fallback:
                # The deterministic fallback must pass the same provenance,
                # uniqueness and overlap checks as a model-generated edit.
                warnings.extend(ground_sentences(fields, answers, grounded))
                warnings.extend(require_answer_reflection(grounded, current_answers))
        if request.review_mode == 'job':
            prefer_project_evidence_over_surface_edit(grounded, fields, answers)
        if not is_gap_audit:
            apply_selected_job_identity_revisions(
                grounded,
                fields,
                job_source,
                insert_missing_identity=(
                    request.review_mode == 'job'
                    and request.tailored_resume_id is not None
                    and not is_focused_followup
                ),
            )
        changes = normalize_diagnostics(grounded, fields, bool(job_text), previous)
        if not is_focused_followup and not is_gap_audit:
            add_thin_self_introduction_questions(grounded, fields)
            if request.review_mode == 'job':
                add_missing_job_technology_question(grounded, fields, job_text)
        elif not is_gap_audit:
            carry_forward_unanswered_questions(grounded, previous, answers)
        normalize_questions(grounded, fields, answers, request.request_id)
        filter_verified_project_time_questions(grounded, time_context)
        telemetry.update(status='complete', elapsed_ms=round((time.monotonic() - started) * 1000))
        response = FirestoreResumeReviewResponse(
            **grounded.model_dump(), review_id=request.request_id, cohort_id=request.cohort_id,
            resume_id=request.resume_id, grounding_warnings=warnings, input_fields=fields,
            input_hash=snapshot_hash, item_refs=refs, excluded_fields=excluded,
            confirmed_answers=answers, changes=changes, telemetry=telemetry, job_source=job_source,
            tailored_resume_id=request.tailored_resume_id)
        # Persist the response on the claimed document; repeat requests recover it.
        if request.tailored_resume_id:
            db.complete_review(
                request.cohort_id,
                request.resume_id,
                uid,
                request.request_id,
                response.model_dump(),
                request.tailored_resume_id,
            )
        else:
            db.complete_review(
                request.cohort_id, request.resume_id, uid, request.request_id, response.model_dump()
            )
        return response
    except Exception as exc:
        telemetry.update(status='failed', elapsed_ms=round((time.monotonic() - started) * 1000), error_type=type(exc).__name__)
        # Do not release the claim: uncertain model/save outcomes must not silently rebill.
        try:
            if request.tailored_resume_id:
                db.fail_review(
                    request.cohort_id,
                    request.resume_id,
                    uid,
                    request.request_id,
                    telemetry,
                    request.tailored_resume_id,
                )
            else:
                db.fail_review(
                    request.cohort_id, request.resume_id, uid, request.request_id, telemetry
                )
        except Exception:
            pass
        raise
