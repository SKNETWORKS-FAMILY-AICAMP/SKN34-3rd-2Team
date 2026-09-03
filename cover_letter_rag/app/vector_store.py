from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_openai import OpenAIEmbeddings

from app.config import Settings
from app.models import JobSearchResult


@dataclass(frozen=True)
class RetrievedJob:
    job_id: str
    company: str
    title: str
    location: str | None
    employment_type: str | None
    source: str
    chunks: tuple[str, ...]

    @property
    def summary(self) -> str:
        text = " ".join(chunk.strip() for chunk in self.chunks if chunk.strip())
        return text[:500]


class JobRepository:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        embeddings = OpenAIEmbeddings(
            model=settings.openai_embedding_model,
            api_key=settings.openai_api_key,
        )
        self._store = Chroma(
            collection_name=settings.chroma_collection_name,
            embedding_function=embeddings,
            persist_directory=str(settings.chroma_persist_directory),
            collection_metadata={"hnsw:space": "cosine"},
        )

    @staticmethod
    def is_index_ready(path: Path) -> bool:
        return path.exists() and any(path.iterdir())

    def search(self, query: str, top_k: int) -> list[RetrievedJob]:
        fetch_k = min(max(top_k * 4, top_k), 40)
        documents: Sequence[Document] = self._store.similarity_search(query, k=fetch_k)

        grouped: dict[str, list[Document]] = {}
        for document in documents:
            job_id = str(document.metadata.get("job_id", "")).strip()
            if not job_id:
                continue
            grouped.setdefault(job_id, []).append(document)
            if len(grouped) >= top_k and all(grouped.values()):
                # Keep walking only until enough distinct jobs are collected.
                continue

        jobs: list[RetrievedJob] = []
        for job_id, chunks in list(grouped.items())[:top_k]:
            metadata = chunks[0].metadata
            jobs.append(
                RetrievedJob(
                    job_id=job_id,
                    company=str(metadata.get("company", "")),
                    title=str(metadata.get("title", "")),
                    location=_optional_text(metadata.get("location")),
                    employment_type=_optional_text(metadata.get("employment_type")),
                    source=str(metadata.get("source", "static_job_posting")),
                    chunks=tuple(document.page_content for document in chunks),
                )
            )
        return jobs


def to_search_results(jobs: list[RetrievedJob]) -> list[JobSearchResult]:
    return [
        JobSearchResult(
            rank=rank,
            job_id=job.job_id,
            company=job.company,
            title=job.title,
            location=job.location,
            employment_type=job.employment_type,
            summary=job.summary,
            source=job.source,
        )
        for rank, job in enumerate(jobs, start=1)
    ]


def _optional_text(value: object) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None

