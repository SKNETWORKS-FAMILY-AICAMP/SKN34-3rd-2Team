"""수집한 IT 공고를 Firebase Functions가 쓰는 TypeScript 모듈로 내보낸다.

Functions에 공고를 다시 하드코딩하면 Python 파이프라인과 값이 갈라진다.
그래서 공고 데이터의 단일 출처는 이 파이프라인이고, Functions는 여기서
생성한 파일을 읽기만 한다.

JSON 파일 대신 `.ts`를 만드는 이유는 배포 때문이다. `tsc`는 `src`의 JSON을
`lib`으로 복사하지 않아서, JSON을 import하면 배포본에서 파일을 찾지 못한다.
"""

from __future__ import annotations

import json
from typing import Any

GENERATED_HEADER = """// 이 파일은 자동 생성됩니다. 직접 수정하지 마세요.
// 다시 만들려면 레포 루트에서 실행하세요:
//   python -m job_matching_bot
//
// 원본: job_matching_bot/artifacts/collected_it_jobs.json
"""

# 수집 레코드(snake_case) → Functions가 쓰는 필드명(camelCase)
FIELD_NAMES = {
    "id": "jobId",
    "company": "company",
    "position": "title",
    "description": "description",
    "required_skills": "requiredSkills",
    "preferred_skills": "preferredSkills",
    "tech_stack": "techStack",
    "body_is_image": "bodyIsImage",
    "required_majors": "requiredMajors",
    "required_major_terms": "requiredMajorTerms",
    "required_certifications": "requiredCertifications",
    "military_required": "militaryRequired",
    "career_type": "careerType",
    "min_career_years": "minCareerYears",
    "education": "education",
    "location": "region",
    "employment_type": "employmentType",
    "status": "status",
    "source": "source",
    "source_url": "sourceUrl",
    "deadline": "deadline",
}

# Functions의 Hard Filter는 "미기재"를 값이 아니라 "확인 필요"로 다뤄야 해서 null로 바꾼다.
UNKNOWN_MARKER = "미기재"
NULLABLE_ON_UNKNOWN = ("employment_type",)


def _to_camel_record(record: dict[str, Any]) -> dict[str, Any]:
    converted: dict[str, Any] = {}
    for source_key, target_key in FIELD_NAMES.items():
        value = record.get(source_key)
        if source_key in NULLABLE_ON_UNKNOWN and value == UNKNOWN_MARKER:
            value = None
        converted[target_key] = value
    return converted


def build_typescript_module(collected_jobs: list[dict[str, Any]]) -> str:
    """수집 레코드 목록을 `collectedJobs.ts` 내용 문자열로 만든다."""
    payload = [_to_camel_record(record) for record in collected_jobs]
    body = json.dumps(payload, ensure_ascii=False, indent=2)
    return (
        f"{GENERATED_HEADER}\n"
        "import {CollectedJob} from \"../jobCoachTypes\";\n\n"
        f"export const COLLECTED_JOBS: CollectedJob[] = {body};\n"
    )
