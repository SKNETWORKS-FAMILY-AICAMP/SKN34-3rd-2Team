import argparse
import json
import statistics
from collections import Counter
from pathlib import Path
from typing import Any


def inspect_jsonl(path: Path) -> dict[str, Any]:
    record_count = 0
    parse_errors = 0
    blank_ids = 0
    ids: Counter[str] = Counter()
    latest_by_id: dict[str, dict[str, Any]] = {}
    fields: Counter[str] = Counter()
    condition_fields: Counter[str] = Counter()
    sources: Counter[str] = Counter()
    parser_versions: Counter[str] = Counter()
    fetched_at_values: list[str] = []
    description_lengths: list[int] = []
    tags_present = 0
    conditions_present = 0
    images_present = 0
    needs_human_review = 0
    records_with_replacement_char = 0
    replacement_char_count = 0
    sample: dict[str, Any] | None = None

    with path.open(encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, start=1):
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                parse_errors += 1
                continue

            record_count += 1
            fields.update(record.keys())
            listing = record.get("list_item") or {}
            conditions = record.get("conditions") or {}
            source_job_id = str(
                record.get("source_job_id") or listing.get("source_job_id") or ""
            ).strip()
            if source_job_id:
                ids[source_job_id] += 1
                latest_by_id[source_job_id] = record
            else:
                blank_ids += 1

            description = str(record.get("description") or "").strip()
            description_lengths.append(len(description))
            tags = record.get("tags") or []
            images = record.get("description_images") or []
            tags_present += bool(tags)
            conditions_present += bool(conditions)
            images_present += bool(images)
            needs_human_review += bool(record.get("needs_human_review"))
            condition_fields.update(conditions.keys())
            sources[str(record.get("source") or "UNKNOWN")] += 1
            parser_versions[str(record.get("parser_version") or "UNKNOWN")] += 1
            if record.get("fetched_at"):
                fetched_at_values.append(str(record["fetched_at"]))
            serialized = json.dumps(record, ensure_ascii=False)
            current_replacement_count = serialized.count("\ufffd")
            records_with_replacement_char += current_replacement_count > 0
            replacement_char_count += current_replacement_count

            if sample is None:
                title = str(listing.get("title") or "")
                company = str(listing.get("company") or "")
                sample = {
                    "line_number": line_number,
                    "source_job_id": source_job_id,
                    "source_url": record.get("source_url"),
                    "company": company,
                    "title": title,
                    "company_unicode_escape": company.encode("unicode_escape").decode("ascii"),
                    "title_unicode_escape": title.encode("unicode_escape").decode("ascii"),
                    "condition_keys_unicode_escape": [
                        str(key).encode("unicode_escape").decode("ascii")
                        for key in conditions
                    ],
                    "conditions": conditions,
                    "tags": tags[:20],
                    "description_length": len(description),
                    "description_image_count": len(images),
                    "needs_human_review": bool(record.get("needs_human_review")),
                }

    duplicate_ids = {job_id: count for job_id, count in ids.items() if count > 1}
    description_present = sum(length > 0 for length in description_lengths)
    unique_records = list(latest_by_id.values())
    unique_description_lengths = [
        len(str(record.get("description") or "").strip())
        for record in unique_records
    ]
    unique_coverage = {
        "description": sum(length > 0 for length in unique_description_lengths),
        "description_at_least_800_chars": sum(
            length >= 800 for length in unique_description_lengths
        ),
        "tags": sum(bool(record.get("tags")) for record in unique_records),
        "conditions": sum(bool(record.get("conditions")) for record in unique_records),
        "description_images": sum(
            bool(record.get("description_images")) for record in unique_records
        ),
        "needs_human_review": sum(
            bool(record.get("needs_human_review")) for record in unique_records
        ),
        "job_sectors": sum(
            bool((record.get("list_item") or {}).get("job_sectors"))
            for record in unique_records
        ),
    }
    return {
        "path": str(path.resolve()),
        "size_bytes": path.stat().st_size,
        "records": record_count,
        "parse_errors": parse_errors,
        "unique_job_ids": len(ids),
        "blank_job_ids": blank_ids,
        "duplicate_id_count": len(duplicate_ids),
        "duplicate_row_excess": sum(count - 1 for count in duplicate_ids.values()),
        "duplicate_multiplicity": dict(Counter(ids.values())),
        "encoding_health": {
            "records_with_replacement_char": records_with_replacement_char,
            "replacement_char_count": replacement_char_count,
        },
        "coverage": {
            "description": description_present,
            "tags": tags_present,
            "conditions": conditions_present,
            "description_images": images_present,
            "needs_human_review": needs_human_review,
        },
        "latest_unique_coverage": unique_coverage,
        "latest_unique_description_length": {
            "min": min(unique_description_lengths, default=0),
            "median": int(statistics.median(unique_description_lengths))
            if unique_description_lengths
            else 0,
            "max": max(unique_description_lengths, default=0),
        },
        "description_length": {
            "min": min(description_lengths, default=0),
            "median": int(statistics.median(description_lengths))
            if description_lengths
            else 0,
            "max": max(description_lengths, default=0),
        },
        "top_level_fields": dict(fields),
        "condition_fields": dict(condition_fields),
        "sources": dict(sources),
        "parser_versions": dict(parser_versions),
        "fetched_at": {
            "present": len(fetched_at_values),
            "min": min(fetched_at_values, default=None),
            "max": max(fetched_at_values, default=None),
        },
        "sample": sample,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Inspect a Saramin detail JSONL file")
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect_jsonl(args.path), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
