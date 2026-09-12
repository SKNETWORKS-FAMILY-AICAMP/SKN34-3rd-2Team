from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import AliasChoices, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


BASE_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = BASE_DIR.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=REPO_ROOT / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_env: str = "local"
    openai_api_key: str | None = Field(default=None, repr=False)
    openai_model: str = "gpt-5.6-luna"
    openai_embedding_model: str = "text-embedding-3-small"
    openai_reasoning_effort: Literal["none", "low", "medium", "high", "xhigh", "max"] = "medium"
    vector_store_provider: Literal["pinecone", "chroma"] = "pinecone"
    # 채용공고 인덱스는 공지·정책 인덱스와 다른 계정을 쓴다. 키 이름을 나눠
    # 두 인덱스가 서로의 자격증명을 물고 들어가지 않게 한다.
    pinecone_api_key: str | None = Field(
        default=None,
        repr=False,
        validation_alias=AliasChoices("PINECONE_API_KEY1", "PINECONE_API_KEY"),
    )
    pinecone_index_name: str = "job-postings"
    pinecone_namespace: str = "saramin"
    pinecone_index_host: str | None = None
    pinecone_dimension: int = Field(default=1536, ge=1)
    pinecone_cloud: str = "aws"
    pinecone_region: str = "us-east-1"
    chroma_persist_directory: Path = BASE_DIR / "chroma_db"
    chroma_collection_name: str = "static_job_postings"
    retrieval_top_k: int = Field(default=4, ge=1, le=10)
    firebase_project_id: str | None = None
    firestore_cohorts_collection: str = "cohorts"
    firestore_resumes_collection: str = "resumes"
    firestore_ai_reviews_collection: str = "aiReviews"
    matching_job_store_path: Path = BASE_DIR.parent / "job_matching_bot" / "artifacts" / "job_store.sqlite"

    @field_validator("chroma_persist_directory", mode="before")
    @classmethod
    def resolve_chroma_path(cls, value: object) -> Path:
        path = Path(str(value))
        return path if path.is_absolute() else BASE_DIR / path


@lru_cache
def get_settings() -> Settings:
    return Settings()
