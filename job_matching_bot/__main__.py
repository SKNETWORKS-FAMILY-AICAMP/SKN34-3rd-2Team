"""CLI 진입점.

    python -m job_matching_bot
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from job_matching_bot.config import (
    DEFAULT_COLLECTION_OUTPUT,
    DEFAULT_DART_OUTPUT,
    DEFAULT_INPUT,
    DEFAULT_JSON_OUTPUT,
    DEFAULT_REPORT_OUTPUT,
    DEFAULT_RESUME_MOCKS_DART_OUTPUT,
    DEFAULT_TYPESCRIPT_OUTPUT,
)
from job_matching_bot.ingest import DEFAULT_STORE
from job_matching_bot.pipeline import run_pipeline


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="AI 취업 코치 Vertical Slice POC")
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--json-output", type=Path, default=DEFAULT_JSON_OUTPUT)
    parser.add_argument("--report-output", type=Path, default=DEFAULT_REPORT_OUTPUT)
    parser.add_argument("--collection-output", type=Path, default=DEFAULT_COLLECTION_OUTPUT)
    parser.add_argument(
        "--typescript-output",
        type=Path,
        default=DEFAULT_TYPESCRIPT_OUTPUT,
        help="Functions가 import하는 공고 데이터 모듈 경로",
    )
    parser.add_argument(
        "--dart-output",
        type=Path,
        default=DEFAULT_DART_OUTPUT,
        help="Flutter 채용공고 검색이 읽는 공고 데이터 모듈 경로",
    )
    parser.add_argument(
        "--resume-mocks-output",
        type=Path,
        default=DEFAULT_RESUME_MOCKS_DART_OUTPUT,
        help="Flutter '목업 이력서 채우기' 메뉴가 읽는 생성 파일 경로",
    )
    parser.add_argument(
        "--store",
        type=Path,
        default=DEFAULT_STORE,
        help="수집 저장소(job_store.json). 있으면 진행 중 공고를 함께 내보낸다",
    )
    parser.add_argument(
        "--no-store", action="store_true", help="저장소를 읽지 않고 fixture만 쓴다"
    )
    args = parser.parse_args()

    result = run_pipeline(
        args.input,
        args.json_output,
        args.report_output,
        collection_output=args.collection_output,
        typescript_output=args.typescript_output,
        dart_output=args.dart_output,
        resume_mocks_output=args.resume_mocks_output,
        store_path=None if args.no_store else args.store,
    )
    print(f"AI Job Coach Pipeline: {result['test_status']}")
    print(
        f"jobs={result['input_summary']['deduplicated']} "
        f"(store={result['input_summary']['store']}) "
        f"it_jobs={result['input_summary']['it_jobs']} "
        f"recommendations={len(result['recommendations'])} "
        f"selected={result['selected_job']['job_id']}"
    )
    for check in result["checks"]:
        print(f"[{'PASS' if check['passed'] else 'FAIL'}] {check['name']}")
    print(f"JSON: {args.json_output.resolve()}")
    print(f"REPORT: {args.report_output.resolve()}")
    print(f"COLLECTED JOBS: {args.collection_output.resolve()}")
    print(f"FUNCTIONS DATA: {args.typescript_output.resolve()}")
    print(f"FLUTTER DATA:  {args.dart_output.resolve()}")
    print(f"RESUME MOCKS:  {args.resume_mocks_output.resolve()}")
    return 0 if result["test_status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
