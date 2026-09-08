"""Pinecone 인덱스 생성과 접속.

인덱스 하나를 팀이 같이 쓴다. 키는 저장소 루트 `.env`의 `PINECONE_API_KEY`에서 읽고
코드나 로그에 남기지 않는다.

차원은 임베딩 모델에 묶여 있다. `text-embedding-3-small`은 1536이고, 모델을 바꾸면
인덱스를 새로 만들어야 한다. 그래서 상수로 고정하고 적재할 때 한 번 더 확인한다.
"""

from __future__ import annotations

import os

from job_matching_bot.env import ensure_loaded

INDEX_NAME = "job-posting"
EMBEDDING_MODEL = "text-embedding-3-small"
DIMENSION = 1536
METRIC = "cosine"
CLOUD = "aws"
REGION = "us-east-1"


def api_key() -> str:
    ensure_loaded()
    key = os.environ.get("PINECONE_API_KEY", "").strip()
    if not key:
        raise RuntimeError("PINECONE_API_KEY가 없습니다. 저장소 루트 .env를 확인하세요.")
    return key


def index_name() -> str:
    ensure_loaded()
    return os.environ.get("PINECONE_INDEX", INDEX_NAME).strip() or INDEX_NAME


def namespace() -> str:
    """벡터를 담을 namespace. 비어 있으면 기본 namespace를 쓴다.

    지금은 출처가 사람인 하나뿐이라 비워 둔다. 잡코리아 같은 출처가 늘면
    `saramin` / `jobkorea` 로 나눠 검색이 섞이지 않게 할 수 있다. 옮기려면
    전량을 다시 임베딩해야 하므로 미리 정해 두는 편이 싸다.
    """
    ensure_loaded()
    return os.environ.get("PINECONE_NAMESPACE", "").strip()


def client():
    from pinecone import Pinecone

    return Pinecone(api_key=api_key())


def ensure_index(name: str | None = None) -> dict:
    """인덱스가 없으면 만들고, 있으면 차원·메트릭이 맞는지 확인한다."""
    from pinecone import ServerlessSpec

    name = name or index_name()
    pc = client()
    existing = {i["name"] for i in pc.list_indexes()}
    created = False
    if name not in existing:
        pc.create_index(
            name=name,
            dimension=DIMENSION,
            metric=METRIC,
            spec=ServerlessSpec(cloud=CLOUD, region=REGION),
        )
        created = True

    described = pc.describe_index(name)
    if described.dimension != DIMENSION:
        raise RuntimeError(
            f"인덱스 '{name}'의 차원이 {described.dimension}입니다. "
            f"{EMBEDDING_MODEL}는 {DIMENSION}을 씁니다. 인덱스를 다시 만들어야 합니다."
        )
    return {
        "name": name,
        "created": created,
        "dimension": described.dimension,
        "metric": described.metric,
        "host": described.host,
        # SDK 버전마다 status가 dict, 객체, None으로 달라서 있는 그대로 문자열로 담는다.
        "status": str(described.status) if described.status is not None else "",
    }
