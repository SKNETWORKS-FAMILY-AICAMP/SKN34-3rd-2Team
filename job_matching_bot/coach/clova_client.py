"""네이버 CLOVA Studio 호출 어댑터.

CLOVA Studio는 OpenAI 호환 엔드포인트를 제공하므로 `openai` SDK를 그대로 쓰고
`base_url`만 바꾼다.

    base_url : https://clovastudio.stream.ntruss.com/v1/openai
    api_key  : CLOVA Studio 콘솔에서 발급한 테스트/서비스 API 키
    model    : HCX-005

주의할 점:

- **structured output(JSON 스키마 강제)을 지원하지 않는다.** 지원 필드는
  `messages`, `model`, `temperature`, `top_p`, `max_tokens`, `stream`,
  `tools`, `tool_choice` 정도다. 그래서 JSON을 프롬프트로 요청하고 받은 뒤
  우리가 직접 검증한다. 검증과 재시도는 `requirement_extractor`가 담당한다.
- `frequency_penalty`, `presence_penalty`, `logprobs` 등은 미지원이라 보내지 않는다.
- 임베딩이 필요해지면 같은 엔드포인트에서 `bge-m3`를 쓸 수 있다
  (`encoding_format="float"` 필수).
"""

from __future__ import annotations

import os
from typing import Any

from job_matching_bot.env import ensure_loaded

ensure_loaded()

BASE_URL = "https://clovastudio.stream.ntruss.com/v1/openai"
DEFAULT_MODEL = "HCX-005"

# 추출 작업이라 창의성이 필요 없다. 같은 공고에 같은 결과가 나오는 편이 낫다.
DEFAULT_TEMPERATURE = 0.1
DEFAULT_MAX_TOKENS = 4096


class ClovaChatModel:
    """CLOVA Studio 채팅 모델. `complete(system, user)`만 제공한다.

    이 인터페이스만 맞추면 다른 공급자로 갈아끼울 수 있다.
    """

    provider = "clova"

    def __init__(
        self,
        api_key: str | None = None,
        model: str = DEFAULT_MODEL,
        base_url: str = BASE_URL,
        temperature: float = DEFAULT_TEMPERATURE,
        max_tokens: int = DEFAULT_MAX_TOKENS,
        client: Any = None,
    ):
        self.model = model
        self.temperature = temperature
        self.max_tokens = max_tokens
        self._api_key = api_key or os.environ.get("CLOVA_API_KEY")
        self._base_url = base_url
        self._client = client

    @property
    def client(self) -> Any:
        if self._client is None:
            # 키 확인을 import보다 먼저 한다. SDK가 없을 때도 "키가 없다"는
            # 정확한 이유를 먼저 알려주기 위해서다.
            if not self._api_key:
                raise RuntimeError(
                    "CLOVA_API_KEY가 없습니다. CLOVA Studio 콘솔에서 발급한 키를 "
                    "환경변수 CLOVA_API_KEY에 넣어주세요."
                )
            try:
                # 호출 시점까지 미뤄서 SDK가 없어도 모듈을 읽을 수 있게 한다.
                from openai import OpenAI
            except ImportError as error:
                raise RuntimeError(
                    "openai 패키지가 필요합니다 (CLOVA Studio의 OpenAI 호환 "
                    "엔드포인트를 사용합니다). `pip install openai`로 설치하세요."
                ) from error
            self._client = OpenAI(api_key=self._api_key, base_url=self._base_url)
        return self._client

    def complete(self, system: str, user: str) -> tuple[str, dict[str, int]]:
        """(응답 텍스트, 토큰 사용량)을 돌려준다."""
        response = self.client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            temperature=self.temperature,
            max_tokens=self.max_tokens,
        )
        text = response.choices[0].message.content or ""
        usage = getattr(response, "usage", None)
        return text, {
            "input_tokens": getattr(usage, "prompt_tokens", 0) or 0,
            "output_tokens": getattr(usage, "completion_tokens", 0) or 0,
        }


def is_configured() -> bool:
    ensure_loaded()
    return bool(os.environ.get("CLOVA_API_KEY"))
