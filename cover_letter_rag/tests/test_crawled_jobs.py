import json
from pathlib import Path

from app.crawled_jobs import load_crawled_job_documents


def test_crawled_jsonl_is_deduplicated_normalized_and_it_filtered(tmp_path: Path) -> None:
    path = tmp_path / "jobs.jsonl"
    records = [
        {
            "source_job_id": "101",
            "list_item": {"company": "이전 회사명", "title": "Python 개발자"},
            "description": "짧은 이전 레코드",
        },
        {
            "source_job_id": "101",
            "list_item": {
                "company": "테스트 회사",
                "title": "Python 백엔드 개발자",
                "job_sectors": ["백엔드/서버개발"],
            },
            "conditions": {"경력": "신입", "근무지역": "서울", "근무형태": "정규직"},
            "tags": ["Python", "FastAPI"],
            "description": "Python과 FastAPI 기반 API 개발 " * 50,
            "source_url": "https://example.test/101",
            "needs_human_review": False,
        },
        {
            "source_job_id": "202",
            "list_item": {"company": "비IT 회사", "title": "구매 담당자"},
            "description": "자재 구매와 공급업체 관리",
        },
    ]
    path.write_text("\n".join(json.dumps(record, ensure_ascii=False) for record in records), encoding="utf-8")

    documents, stats = load_crawled_job_documents(path)

    assert stats.valid_records == 3
    assert stats.unique_records == 2
    assert stats.duplicate_records == 1
    assert stats.it_records == 1
    assert len(documents) == 1
    assert documents[0].metadata["company"] == "테스트 회사"
    assert documents[0].metadata["detail_quality"] == "DETAILED"
    assert documents[0].metadata["tech_tags"] == "Python, FastAPI"
