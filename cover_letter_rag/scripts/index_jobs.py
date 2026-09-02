import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_core.embeddings import Embeddings
from langchain_openai import OpenAIEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter

from app.config import BASE_DIR, get_settings


def load_job_documents(data_directory: Path) -> list[Document]:
    documents: list[Document] = []
    for path in sorted(data_directory.glob("*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        _validate_job(payload, path)
        content = _render_job(payload)
        documents.append(
            Document(
                page_content=content,
                metadata={
                    "job_id": payload["job_id"],
                    "company": payload["company"],
                    "title": payload["title"],
                    "location": payload.get("location", ""),
                    "employment_type": payload.get("employment_type", ""),
                    "source": str(path.relative_to(BASE_DIR)).replace("\\", "/"),
                },
            )
        )
    if not documents:
        raise ValueError(f"No job JSON files found in {data_directory}")
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
    settings = get_settings()
    documents = load_job_documents(data_directory)
    chunks = split_job_documents(documents)
    embedding_function = embeddings or OpenAIEmbeddings(
        model=settings.openai_embedding_model,
        api_key=settings.openai_api_key,
    )
    vector_store = Chroma(
        collection_name=collection_name or settings.chroma_collection_name,
        embedding_function=embedding_function,
        persist_directory=str(persist_directory or settings.chroma_persist_directory),
        collection_metadata={"hnsw:space": "cosine"},
    )
    ids = [_chunk_id(chunk, index) for index, chunk in enumerate(chunks)]
    vector_store.add_documents(chunks, ids=ids)
    return len(documents), len(chunks)


def _validate_job(payload: dict[str, Any], path: Path) -> None:
    required = {"job_id", "company", "title", "summary", "responsibilities", "requirements"}
    missing = sorted(required - payload.keys())
    if missing:
        raise ValueError(f"{path.name} is missing fields: {', '.join(missing)}")
    if not isinstance(payload["requirements"], list) or not payload["requirements"]:
        raise ValueError(f"{path.name} requirements must be a non-empty list")


def _render_job(job: dict[str, Any]) -> str:
    responsibilities = "\n".join(f"- {item}" for item in job["responsibilities"])
    requirements = "\n".join(
        f"- [{item.get('type', '기타')}] {item['text']}"
        for item in job["requirements"]
    )
    preferred = "\n".join(f"- {item}" for item in job.get("preferred", [])) or "- 없음"
    return (
        f"회사: {job['company']}\n"
        f"직무: {job['title']}\n"
        f"근무지: {job.get('location', '미정')}\n"
        f"고용형태: {job.get('employment_type', '미정')}\n\n"
        f"요약\n{job['summary']}\n\n"
        f"주요 업무\n{responsibilities}\n\n"
        f"자격요건\n{requirements}\n\n"
        f"우대사항\n{preferred}"
    )


def _chunk_id(document: Document, index: int) -> str:
    raw = f"{document.metadata['job_id']}:{index}:{document.page_content}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description="Index static job postings into local Chroma")
    parser.add_argument("--data-dir", type=Path, default=BASE_DIR / "data" / "jobs")
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Load and chunk documents without embedding or writing Chroma",
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
