"""저장된 기대 결과와 Luna 실험 supervisor를 비교한다.

실제 OpenAI 호출 비용이 발생하므로 사용자가 명시적으로 실행할 때만 동작한다.
이 도구는 운영 Sol 모델을 생성하거나 호출하지 않는다.
"""

from __future__ import annotations

import argparse
import json
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

from langchain_core.messages import HumanMessage

from chatbot_lab.bot import create_supervisor_harness

DEFAULT_CASES = Path(__file__).with_name("eval_cases.json")


def _decision(bot: Any, question: str) -> tuple[dict[str, Any], int]:
    started = time.perf_counter()
    result = bot.supervisor_middleware.invoke(
        {"messages": [HumanMessage(content=question)]},
        bot.supervisor_chain,
    )
    elapsed_ms = round((time.perf_counter() - started) * 1000)
    return result.model_dump(), elapsed_ms


def _matches(actual: dict[str, Any], expected: dict[str, Any]) -> bool:
    return (
        actual.get("route") == expected["route"]
        and set(actual.get("namespaces", [])) == set(expected["namespaces"])
        and set(actual.get("student_scopes", [])) == set(expected["student_scopes"])
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Luna 학생 챗봇 라우팅 평가")
    parser.add_argument("--cases", type=Path, default=DEFAULT_CASES)
    parser.add_argument("--output", type=Path, default=Path("chatbot_lab/eval_result.json"))
    args = parser.parse_args()

    cases = json.loads(args.cases.read_text(encoding="utf-8"))
    baseline = create_supervisor_harness(improved=False)
    candidate = create_supervisor_harness(improved=True)

    # API 호출은 서로 독립적이다. 소수만 병렬 실행해 평가 대기 시간을 줄인다.
    with ThreadPoolExecutor(max_workers=4) as executor:
        pending = [
            (
                case,
                executor.submit(_decision, baseline, case["question"]),
                executor.submit(_decision, candidate, case["question"]),
            )
            for case in cases
        ]

    rows = []
    for case, original_future, candidate_future in pending:
        original, original_ms = original_future.result()
        luna, luna_ms = candidate_future.result()
        rows.append(
            {
                "id": case["id"],
                "question": case["question"],
                "expected": {
                    key: case[key]
                    for key in ("route", "namespaces", "student_scopes")
                },
                "original_luna": {
                    "decision": original,
                    "elapsed_ms": original_ms,
                    "passed": _matches(original, case),
                },
                "luna_lab": {
                    "decision": luna,
                    "elapsed_ms": luna_ms,
                    "passed": _matches(luna, case),
                },
            }
        )

    summary = {
        "case_count": len(rows),
        "original_luna_passed": sum(row["original_luna"]["passed"] for row in rows),
        "luna_lab_passed": sum(row["luna_lab"]["passed"] for row in rows),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps({"summary": summary, "cases": rows}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(json.dumps(summary, ensure_ascii=False))
    print(f"상세 결과: {args.output}")


if __name__ == "__main__":
    main()
