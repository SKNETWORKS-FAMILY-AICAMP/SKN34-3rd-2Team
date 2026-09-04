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
    industry_code: str | None
    industry_name: str | None
    job_mid_code: str | None
    job_mid_name: str | None
    job_code: str | None
    job_name: str | None
    location_code: str | None
    location: str | None
    employment_type_code: str | None
    employment_type: str | None
    career: str | None
    education: str | None
    job_sectors: tuple[str, ...]
    tech_tags: tuple[str, ...]
    detail_quality: str | None
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
                    industry_code=_optional_text(metadata.get("industry_code")),
                    industry_name=_optional_text(metadata.get("industry_name")),
                    job_mid_code=_optional_text(metadata.get("job_mid_code")),
                    job_mid_name=_optional_text(metadata.get("job_mid_name")),
                    job_code=_optional_text(metadata.get("job_code")),
                    job_name=_optional_text(metadata.get("job_name")),
                    location_code=_optional_text(metadata.get("location_code")),
                    location=_optional_text(metadata.get("location")),
                    employment_type_code=_optional_text(
                        metadata.get("employment_type_code")
                    ),
                    employment_type=_optional_text(metadata.get("employment_type")),
                    career=_optional_text(metadata.get("career")),
                    education=_optional_text(metadata.get("education")),
                    job_sectors=_split_metadata_list(metadata.get("job_sectors")),
                    tech_tags=_split_metadata_list(metadata.get("tech_tags")),
                    detail_quality=_optional_text(metadata.get("detail_quality")),
                    source=str(metadata.get("source", "static_job_posting")),
                    chunks=tuple(document.page_content for document in chunks),
                )
            )
        return jobs

    def get(self, job_id: str) -> RetrievedJob | None:
        result = self._store.get(
            where={"job_id": job_id},
            include=["documents", "metadatas"],
        )
        documents = result.get("documents") or []
        metadatas = result.get("metadatas") or []
        if not documents or not metadatas:
            return None
        metadata = metadatas[0]
        return _retrieved_job(job_id, metadata, tuple(str(item) for item in documents))


def to_search_results(jobs: list[RetrievedJob]) -> list[JobSearchResult]:
    return [
        JobSearchResult(
            rank=rank,
            job_id=job.job_id,
            company=job.company,
            title=job.title,
            industry_code=job.industry_code,
            industry_name=job.industry_name,
            job_mid_code=job.job_mid_code,
            job_mid_name=job.job_mid_name,
            job_code=job.job_code,
            job_name=job.job_name,
            location_code=job.location_code,
            location=job.location,
            employment_type_code=job.employment_type_code,
            employment_type=job.employment_type,
            career=job.career,
            education=job.education,
            job_sectors=list(job.job_sectors),
            tech_tags=list(job.tech_tags),
            detail_quality=job.detail_quality,
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


def _split_metadata_list(value: object) -> tuple[str, ...]:
    text = _optional_text(value)
    if not text:
        return ()
    return tuple(item.strip() for item in text.split(",") if item.strip())


def _retrieved_job(
    job_id: str,
    metadata: dict[str, object],
    chunks: tuple[str, ...],
) -> RetrievedJob:
    return RetrievedJob(
        job_id=job_id,
        company=str(metadata.get("company", "")),
        title=str(metadata.get("title", "")),
        industry_code=_optional_text(metadata.get("industry_code")),
        industry_name=_optional_text(metadata.get("industry_name")),
        job_mid_code=_optional_text(metadata.get("job_mid_code")),
        job_mid_name=_optional_text(metadata.get("job_mid_name")),
        job_code=_optional_text(metadata.get("job_code")),
        job_name=_optional_text(metadata.get("job_name")),
        location_code=_optional_text(metadata.get("location_code")),
        location=_optional_text(metadata.get("location")),
        employment_type_code=_optional_text(metadata.get("employment_type_code")),
        employment_type=_optional_text(metadata.get("employment_type")),
        career=_optional_text(metadata.get("career")),
        education=_optional_text(metadata.get("education")),
        job_sectors=_split_metadata_list(metadata.get("job_sectors")),
        tech_tags=_split_metadata_list(metadata.get("tech_tags")),
        detail_quality=_optional_text(metadata.get("detail_quality")),
        source=str(metadata.get("source", "static_job_posting")),
        chunks=chunks,
    )
