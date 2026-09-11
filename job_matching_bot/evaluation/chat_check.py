"""챗봇이 말을 제대로 가르는지, 답이 규율을 지키는지 잰다. 사람 정답이 필요 없다.

    python -m job_matching_bot.evaluation.chat_check             # 전부
    python -m job_matching_bot.evaluation.chat_check --routing   # 가르기만 (서버 없이)
    python -m job_matching_bot.evaluation.chat_check --answers   # 답 규율만 (서버 필요)

## 왜 필요한가

프롬프트를 고칠 때마다 몇 마디 넣어 보고 "되네" 하고 넘어갔다. 2026-09-11 하루에만
여섯 번 고쳤다. 무엇이 좋아졌는지, 대신 무엇이 나빠졌는지 잰 것이 없다.

단위 테스트는 가짜 모델로 돈다. 갈래를 가르는 일은 **모델이 하는 판단**이라 거기서는
한 줄도 안 잡힌다. 그래서 실제로 불러 봐야 한다.

## 두 갈래로 잰다

**가르기**는 모델만 부른다. 저장소도 인덱스도 안 쓴다. 말 하나에 한 번, 1.7초쯤.
기대값이 분명해서 맞고 틀림을 그냥 셀 수 있다. 프롬프트를 고쳤으면 이것부터 돌린다.

**답 규율**은 서버를 띄우고 전체를 돌린다. 느리고 값이 든다. 대신 **사람 없이도
확실히 틀렸다고 말할 수 있는 것**만 본다. 답이 좋은지는 여기서 판단하지 않는다 —
그건 취향이 섞이고, 취향을 결함으로 세면 숫자가 의미를 잃는다.

## 쓰는 법

고치기 전에 한 번, 고친 뒤에 한 번 돌려 비교한다. 틀린 것이 있으면 종료 코드가 1이다.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

KST = timezone(timedelta(hours=9))
DEFAULT_BASE_URL = "http://127.0.0.1:8000"


# ── 가르기 ────────────────────────────────────────────────────
#
# 기대값은 `ChatTurnOut`의 필드 이름 그대로다. 적은 필드만 본다 — 한 말에서 확실한
# 것만 적고 나머지는 비워 둔다. 애매한 것을 적으면 고칠 때마다 여기부터 흔들린다.


@dataclass
class RoutingCase:
    message: str
    expect: dict
    why: str
    last_job_ids: list[str] = field(default_factory=list)
    last_answer_job_ids: list[str] = field(default_factory=list)


ROUTING_CASES: list[RoutingCase] = [
    # 갈래 넷
    RoutingCase("서울 백엔드 신입 찾아줘", {"topic": "채용", "intent": "검색"},
                "가장 흔한 말. 이게 틀리면 아무것도 안 된다"),
    RoutingCase("마감 임박한 것만", {"topic": "채용", "intent": "검색"},
                "앞 조건에 얹는 말도 검색이다"),
    RoutingCase("백엔드 신입은 뭘 준비해야 해?", {"intent": "질문", "counts_jobs": True},
                "세면 답이 되는 물음. 표를 만들어 넘겨야 한다"),
    RoutingCase("자소서 어떻게 써?", {"intent": "질문", "counts_jobs": False},
                "세어도 답이 안 나오는 물음. 상관없는 숫자로 답을 시작하면 안 된다"),
    RoutingCase("내 이력서 보고 맞는 공고 찾아줘", {"topic": "채용", "intent": "추천"},
                "챗봇이 목록을 내면 안 된다. 추천으로 넘겨야 한다"),
    RoutingCase("안녕", {"topic": "인사"},
                "인사에 사용법 안내가 나가면 대화가 아니라 자판기다"),
    # 범위
    RoutingCase("호구", {"topic": "그 밖"},
                "뜻풀이와 '부드럽게 바꿔 말해줘' 제안까지 붙어 나간 적이 있다"),
    RoutingCase("파이썬으로 퀵소트 코드 짜줘", {"topic": "그 밖"},
                "채용 밖의 일"),
    RoutingCase("면접 준비하게 파이썬 코드 짜줘", {"topic": "그 밖"},
                "채용을 빌미로 삼았을 뿐 우리가 할 일이 아니다"),
    RoutingCase("친구 생일선물 뭐 사지", {"topic": "그 밖"},
                "목록으로는 못 막는 말. 여기서 걸러야 한다"),
    RoutingCase("취업 너무 막막해", {"topic": "채용", "intent": "질문"},
                "취업을 두고 하는 토로는 채용이다. 잡담으로 떨어지면 아무도 답하지 않는다"),
    RoutingCase("면접에서 뭘 물어봐?", {"topic": "채용", "intent": "질문"},
                "면접은 취업 준비의 하나다"),
    # 가리키기
    RoutingCase("2번 자세히 봐줘", {"job_refs": [2]},
                "번호를 가리킨 말", last_job_ids=["J1", "J2", "J3"]),
    RoutingCase("1번하고 3번 비교해줘", {"job_refs": [1, 3]},
                "둘을 가리키면 비교다", last_job_ids=["J1", "J2", "J3"]),
    RoutingCase("3년차인데 갈 만한 데 있어?", {"job_refs": []},
                "숫자지만 자리가 아니다. 경력이다"),
    RoutingCase("두 공고의 자격요건만 간단히 비교해줘",
                {"refers_to_last_answer": True, "job_refs": []},
                "번호 없이 방금 그거를 가리킨 말. 챗봇이 직접 내놓는 제안 문구다",
                last_job_ids=["J1", "J2", "J3"], last_answer_job_ids=["J1", "J3"]),
    RoutingCase("다른 공고도 보여줘", {"refers_to_last_answer": False},
                "새로 찾아 달라는 말이지 방금 그것을 가리킨 것이 아니다",
                last_job_ids=["J1", "J2"], last_answer_job_ids=["J1", "J2"]),
    # 못 하는 것
    RoutingCase("급여 높은 순으로 보여줘", {"unavailable": "급여"},
                "공고 10건 중 9건이 '면접 후 결정'이라 줄을 세울 수 없다"),
    RoutingCase("나 붙을 만한 데 있어?", {"unavailable": "합격 가능성"},
                "알 수 없는 것을 조건으로 넣으면 0건이 나오고 엉뚱한 안내가 나간다"),
    # 뜻으로 찾기
    RoutingCase("돈 다루는 일 찾아줘", {"topic": "채용", "intent": "검색"},
                "글자로는 0건이다. requirement_query가 있어야 뜻으로 찾는다"),
]


def run_routing(report: Report) -> None:
    from job_matching_bot.api import prompts, schemas
    from job_matching_bot.api.service import CHAT_EFFORT, _build_generator

    generate = _build_generator(
        prompts.CHAT_PROMPT, schemas.ChatTurnOut, effort=CHAT_EFFORT
    )
    empty = schemas.ChatFilters().model_dump_json()
    for case in ROUTING_CASES:
        report.checked += 1
        try:
            turn = generate({"previous": empty, "message": case.message})
        except Exception as error:  # noqa: BLE001 — 실패도 결과다
            report.add("가르기", case.message, f"모델 호출 실패: {type(error).__name__}", case.why)
            continue
        for field_name, wanted in case.expect.items():
            got = getattr(turn, field_name)
            if got != wanted:
                report.add(
                    "가르기", case.message, f"{field_name}: {got!r} (기대 {wanted!r})", case.why
                )
        # "돈 다루는 일"은 조건으로 옮길 말이 없다. 뜻으로 찾을 문장이 있어야 한다.
        if case.message.startswith("돈 다루는 일") and not turn.requirement_query:
            report.add("가르기", case.message, "requirement_query가 비었다", case.why)


# ── 답 규율 ───────────────────────────────────────────────────
#
# 각 검사는 **왜 결함인지**가 분명해야 한다. "답이 좋은가"는 여기서 묻지 않는다.

OFF_TOPIC_MARK = "채용과 취업 준비에 대해서만"
GUIDE_MARK = "공고를 찾으시려면"
# 존댓말 종결. 하나도 없으면 반말로 답한 것으로 본다. 낱말 하나로 가르면 오판이 많다.
_POLITE = re.compile(r"(요|다|까|죠)[.!?]|(요|다|까|죠)$", re.MULTILINE)
_AB_LABEL = re.compile(r"(?<![A-Za-z])[AB](?=[는은이가의와과])")
_MD_TABLE = re.compile(r"\|\s*-{2,}")
_COUNT = re.compile(r"([\d,]+)\s*건")


@dataclass
class AnswerCase:
    message: str
    checks: list[str]
    why: str
    last_job_ids: list[str] = field(default_factory=list)
    last_answer_job_ids: list[str] = field(default_factory=list)


ANSWER_CASES: list[AnswerCase] = [
    AnswerCase("서울 백엔드 신입 찾아줘", ["말투", "건수", "표라는말", "마크다운표"],
               "가장 흔한 답. 숫자가 결과와 어긋나면 없는 공고를 있다고 말하는 셈이다"),
    AnswerCase("백엔드 신입은 뭘 준비해야 해?", ["말투", "건수", "표라는말", "마크다운표"],
               "센 결과를 근거로 쓰되 사용자는 표를 본 적이 없다"),
    AnswerCase("안녕", ["말투", "인사에안내금지"],
               "인사에 사용법 안내가 돌아오면 사람과 말하는 것 같지 않다"),
    AnswerCase("호구", ["범위밖고정문구"],
               "정해진 말이 그대로 나가야 한다. 모델이 쓴 문장이 새면 안 된다"),
    AnswerCase("친구 생일선물 뭐 사지", ["범위밖고정문구"], "위와 같다"),
    AnswerCase("바보", ["범위밖고정문구"], "목록에 걸려 모델을 부르지 않고 막혀야 한다"),
    AnswerCase("취업 너무 막막해", ["말투", "표라는말"],
               "반말로 물어도 존댓말로 답해야 한다"),
    AnswerCase("급여 제일 높은 공고", ["말투", "면접후결정"],
               "왜 못 하는지 밝혀야 한다. 조건을 빼 보라고 하면 안 된다"),
]


def check_말투(answer: dict) -> str | None:
    """존댓말 종결이 하나도 없으면 반말로 답한 것이다.

    사용자가 반말로 물으면 모델이 따라갔다. "알아. ... 줄여봐."로 답한 적이 있다.
    처음 쓰는 도구가 먼저 말을 놓으면 친근한 게 아니라 무례하게 읽힌다.
    """
    reply = answer["reply"].strip()
    if len(reply) < 10 or _POLITE.search(reply):
        return None
    return f"존댓말 종결이 없다: {reply[:60]}"


def check_건수(answer: dict) -> str | None:
    """답에 적은 건수가 실제 결과와 다르면 안 된다.

    답 문장을 모델이 통째로 쓰면 없는 공고를 있다고 말한다. 그래서 검색 답은 결과로
    조립하는데, 질문 답은 모델이 쓰므로 표에 없는 숫자가 섞일 수 있다.
    """
    total = answer.get("total", 0)
    if not total:
        return None
    numbers = {int(n.replace(",", "")) for n in _COUNT.findall(answer["reply"])}
    if numbers and total not in numbers:
        return f"답의 건수 {sorted(numbers)}에 실제 {total}건이 없다"
    return None


def check_표라는말(answer: dict) -> str | None:
    """사용자는 표를 본 적이 없다. "표에 없다"는 말은 무슨 표인지 모를 소리다."""
    if "표에" in answer["reply"] or "표를 보면" in answer["reply"]:
        return "답에 '표' 이야기가 나온다"
    return None


def check_마크다운표(answer: dict) -> str | None:
    """대화창은 표를 그리지 않는다. 막대 기호만 줄줄이 나온다."""
    return "마크다운 표를 그렸다" if _MD_TABLE.search(answer["reply"]) else None


def check_인사에안내금지(answer: dict) -> str | None:
    return "인사에 사용법 안내가 나갔다" if GUIDE_MARK in answer["reply"] else None


def check_범위밖고정문구(answer: dict) -> str | None:
    if OFF_TOPIC_MARK not in answer["reply"]:
        return f"정해진 거절 문구가 아니다: {answer['reply'][:60]}"
    if answer.get("jobs"):
        return "범위 밖인데 공고가 붙어 나갔다"
    return None


def check_면접후결정(answer: dict) -> str | None:
    """왜 못 하는지 밝혀야 한다. 그냥 0건이라고 하면 조건을 빼 보라는 말이 나간다."""
    if "면접 후 결정" not in answer["reply"]:
        return "급여로 줄 세울 수 없는 이유를 밝히지 않았다"
    return None


def check_ab라벨(answer: dict) -> str | None:
    """"A"와 "B"는 프롬프트 안에서 붙인 이름이다. 사용자는 본 적이 없다."""
    return "공고를 A/B로 불렀다" if _AB_LABEL.search(answer["reply"]) else None


CHECKS = {
    "말투": check_말투,
    "건수": check_건수,
    "표라는말": check_표라는말,
    "마크다운표": check_마크다운표,
    "인사에안내금지": check_인사에안내금지,
    "범위밖고정문구": check_범위밖고정문구,
    "면접후결정": check_면접후결정,
    "ab라벨": check_ab라벨,
}


def run_answers(report: Report, base_url: str) -> None:
    import requests

    for case in ANSWER_CASES:
        report.checked += 1
        body = {
            "message": case.message,
            "last_job_ids": case.last_job_ids,
            "last_answer_job_ids": case.last_answer_job_ids,
        }
        try:
            response = requests.post(
                f"{base_url}/api/v1/jobs/chat", json=body, timeout=120
            )
            response.raise_for_status()
            answer = response.json()
        except Exception as error:  # noqa: BLE001
            report.add("답", case.message, f"요청 실패: {type(error).__name__}", case.why)
            continue
        for name in case.checks:
            detail = CHECKS[name](answer)
            if detail:
                report.add(f"답·{name}", case.message, detail, case.why)


# ── 결과 ──────────────────────────────────────────────────────


@dataclass
class Defect:
    check: str
    message: str
    detail: str
    why: str


@dataclass
class Report:
    defects: list[Defect] = field(default_factory=list)
    checked: int = 0
    elapsed: float = 0.0

    def add(self, check: str, message: str, detail: str, why: str) -> None:
        self.defects.append(Defect(check, message, detail, why))

    def show(self) -> None:
        print(f"\n잰 것 {self.checked}가지 · 틀린 것 {len(self.defects)}개 · {self.elapsed:.0f}초")
        for defect in self.defects:
            print(f"\n  [{defect.check}] {defect.message}")
            print(f"    {defect.detail}")
            print(f"    왜 보나: {defect.why}")
        if not self.defects:
            print("  전부 통과")

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(
                {
                    "when": datetime.now(KST).isoformat(timespec="seconds"),
                    "checked": self.checked,
                    "elapsed": round(self.elapsed, 1),
                    "defects": [vars(d) for d in self.defects],
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        print(f"\n기록: {path}")


def main() -> int:
    parser = argparse.ArgumentParser(description="챗봇 가르기·답 규율 검사")
    parser.add_argument("--routing", action="store_true", help="가르기만 (서버 없이)")
    parser.add_argument("--answers", action="store_true", help="답 규율만 (서버 필요)")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--save", action="store_true", help="결과를 파일로 남긴다")
    args = parser.parse_args()

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    both = not (args.routing or args.answers)
    from job_matching_bot.env import ensure_loaded

    ensure_loaded()

    report = Report()
    started = time.perf_counter()
    if both or args.routing:
        print(f"가르기 {len(ROUTING_CASES)}가지…")
        run_routing(report)
    if both or args.answers:
        print(f"답 규율 {len(ANSWER_CASES)}가지… ({args.base_url})")
        run_answers(report, args.base_url.rstrip("/"))
    report.elapsed = time.perf_counter() - started
    report.show()

    if args.save:
        from job_matching_bot.config import ARTIFACTS_DIR

        stamp = datetime.now(KST).strftime("%Y%m%d-%H%M%S")
        report.save(ARTIFACTS_DIR / "eval_runs" / f"{stamp}-chat.json")
    return 1 if report.defects else 0


if __name__ == "__main__":
    sys.exit(main())
