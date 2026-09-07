import argparse
from pathlib import Path

from app.config import BASE_DIR
from app.crawled_jobs import load_crawled_job_documents
from scripts.index_jobs import index_documents, split_job_documents


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Normalize a Saramin crawl JSONL and index IT postings into the configured vector store"
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=BASE_DIR / "local_data" / "saramin_detail.jsonl",
    )
    parser.add_argument("--max-jobs", type=int, default=None)
    parser.add_argument("--all-categories", action="store_true")
    parser.add_argument("--detailed-only", action="store_true")
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Normalize and chunk without calling the embedding API or writing the vector store",
    )
    args = parser.parse_args()

    documents, stats = load_crawled_job_documents(
        args.input,
        it_only=not args.all_categories,
        include_limited=not args.detailed_only,
        max_jobs=args.max_jobs,
    )
    print(stats)

    if args.validate_only:
        chunks = split_job_documents(documents)
        print(f"validated jobs={len(documents)} chunks={len(chunks)}")
        return

    chunk_count = index_documents(documents)
    print(f"indexed jobs={len(documents)} chunks={chunk_count}")


if __name__ == "__main__":
    main()
