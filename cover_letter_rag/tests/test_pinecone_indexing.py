from typing import Any

from langchain_core.documents import Document
from langchain_core.embeddings import Embeddings

from app.config import Settings
from scripts.index_jobs import index_documents


class FakeEmbeddings(Embeddings):
    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        return [[0.1, 0.2, 0.3] for _ in texts]

    def embed_query(self, text: str) -> list[float]:
        return [0.1, 0.2, 0.3]


class FakeIndex:
    def __init__(self) -> None:
        self.deleted: list[dict[str, Any]] = []
        self.upserted: list[dict[str, Any]] = []

    def delete(self, **kwargs: Any) -> None:
        self.deleted.append(kwargs)

    def upsert(self, **kwargs: Any) -> None:
        self.upserted.append(kwargs)


def test_pinecone_indexing_replaces_jobs_and_stores_search_metadata() -> None:
    settings = Settings(
        _env_file=None,
        vector_store_provider="pinecone",
        pinecone_dimension=3,
        pinecone_namespace="job-postings",
    )
    index = FakeIndex()
    documents = [
        Document(
            page_content="백엔드 개발자\nFastAPI 기반 API 개발",
            metadata={
                "job_id": "job-1",
                "company": "테스트회사",
                "title": "백엔드 개발자",
                "source": "https://example.test/job-1",
            },
        )
    ]

    chunk_count = index_documents(
        documents,
        embeddings=FakeEmbeddings(),
        settings=settings,
        pinecone_index=index,
    )

    assert chunk_count == 1
    assert index.deleted == [
        {
            "namespace": "job-postings",
            "filter": {"job_id": {"$in": ["job-1"]}},
        }
    ]
    vector = index.upserted[0]["vectors"][0]
    assert vector["values"] == [0.1, 0.2, 0.3]
    assert vector["metadata"]["status"] == "OPEN"
    assert vector["metadata"]["chunk_index"] == 0
    assert vector["metadata"]["chunk_text"] == documents[0].page_content
    assert index.upserted[0]["namespace"] == "job-postings"
