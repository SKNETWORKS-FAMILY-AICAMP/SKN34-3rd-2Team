"""POC 전역 설정: 기준 시각과 기본 입출력 경로.

경로는 패키지 위치를 기준으로 계산하므로 어느 디렉터리에서 실행해도 동작한다.
"""

from datetime import datetime
from pathlib import Path

# 재현 가능한 결과를 위해 고정한 기준 시각. 공고 마감 판정과 수집일에 사용한다.
AS_OF = datetime.fromisoformat("2026-09-02T12:00:00+09:00")

PACKAGE_ROOT = Path(__file__).resolve().parent
REPO_ROOT = PACKAGE_ROOT.parent

FIXTURES_DIR = PACKAGE_ROOT / "fixtures"
ARTIFACTS_DIR = PACKAGE_ROOT / "artifacts"

DEFAULT_INPUT = FIXTURES_DIR / "jobkorea_detail_first_page.json"
# 크롤러 출력. 상세는 한 건씩 이어 쓰는 JSON Lines, 목록은 JSON 배열.
RAW_DIR = ARTIFACTS_DIR / "raw"
DEFAULT_SARAMIN_INPUT = RAW_DIR / "saramin_detail.jsonl"
DEFAULT_SARAMIN_LIST = RAW_DIR / "saramin_raw.json"
DEFAULT_JSON_OUTPUT = ARTIFACTS_DIR / "job_coach_pipeline_test.json"
DEFAULT_REPORT_OUTPUT = ARTIFACTS_DIR / "job_coach_pipeline_test.md"
DEFAULT_COLLECTION_OUTPUT = ARTIFACTS_DIR / "collected_it_jobs.json"

# Flutter의 채용공고 찾기(챗봇 검색)가 읽는 생성 파일.
DEFAULT_DART_OUTPUT = (
    REPO_ROOT
    / "lib"
    / "features"
    / "resume"
    / "ai_coach"
    / "data"
    / "generated"
    / "collected_jobs.g.dart"
)

# cover_letter_rag 인덱서(`python -m scripts.index_jobs --data-dir ...`)가 읽는
# 정적 공고 JSON 디렉터리. 서버 코드를 건드리지 않고 수집 공고를 임베딩 검색에 올린다.
DEFAULT_RAG_JOBS_OUTPUT = ARTIFACTS_DIR / "cover_letter_rag_jobs"

# 웹용 가상 이력서. 시드 스크립트와 앱의 "목업 채우기" 메뉴가 같은 원본을 쓴다.
DEFAULT_RESUME_MOCKS_INPUT = REPO_ROOT / "scripts" / "resume_mocks.json"
DEFAULT_RESUME_MOCKS_DART_OUTPUT = DEFAULT_DART_OUTPUT.parent / "resume_mocks.g.dart"
