"""매칭 엔진: 명시 조건 Hard Filter와 추천 Ranking.

이 레이어는 이미 정규화된 `Job`만 받는다. 수집·정규화는 `ingestion`의 책임이다.
"""

from job_matching_bot.matching.hard_filter import hard_filter
from job_matching_bot.matching.ranking import rank_jobs

__all__ = ["hard_filter", "rank_jobs"]
