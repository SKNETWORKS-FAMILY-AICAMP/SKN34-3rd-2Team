from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


BASE_DIR = Path(__file__).resolve().parents[1]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=BASE_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_env: str = "local"
    openai_api_key: str | None = Field(default=None, repr=False)
    openai_model: str = "gpt-5.6-luna"
    openai_embedding_model: str = "text-embedding-3-small"
    openai_reasoning_effort: Literal["none", "low", "medium", "high", "xhigh", "max"] = "low"
    chroma_persist_directory: Path = BASE_DIR / "chroma_db"
    chroma_collection_name: str = "static_job_postings"
    retrieval_top_k: int = Field(default=4, ge=1, le=10)
    firebase_project_id: str | None = None

    @field_validator("chroma_persist_directory", mode="before")
    @classmethod
    def resolve_chroma_path(cls, value: object) -> Path:
        path = Path(str(value))
        return path if path.is_absolute() else BASE_DIR / path


@lru_cache
def get_settings() -> Settings:
    return Settings()
