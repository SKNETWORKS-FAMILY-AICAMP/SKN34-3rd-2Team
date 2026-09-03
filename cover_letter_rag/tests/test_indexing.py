import hashlib
from pathlib import Path

from langchain_chroma import Chroma
from langchain_core.embeddings import Embeddings

from app.config import BASE_DIR
from scripts.index_jobs import index_jobs


class DeterministicEmbeddings(Embeddings):
    """Small offline embedding used only to verify the Chroma integration path."""

    dimensions = 32

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        return [self._embed(text) for text in texts]

    def embed_query(self, text: str) -> list[float]:
        return self._embed(text)

    def _embed(self, text: str) -> list[float]:
        digest = hashlib.sha256(text.encode("utf-8")).digest()
        return [byte / 255 for byte in digest[: self.dimensions]]


def test_sample_jobs_are_written_to_and_read_from_chroma(tmp_path: Path) -> None:
    embeddings = DeterministicEmbeddings()
    data_directory = BASE_DIR / "data" / "jobs"
    collection_name = "test_static_jobs"

    job_count, chunk_count = index_jobs(
        data_directory,
        embeddings=embeddings,
        persist_directory=tmp_path,
        collection_name=collection_name,
    )

    store = Chroma(
        collection_name=collection_name,
        embedding_function=embeddings,
        persist_directory=str(tmp_path),
        collection_metadata={"hnsw:space": "cosine"},
    )
    results = store.similarity_search("교육 플랫폼 API", k=3)

    assert job_count == 3
    assert chunk_count >= 3
    assert results
    assert all(result.metadata.get("job_id") for result in results)

