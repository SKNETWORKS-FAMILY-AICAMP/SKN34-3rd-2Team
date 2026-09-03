"""검증된 학습 자료 Catalog.

모델이 존재하지 않는 강의나 URL을 만들어내지 않도록, 학습 추천은 이 목록에
있는 항목에서만 고른다. `last_checked_at`의 `TEST_FIXTURE`는 실시간 링크
검증을 거치지 않았다는 뜻이다.
"""

from typing import Any

LEARNING_CATALOG: dict[str, dict[str, Any]] = {
    "kubernetes": {
        "catalog_id": "fixture-k8s-001",
        "provider": "Kubernetes 공식 문서",
        "title": "Kubernetes Basics",
        "url": "https://kubernetes.io/docs/tutorials/kubernetes-basics/",
        "level": "입문",
        "estimated_duration": "2~3시간",
        "last_checked_at": "TEST_FIXTURE",
    },
    "redis": {
        "catalog_id": "fixture-redis-001",
        "provider": "Redis 공식 문서",
        "title": "Redis Get started",
        "url": "https://redis.io/docs/latest/get-started/",
        "level": "입문",
        "estimated_duration": "1~2시간",
        "last_checked_at": "TEST_FIXTURE",
    },
}


def find_learning_item(skill: str) -> dict[str, Any] | None:
    return LEARNING_CATALOG.get(skill.lower())
