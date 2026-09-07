from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

from langchain_chroma import Chroma
from langchain_core.embeddings import Embeddings
from langchain_openai import OpenAIEmbeddings
from pinecone import Pinecone

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
    score: float | None = None

    @property
    def summary(self) -> str:
        text = " ".join(chunk.strip() for chunk in self.chunks if chunk.strip())
        return text[:500]


class JobStore(Protocol):
    def search(self, query: str, top_k: int) -> list[RetrievedJob]: ...

    def get(self, job_id: str) -> RetrievedJob | None: ...


class JobRepository:
    def __init__(
        self,
        settings: Settings,
        *,
        embeddings: Embeddings | None = None,
        pinecone_index: Any | None = None,
    ) -> None:
        embedding_function = embeddings or OpenAIEmbeddings(
            model=settings.openai_embedding_model,
            api_key=settings.openai_api_key,
        )
        if settings.vector_store_provider == "pinecone":
            self._store: JobStore = PineconeJobStore(
                settings,
                embedding_function,
                index=pinecone_index,
            )
        else:
            self._store = ChromaJobStore(settings, embedding_function)

    @staticmethod
    def is_index_ready(settings: Settings) -> bool:
        if settings.vector_store_provider == "chroma":
            path = Path(settings.chroma_persist_directory)
            return path.exists() and any(path.iterdir())
        if not settings.pinecone_api_key:
            return False
        try:
            client = Pinecone(api_key=settings.pinecone_api_key)
            index = _pinecone_index(client, settings)
            stats = index.describe_index_stats()
            namespaces = _field(stats, "namespaces", {}) or {}
            namespace = namespaces.get(settings.pinecone_namespace)
            return int(_field(namespace, "vector_count", 0) or 0) > 0
        except Exception:
            return False

    def search(self, query: str, top_k: int) -> list[RetrievedJob]:
        return self._store.search(query, top_k)

    def get(self, job_id: str) -> RetrievedJob | None:
        return self._store.get(job_id)


class ChromaJobStore:
    def __init__(self, settings: Settings, embeddings: Embeddings) -> None:
        self._store = Chroma(
            collection_name=settings.chroma_collection_name,
            embedding_function=embeddings,
            persist_directory=str(settings.chroma_persist_directory),
        )

    def search(self, query: str, top_k: int) -> list[RetrievedJob]:
        fetch_k = min(max(top_k * 4, top_k), 40)
        results = self._store.similarity_search_with_relevance_scores(
            query, k=fetch_k
        )
        grouped: dict[str, list[tuple[Any, float]]] = defaultdict(list)
        for document, score in results:
            job_id = str(document.metadata.get("job_id", "")).strip()
            if job_id:
                grouped[job_id].append((document, float(score)))
        jobs: list[RetrievedJob] = []
        for job_id, matches in list(grouped.items())[:top_k]:
            documents = [match[0] for match in matches]
            jobs.append(
                _retrieved_job(
                    job_id,
                    documents[0].metadata,
                    tuple(document.page_content for document in documents),
                    max(match[1] for match in matches),
                )
            )
        return jobs

    def get(self, job_id: str) -> RetrievedJob | None:
        result = self._store.get(where={"job_id": job_id})
        documents = result.get("documents") or []
        metadatas = result.get("metadatas") or []
        if not documents:
            return None
        metadata = metadatas[0] if metadatas else {}
        return _retrieved_job(
            job_id,
            metadata,
            tuple(str(item) for item in documents),
        )


class PineconeJobStore:
    def __init__(
        self,
        settings: Settings,
        embeddings: Embeddings,
        *,
        index: Any | None = None,
    ) -> None:
        if index is None:
            if not settings.pinecone_api_key:
                raise ValueError("PINECONE_API_KEY is not configured on the server")
            index = _pinecone_index(
                Pinecone(api_key=settings.pinecone_api_key), settings
            )
        self._index = index
        self._embeddings = embeddings
        self._namespace = settings.pinecone_namespace
        self._dimension = settings.pinecone_dimension

    def search(self, query: str, top_k: int) -> list[RetrievedJob]:
        response = self._index.query(
            vector=self._embeddings.embed_query(query),
            top_k=min(max(top_k * 4, top_k), 40),
            namespace=self._namespace,
            include_metadata=True,
            include_values=False,
            filter={"status": {"$eq": "OPEN"}},
        )
        grouped: dict[str, list[Any]] = defaultdict(list)
        for match in _matches(response):
            metadata = _field(match, "metadata", {}) or {}
            job_id = str(metadata.get("job_id", ""))
            if job_id:
                grouped[job_id].append(match)

        jobs = [_group_matches(job_id, matches) for job_id, matches in grouped.items()]
        jobs.sort(
            key=lambda item: item.score if item.score is not None else -1,
            reverse=True,
        )
        return jobs[:top_k]

    def get(self, job_id: str) -> RetrievedJob | None:
        response = self._index.query(
            vector=[0.0] * self._dimension,
            top_k=100,
            namespace=self._namespace,
            include_metadata=True,
            include_values=False,
            filter={
                "$and": [
                    {"job_id": {"$eq": job_id}},
                    {"status": {"$eq": "OPEN"}},
                ]
            },
        )
        matches = _matches(response)
        return _group_matches(job_id, matches) if matches else None


def _pinecone_index(client: Pinecone, settings: Settings) -> Any:
    if settings.pinecone_index_host:
        return client.Index(host=settings.pinecone_index_host)
    return client.Index(settings.pinecone_index_name)


def _matches(response: Any) -> list[Any]:
    return list(_field(response, "matches", []) or [])


def _field(value: Any, name: str, default: Any = None) -> Any:
    if value is None:
        return default
    if isinstance(value, dict):
        return value.get(name, default)
    return getattr(value, name, default)


def _group_matches(job_id: str, matches: list[Any]) -> RetrievedJob:
    ordered = sorted(
        matches,
        key=lambda match: int(
            (_field(match, "metadata", {}) or {}).get("chunk_index", 0)
        ),
    )
    metadata = _field(ordered[0], "metadata", {}) or {}
    contents = [
        str((_field(match, "metadata", {}) or {}).get("chunk_text", ""))
        for match in ordered
    ]
    score_values = [
        float(score)
        for match in ordered
        if (score := _field(match, "score")) is not None
    ]
    return _retrieved_job(
        job_id,
        metadata,
        tuple(item for item in contents if item),
        max(score_values) if score_values else None,
    )


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
    if isinstance(value, list):
        return tuple(str(item).strip() for item in value if str(item).strip())
    text = _optional_text(value)
    if not text:
        return ()
    return tuple(item.strip() for item in text.split(",") if item.strip())


def _retrieved_job(
    job_id: str,
    metadata: dict[str, Any],
    chunks: tuple[str, ...],
    score: float | None = None,
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
        score=score,
    )
