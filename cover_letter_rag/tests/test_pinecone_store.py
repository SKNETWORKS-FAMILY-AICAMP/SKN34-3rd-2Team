from typing import Any

from langchain_core.embeddings import Embeddings

from app.config import Settings
from app.vector_store import JobRepository


class FakeEmbeddings(Embeddings):
    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        return [[0.1, 0.2, 0.3] for _ in texts]

    def embed_query(self, text: str) -> list[float]:
        return [0.1, 0.2, 0.3]


class FakeIndex:
    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []

    def query(self, **kwargs: Any) -> dict[str, Any]:
        self.calls.append(kwargs)
        if kwargs["filter"] == {"status": {"$eq": "OPEN"}}:
            return {
                "matches": [
                    {
                        "score": 0.82,
                        "metadata": {
                            "job_id": "job-1",
                            "company": "테스트회사",
                            "title": "백엔드 개발자",
                            "source": "https://example.test/job-1",
                            "chunk_index": 1,
                            "chunk_text": "자격요건: FastAPI",
                        },
                    },
                    {
                        "score": 0.91,
                        "metadata": {
                            "job_id": "job-1",
                            "company": "테스트회사",
                            "title": "백엔드 개발자",
                            "source": "https://example.test/job-1",
                            "chunk_index": 0,
                            "chunk_text": "주요업무: API 개발",
                        },
                    },
                ]
            }
        return {
            "matches": [
                {
                    "score": 0.0,
                    "metadata": {
                        "job_id": "job-1",
                        "company": "테스트회사",
                        "title": "백엔드 개발자",
                        "source": "https://example.test/job-1",
                        "chunk_index": 0,
                        "chunk_text": "공고 전체 내용",
                    },
                }
            ]
        }


def _settings() -> Settings:
    return Settings(
        _env_file=None,
        vector_store_provider="pinecone",
        pinecone_dimension=3,
        pinecone_namespace="job-postings",
    )


def test_pinecone_search_groups_chunks_by_job() -> None:
    index = FakeIndex()
    repository = JobRepository(
        _settings(), embeddings=FakeEmbeddings(), pinecone_index=index
    )

    jobs = repository.search("FastAPI 경험", top_k=3)

    assert len(jobs) == 1
    assert jobs[0].job_id == "job-1"
    assert jobs[0].score == 0.91
    assert jobs[0].chunks == ("주요업무: API 개발", "자격요건: FastAPI")
    assert index.calls[0]["namespace"] == "job-postings"
    assert index.calls[0]["filter"] == {"status": {"$eq": "OPEN"}}


def test_pinecone_get_uses_job_and_open_status_filter() -> None:
    index = FakeIndex()
    repository = JobRepository(
        _settings(), embeddings=FakeEmbeddings(), pinecone_index=index
    )

    job = repository.get("job-1")

    assert job is not None
    assert job.chunks == ("공고 전체 내용",)
    assert index.calls[0]["vector"] == [0.0, 0.0, 0.0]
    assert index.calls[0]["filter"] == {
        "$and": [
            {"job_id": {"$eq": "job-1"}},
            {"status": {"$eq": "OPEN"}},
        ]
    }
