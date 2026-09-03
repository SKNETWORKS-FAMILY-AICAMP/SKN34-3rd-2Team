"""수집 결과를 다른 런타임이 읽을 수 있는 형태로 내보내는 레이어."""

from job_matching_bot.exporters.typescript import build_typescript_module

__all__ = ["build_typescript_module"]
