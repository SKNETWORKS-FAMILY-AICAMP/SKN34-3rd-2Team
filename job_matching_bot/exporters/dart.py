"""수집한 IT 공고를 Flutter가 쓰는 Dart 모듈로 내보낸다.

채용공고 찾기(챗봇 검색)는 로그인·분석 없이도 동작해야 해서 클라이언트에서
바로 검색한다. 그 데이터를 Dart에 다시 손으로 적으면 Python·Functions와
값이 갈라지므로, TypeScript 모듈과 같은 수집 결과에서 함께 생성한다.
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

UNKNOWN_MARKER = "미기재"


def _dart_string(value: str) -> str:
    """Dart 문자열 리터럴로 만든다. 줄바꿈은 검색 표시에 불필요해 공백으로 바꾼다.

    JSON과 달리 Dart는 `$`가 문자열 보간이라 그대로 두면 "$10M USD" 같은 본문이
    컴파일 오류를 낸다(`missing_identifier`). JSON 이스케이프 뒤에 `$`를 따로 막는다.
    """
    normalized = " ".join(value.split())
    return json.dumps(normalized, ensure_ascii=False).replace("$", r"\$")


def _dart_string_list(values: list[str]) -> str:
    return "[" + ", ".join(_dart_string(value) for value in values) + "]"


def _dart_nullable_int(value: int | None) -> str:
    return "null" if value is None else str(int(value))


def _dart_nullable_string(value: str | None) -> str:
    if value is None or value == UNKNOWN_MARKER:
        return "null"
    return _dart_string(value)


def build_dart_module(collected_jobs: list[dict[str, Any]]) -> str:
    """수집 레코드 목록을 `collected_jobs.g.dart` 내용 문자열로 만든다."""
    entries = []
    for record in collected_jobs:
        entries.append(
            "  CollectedJob(\n"
            f"    jobId: {_dart_string(record['id'])},\n"
            f"    company: {_dart_string(record['company'])},\n"
            f"    title: {_dart_string(record['position'])},\n"
            f"    description: {_dart_string(record['description'])},\n"
            f"    requiredSkills: {_dart_string_list(record['required_skills'])},\n"
            f"    preferredSkills: {_dart_string_list(record['preferred_skills'])},\n"
            f"    techStack: {_dart_string_list(record.get('tech_stack', []))},\n"
            f"    bodyIsImage: {'true' if record.get('body_is_image') else 'false'},\n"
            f"    requiredMajors: {_dart_string_list(record.get('required_majors') or [])},\n"
            f"    requiredMajorTerms: {_dart_string_list(record.get('required_major_terms') or [])},\n"
            f"    requiredCertifications: {_dart_string_list(record.get('required_certifications') or [])},\n"
            f"    militaryRequired: {'true' if record.get('military_required') else 'false'},\n"
            f"    careerType: {_dart_string(record['career_type'])},\n"
            f"    minCareerYears: {_dart_nullable_int(record.get('min_career_years'))},\n"
            f"    education: {_dart_string(record['education'])},\n"
            f"    region: {_dart_string(record['location'])},\n"
            f"    employmentType: {_dart_nullable_string(record['employment_type'])},\n"
            f"    deadline: {_dart_nullable_string(record['deadline'])},\n"
            f"    source: {_dart_string(record['source'])},\n"
            f"    sourceUrl: {_dart_string(record['source_url'])},\n"
            f"    status: {_dart_string(record.get('status') or 'OPEN')},\n"
            "  ),"
        )
    body = "\n".join(entries)
    return (
        f"{GENERATED_HEADER}\n"
        "import '../../models/collected_job.dart';\n\n"
        "const collectedJobs = <CollectedJob>[\n"
        f"{body}\n"
        "];\n"
    )
