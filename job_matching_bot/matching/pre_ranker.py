"""후보를 LLM에 넘기기 전에 다시 세운다 — 벡터 순위와 기술 겹침을 섞어서.

## 왜 필요한가

벡터 검색이 매긴 순서는 후보 안에서 거의 평평하다. 6개 이력서로 재 보니 후보 12~17건의
유사도 폭이 0.042~0.140뿐이었다. 그 좁은 구간의 순서로 "누구를 먼저 보여줄지"와
"누구를 LLM에 보낼지"를 정하고 있었다.

기술 겹침은 훨씬 넓게 흩어지고(0~67%), LLM이 매긴 적합도와도 깨끗하게 이어진다.
후보 79건을 전부 판정시켜 본 결과다.

    높음 30% · 보통 19% · 낮음 10%   (적합도별 평균 겹침)

판정과의 순위상관도 기술 겹침(+0.33)이 벡터 순위(+0.26)보다 높았다. 둘을 반씩 섞으면
+0.42로 올라간다 — 어느 한쪽만 쓸 때보다 낫다. 가중치는 0.4~0.7 구간이 고르게 좋아서
가운데인 0.5로 둔다. 표본이 6개 이력서라 소수점까지 맞추는 것은 과적합이다.

## 정보가 없는 공고를 벌주지 않는다

인덱스에 올라간 공고의 **53%가 기술 정보를 아예 안 갖고 있다.** 겹침을 0으로 치면
"정보 없음"이 "안 맞음"이 되어 그 공고들이 통째로 뒤로 밀린다. 그래서 정보가 없는
공고는 그 요청의 평균 겹침으로 두어 **제자리에 남긴다.** 근거가 없으면 움직이지 않는
것이 맞다.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence, TypeVar

from job_matching_bot.matching.skill_normalize import canonical_set
from job_matching_bot.schemas.job_posting import Job

# 기술 겹침에 줄 비중. 나머지는 벡터 유사도 몫이다.
SKILL_WEIGHT = 0.5


@dataclass(frozen=True)
class SkillMatch:
    """공고가 요구하는 기술 중 이력서가 가진 것."""

    matched: tuple[str, ...]
    pool_size: int

    @property
    def coverage(self) -> float | None:
        """겹친 비율. 공고에 기술 정보가 없으면 None — 0이 아니다."""
        if self.pool_size == 0:
            return None
        return len(self.matched) / self.pool_size


def skill_match(job: Job, resume_skills: Sequence[str]) -> SkillMatch:
    """공고의 요구 기술과 이력서 기술을 표준 키로 맞대어 본다.

    `required_skills`와 `tech_stack`을 합쳐서 본다. 전자는 본문에서 뽑은 요건이고
    후자는 기업이 등록한 태그인데, 저장소에서 각각 26%·35%만 채워져 있어 한쪽만
    보면 볼 수 있는 공고가 절반으로 줄어든다.
    """
    pool = canonical_set(list(job.required_skills)) | canonical_set(list(job.tech_stack))
    mine = canonical_set(list(resume_skills))
    return SkillMatch(matched=tuple(sorted(pool & mine)), pool_size=len(pool))


def _normalized(values: list[float]) -> list[float]:
    """0~1로 편다. 전부 같으면 가운데(0.5)로 — 순서를 만들어내지 않는다."""
    low, high = min(values), max(values)
    if high <= low:
        return [0.5] * len(values)
    return [(v - low) / (high - low) for v in values]


T = TypeVar("T")


def pre_rank(
    candidates: Sequence[T],
    scores: Sequence[float],
    matches: Sequence[SkillMatch],
    *,
    weight: float = SKILL_WEIGHT,
) -> list[T]:
    """섞은 점수가 높은 순으로 다시 세운다. 같으면 들어온 순서를 지킨다.

    `scores`는 벡터 유사도(클수록 좋다), `matches`는 같은 자리의 기술 겹침이다.
    셋의 길이가 같아야 한다.
    """
    if len(candidates) != len(scores) or len(candidates) != len(matches):
        raise ValueError("후보·점수·겹침의 개수가 다릅니다")
    if len(candidates) < 2:
        return list(candidates)

    known = [m.coverage for m in matches if m.coverage is not None]
    # 기술 정보가 없는 공고는 이 값을 받아 제자리에 남는다.
    neutral = sum(known) / len(known) if known else 0.0

    vectors = _normalized(list(scores))
    blended = [
        (1 - weight) * v + weight * (m.coverage if m.coverage is not None else neutral)
        for v, m in zip(vectors, matches)
    ]
    order = sorted(range(len(candidates)), key=lambda i: (-blended[i], i))
    return [candidates[i] for i in order]
