import argparse
import hashlib
import json
import time
from pathlib import Path
from typing import Any, Callable, Literal, TypeVar

from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_core.embeddings import Embeddings
from langchain_openai import OpenAIEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter
from pinecone import Pinecone, ServerlessSpec
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from app.config import BASE_DIR, Settings, get_settings
from app.saramin import SaraminJob, SaraminJobSearchResponse


class JobRequirement(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["필수", "우대", "업무", "기타"] = "기타"
    text: str = Field(min_length=1)


class JobEnrichment(BaseModel):
    model_config = ConfigDict(extra="forbid")

    job_id: str
    summary: str = Field(min_length=1)
    responsibilities: list[str] = Field(min_length=1)
    requirements: list[JobRequirement] = Field(min_length=1)
    preferred: list[str] = Field(default_factory=list)


def load_job_documents(
    data_directory: Path,
    enrichment_directory: Path | None = None,
) -> list[Document]:
    documents: list[Document] = []
    enrichments = _load_enrichments(
        enrichment_directory or data_directory.parent / "job_enrichments"
    )
    for path in sorted(data_directory.glob("*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        try:
            response = SaraminJobSearchResponse.model_validate(payload)
        except ValidationError as error:
            raise ValueError(f"{path.name} is not a valid Saramin response: {error}") from error

        if response.jobs.count != len(response.jobs.job):
            raise ValueError(
                f"{path.name} jobs.count does not match the number of jobs.job items"
            )

        for job in response.jobs.job:
            enrichment = enrichments.get(job.id)
            if enrichment is None:
                raise ValueError(
                    f"{path.name} job id {job.id} has no matching enrichment JSON"
                )
            documents.append(
                Document(
                    page_content=_render_job(job, enrichment),
                    metadata={
                        "job_id": job.id,
                        "company": job.company.detail.name,
                        "title": job.position.title,
                        "industry_code": str(job.position.industry.code),
                        "industry_name": job.position.industry.name,
                        "job_mid_code": str(job.position.job_mid_code.code),
                        "job_mid_name": job.position.job_mid_code.name,
                        "job_code": str(job.position.job_code.code),
                        "job_name": job.position.job_code.name,
                        "location_code": str(job.position.location.code),
                        "location": job.position.location.name,
                        "employment_type_code": str(job.position.job_type.code),
                        "employment_type": job.position.job_type.name,
                        "source": job.url,
                        "source_file": str(path.relative_to(BASE_DIR)).replace("\\", "/"),
                    },
                )
            )
    if not documents:
        raise ValueError(f"No Saramin jobs found in {data_directory}")
    return documents


def split_job_documents(documents: list[Document]) -> list[Document]:
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=900,
        chunk_overlap=150,
        separators=["\n\n", "\n", ". ", " ", ""],
    )
    return splitter.split_documents(documents)


def index_jobs(
    data_directory: Path,
    *,
    embeddings: Embeddings | None = None,
    persist_directory: Path | None = None,
    collection_name: str | None = None,
) -> tuple[int, int]:
    documents = load_job_documents(data_directory)
    chunk_count = index_documents(
        documents,
        embeddings=embeddings,
        persist_directory=persist_directory,
        collection_name=collection_name,
    )
    return len(documents), chunk_count


def index_documents(
    documents: list[Document],
    *,
    embeddings: Embeddings | None = None,
    persist_directory: Path | None = None,
    collection_name: str | None = None,
    settings: Settings | None = None,
    pinecone_index: Any | None = None,
) -> int:
    settings = settings or get_settings()
    chunks = split_job_documents(documents)
    embedding_function = embeddings or OpenAIEmbeddings(
        model=settings.openai_embedding_model,
        api_key=settings.openai_api_key,
    )
    if (
        settings.vector_store_provider == "chroma"
        or persist_directory is not None
        or collection_name is not None
    ):
        return _index_chroma(
            chunks,
            embedding_function,
            persist_directory or settings.chroma_persist_directory,
            collection_name or settings.chroma_collection_name,
        )

    index = pinecone_index or _prepare_pinecone_index(settings)
    return _index_pinecone(chunks, embedding_function, index, settings)


def _index_chroma(
    chunks: list[Document],
    embeddings: Embeddings,
    persist_directory: Path,
    collection_name: str,
) -> int:
    vector_store = Chroma(
        collection_name=collection_name,
        embedding_function=embeddings,
        persist_directory=str(persist_directory),
        collection_metadata={"hnsw:space": "cosine"},
    )
    ids = [_chunk_id(chunk, index) for index, chunk in enumerate(chunks)]
    vector_store.add_documents(chunks, ids=ids)
    return len(chunks)


def _prepare_pinecone_index(settings: Settings) -> Any:
    if not settings.pinecone_api_key:
        raise ValueError("PINECONE_API_KEY is required for Pinecone indexing")
    client = Pinecone(api_key=settings.pinecone_api_key)
    names = set(client.list_indexes().names())
    if settings.pinecone_index_name not in names:
        client.create_index(
            name=settings.pinecone_index_name,
            dimension=settings.pinecone_dimension,
            metric="cosine",
            spec=ServerlessSpec(
                cloud=settings.pinecone_cloud,
                region=settings.pinecone_region,
            ),
        )
    description = client.describe_index(settings.pinecone_index_name)
    dimension = int(_value(description, "dimension", 0))
    metric = str(_value(description, "metric", ""))
    if dimension != settings.pinecone_dimension or metric != "cosine":
        raise ValueError(
            "Pinecone index configuration mismatch: "
            f"expected dimension={settings.pinecone_dimension}, metric=cosine; "
            f"actual dimension={dimension}, metric={metric}"
        )
    if settings.pinecone_index_host:
        return client.Index(host=settings.pinecone_index_host)
    return client.Index(settings.pinecone_index_name)


def _index_pinecone(
    chunks: list[Document],
    embeddings: Embeddings,
    index: Any,
    settings: Settings,
    *,
    batch_size: int = 96,
) -> int:
    prepared = _prepare_chunks(chunks)
    chunks_by_job: dict[str, list[Document]] = {}
    for chunk in prepared:
        chunks_by_job.setdefault(str(chunk.metadata["job_id"]), []).append(chunk)

    for job_batch in _batched(sorted(chunks_by_job), 50):
        document_batch = [
            chunk for job_id in job_batch for chunk in chunks_by_job[job_id]
        ]
        payloads: list[list[dict[str, Any]]] = []
        for chunk_batch in _batched(document_batch, batch_size):
            vectors = embeddings.embed_documents(
                [chunk.page_content for chunk in chunk_batch]
            )
            if any(len(vector) != settings.pinecone_dimension for vector in vectors):
                raise ValueError(
                    "Embedding dimension does not match PINECONE_DIMENSION "
                    f"({settings.pinecone_dimension})"
                )
            payloads.append(
                [
                    {
                        "id": _chunk_id(chunk, int(chunk.metadata["chunk_index"])),
                        "values": vector,
                        "metadata": _pinecone_metadata(chunk),
                    }
                    for chunk, vector in zip(chunk_batch, vectors, strict=True)
                ]
            )

        # Embed first so an embedding failure cannot remove a valid existing job.
        _with_retry(
            lambda job_batch=job_batch: index.delete(
                namespace=settings.pinecone_namespace,
                filter={"job_id": {"$in": job_batch}},
            )
        )
        for payload in payloads:
            _with_retry(
                lambda payload=payload: index.upsert(
                    vectors=payload,
                    namespace=settings.pinecone_namespace,
                )
            )
    return len(prepared)


def _prepare_chunks(chunks: list[Document]) -> list[Document]:
    counters: dict[str, int] = {}
    prepared: list[Document] = []
    for chunk in chunks:
        job_id = str(chunk.metadata["job_id"])
        chunk_index = counters.get(job_id, 0)
        counters[job_id] = chunk_index + 1
        metadata = {
            **chunk.metadata,
            "job_id": job_id,
            "chunk_index": chunk_index,
            "chunk_text": chunk.page_content,
            "status": str(chunk.metadata.get("status", "OPEN")).upper(),
        }
        prepared.append(Document(page_content=chunk.page_content, metadata=metadata))
    return prepared


def _pinecone_metadata(document: Document) -> dict[str, Any]:
    allowed = (str, int, float, bool)
    metadata: dict[str, Any] = {}
    for key, value in document.metadata.items():
        if isinstance(value, allowed):
            metadata[key] = value
        elif isinstance(value, list) and all(isinstance(item, str) for item in value):
            metadata[key] = value
    return metadata


T = TypeVar("T")


def _batched(items: list[T], size: int) -> list[list[T]]:
    return [items[index : index + size] for index in range(0, len(items), size)]


def _with_retry(operation: Callable[[], T], attempts: int = 5) -> T:
    for attempt in range(attempts):
        try:
            return operation()
        except Exception:
            if attempt == attempts - 1:
                raise
            time.sleep(2**attempt)
    raise RuntimeError("unreachable")


def _value(value: Any, name: str, default: Any = None) -> Any:
    if isinstance(value, dict):
        return value.get(name, default)
    return getattr(value, name, default)


def _load_enrichments(enrichment_directory: Path) -> dict[str, JobEnrichment]:
    enrichments: dict[str, JobEnrichment] = {}
    for path in sorted(enrichment_directory.glob("*.json")):
        try:
            enrichment = JobEnrichment.model_validate_json(
                path.read_text(encoding="utf-8")
            )
        except ValidationError as error:
            raise ValueError(f"{path.name} is not a valid enrichment: {error}") from error
        if enrichment.job_id in enrichments:
            raise ValueError(f"Duplicate enrichment job_id: {enrichment.job_id}")
        enrichments[enrichment.job_id] = enrichment
    return enrichments


def _render_job(job: SaraminJob, enrichment: JobEnrichment) -> str:
    responsibilities = "\n".join(f"- {item}" for item in enrichment.responsibilities)
    requirements = "\n".join(
        f"- [{item.type}] {item.text}"
        for item in enrichment.requirements
    )
    preferred = "\n".join(f"- {item}" for item in enrichment.preferred) or "- 없음"
    return (
        f"공고 ID: {job.id}\n"
        f"회사: {job.company.detail.name}\n"
        f"직무: {job.position.title}\n"
        f"산업: {job.position.industry.name} ({job.position.industry.code})\n"
        f"직무 분류: {job.position.job_mid_code.name} ({job.position.job_mid_code.code})\n"
        f"직무 키워드: {job.position.job_code.name} ({job.position.job_code.code})\n"
        f"근무지: {job.position.location.name}\n"
        f"고용형태: {job.position.job_type.name}\n"
        f"경력: {job.position.experience_level.name}\n"
        f"학력: {job.position.required_education_level.name}\n"
        f"키워드: {job.keyword}\n\n"
        f"요약\n{enrichment.summary}\n\n"
        f"주요 업무\n{responsibilities}\n\n"
        f"자격요건\n{requirements}\n\n"
        f"우대사항\n{preferred}"
    )


def _chunk_id(document: Document, index: int) -> str:
    raw = f"{document.metadata['job_id']}:{index}:{document.page_content}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Index Saramin-shaped static job postings into the configured vector store"
    )
    parser.add_argument("--data-dir", type=Path, default=BASE_DIR / "data" / "jobs")
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Load and chunk documents without embedding or writing the vector store",
    )
    args = parser.parse_args()

    if args.validate_only:
        documents = load_job_documents(args.data_dir)
        chunks = split_job_documents(documents)
        print(f"validated jobs={len(documents)} chunks={len(chunks)}")
        return

    document_count, chunk_count = index_jobs(args.data_dir)
    print(f"indexed jobs={document_count} chunks={chunk_count}")


if __name__ == "__main__":
    main()
