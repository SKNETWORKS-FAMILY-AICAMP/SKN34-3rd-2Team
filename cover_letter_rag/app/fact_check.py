"""후속 첨삭 수정안이 원문에 한 일·결과로 적힌 사실을 빼거나 약하게 바꿨는지 보는 검사.

"결제 위젯 연동을 구현했습니다"가 "결제 위젯을 연동하기 위해"로, "처리 시간을 줄였습니다"가 "줄이는 업무를 맡았습니다"로
바뀌면 숫자·기술어는 그대로라 낱말 검사를 지나간다(2026-09-15 한 번도 안 본 케이스). 뜻 변화라 낱말 목록으로는
처음 보는 표현을 놓친다(STAR 결과 낱말 확인이 최종 확인용에서 54/58 → 48/58로 떨어졌다). 그래서 모델에 짧게 묻고,
모델이 적은 원문 구절이 원문에 실제로 있을 때만 안내를 붙인다. 수정안은 막지 않는다(검사 모델도 틀릴 수 있다).

비용을 줄이려고 원문과 달라진 내용 수정안(변경 폭 0.15 이상, 턴당 4개까지)만, 한 턴에 여러 개면 동시에 묻는다.
"""
from __future__ import annotations

import re
import time
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor

from pydantic import Field

from app.models import StrictModel

# 변경 폭 0.245인 수정안이 원문 문장 하나를 지웠다(2026-09-15 한 번도 안 본 케이스). 검사는 평균 1.4초라 범위를 넓힌다.
FACT_CHECK_MIN_CHANGE_RATE = 0.15
MAX_FACT_CHECKS_PER_TURN = 4


class WeakenedFact(StrictModel):
    original_phrase: str = Field(description="원문에서 한 일·결과로 적힌 구절. 원문에 있는 그대로 연속 인용")
    revision_phrase: str = Field(default='', description="수정안에서 그 사실이 바뀐 구절. 빠졌으면 빈 문자열")
    change: str = Field(description="dropped(빠짐), purpose(목적·의도로 바뀜), plan(계획·예정으로 바뀜), "
                                    "role(맡음·참여로만 바뀜), learning(배움으로 바뀜) 중 하나")


class FactKeepCheck(StrictModel):
    weakened: list[WeakenedFact] = Field(default_factory=list)


FACT_CHECK_SYSTEM = """너는 이력서 수정안이 원문의 사실을 지켰는지 확인한다.
원문에서 지원자가 이미 한 일·만든 것·얻은 결과로 적힌 구절 중, 수정안에서 빠졌거나 약해진 것만 weakened에 적는다.
약해졌다는 것은 한 일이 목적·의도('~하기 위해'), 계획·예정, 맡음·참여만, 배움으로 바뀐 경우다.
- 표현이나 어순만 바뀌고 한 일·결과가 그대로면 적지 않는다.
- 사용자 답변이 그 사실을 고치거나 뺐다면 약해진 것이 아니다.
- 원문에 원래 목적·계획으로 적힌 것은 적지 않는다.
- original_phrase는 원문에 있는 그대로의 연속 구절이다. 없으면 weakened를 비운다."""


def build_fact_checker(settings) -> Callable[[str, str, str], FactKeepCheck]:
    from langchain_core.prompts import ChatPromptTemplate
    from langchain_openai import ChatOpenAI

    model = ChatOpenAI(
        model=settings.openai_model,
        api_key=settings.openai_api_key,
        use_responses_api=True,
        reasoning_effort='low',
        max_retries=0,
    )
    prompt = ChatPromptTemplate.from_messages([
        ('system', FACT_CHECK_SYSTEM),
        ('human', '[원문]\n{original}\n\n[수정안]\n{revision}\n\n[사용자 답변]\n{answer}'),
    ])
    chain = prompt | model.with_structured_output(FactKeepCheck, method='json_schema')

    def check(original: str, revision: str, answer: str) -> FactKeepCheck:
        return chain.invoke({'original': original, 'revision': revision, 'answer': answer or '없음'})

    return check


_CHANGE_WORDS = {'dropped': '빠졌어요', 'purpose': '목적 표현으로 바뀌었어요', 'plan': '계획 표현으로 바뀌었어요',
                 'role': '맡았다는 말로만 바뀌었어요', 'learning': '배웠다는 말로 바뀌었어요'}


def _squash(text: str) -> str:
    return re.sub(r'\s+', '', str(text or ''))


def add_fact_notices(generation, answers, checker, telemetry) -> None:
    """변경 폭이 큰 내용 수정안마다 검사 모델에 묻고, 원문에 실제로 있는 구절만 안내로 붙인다."""
    if checker is None:
        return
    answer_text = '\n'.join(str(answer.answer) for answer in answers)
    targets = [
        review for review in generation.sentence_reviews
        if review.suggested_revision and review.new_item is None and review.edit_type == 'content'
        and (review.change_rate or 0) >= FACT_CHECK_MIN_CHANGE_RATE
    ][:MAX_FACT_CHECKS_PER_TURN]
    if not targets:
        return
    started = time.monotonic()

    def run(review):
        try:
            return checker(review.original_quote, review.suggested_revision, answer_text)
        except Exception:  # noqa: BLE001 — 검사가 실패해도 수정안은 그대로 보여 준다
            return None

    with ThreadPoolExecutor(max_workers=len(targets)) as pool:
        results = list(pool.map(run, targets))
    for review, result in zip(targets, results):
        if not result:
            continue
        found = [fact for fact in result.weakened
                 if _squash(fact.original_phrase) and _squash(fact.original_phrase) in _squash(review.original_quote)
                 and not (fact.revision_phrase == '' and _squash(fact.original_phrase) in _squash(review.suggested_revision))]
        if found:
            fact = found[0]
            review.fact_notice = (f"원문의 '{fact.original_phrase.strip()}'이(가) 수정안에서 "
                                  f"{_CHANGE_WORDS.get(fact.change, '약해졌어요')}. 한 일이 그대로 드러나는지 확인해 주세요.")
    telemetry.update(fact_checks=len(targets), fact_check_ms=round((time.monotonic() - started) * 1000),
                     fact_notices=sum(1 for review in targets if review.fact_notice))
