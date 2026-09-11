"""챗봇을 잰다. 정답이 있는 것은 자동으로, 답 문장은 사람이.

## 추천 평가와 다른 점

추천은 "이 공고가 이 사람에게 맞나"라 정답이 없다. 그래서 사람이 43건, 50건을 손으로
매겼다. 챗봇은 다르다. **대부분의 지표에 정답이 있다.**

    "서울 백엔드 신입 찾아줘"  →  intent 검색 · roles 백엔드 · regions 서울 · career 신입
    (목록을 보여 준 뒤) "2번"  →  job_refs [2] · 그 자리의 job_id
    "연봉 높은 순으로"          →  unavailable 급여

이건 사람이 매길 일이 아니라 대조할 일이다. 사람에게 100줄을 매기게 하면 시간만
쓰고, 정작 사람만 판단할 수 있는 것(답이 실제 공고 근거로 쓰였나, 없는 것을
지어냈나)에는 힘이 안 남는다.

그래서 셋으로 나눈다.

1. `--router` 말을 가른 결과를 대조한다. 서버가 필요 없다.
2. `--run`   앱이 보는 응답을 대조한다. 서버를 띄워 놓고 부른다.
3. `--sheet` 답 문장만 사람이 매길 페이지를 만든다.

## 왜 라우터를 따로 재는가

`/api/v1/jobs/chat` 응답에는 `mode`, `filters`, `jobs`, `reply`만 있다. 앱이 쓰는
것만 담기 때문이다. **말을 가른 결과는 밖으로 나오지 않는다** — `intent`,
`counts_jobs`, `job_refs`, `unavailable`이 그렇다.

처음에는 이걸 모르고 케이스에 `intent`, `counts_jobs`를 적어 두었다. `check`가
모르는 칸은 건너뛰므로 **적어 두고도 안 본 채 전부 통과로 셌다.** 재는 줄 알았던
것을 안 재고 있었다.

그래서 라우터(`ChatService.generator`)를 직접 부르는 층을 따로 두었다. 응답에 안
실리는 칸은 여기서 본다. 서버에 재는 용도의 필드를 더하지 않으려는 것이다 — 앱이
안 쓰는 것을 API에 얹으면 그 뒤로 계속 지고 가야 한다.

같은 프롬프트·같은 입력이지만 **서버가 실제로 쓴 그 호출은 아니다.** 모델이 늘 같은
답을 주지 않으므로, 여기서 맞았다고 서버 호출도 맞았다는 보장은 없다. 갈래가 흔들리는
말을 찾는 용도로 본다.

## 여러 턴

서버는 대화를 저장하지 않는다. 앞 턴의 응답에서 `filters`와 `jobs`를 꺼내 다음 턴에
그대로 실어 보낸다. 앱이 하는 것과 같다. 그래야 "서울만", "2번 자세히"가 이어진다.
라우터만 잴 때는 앞 턴이 뽑은 `filters`를 그대로 잇는다.

## 실행

    python -m job_matching_bot.evaluation.chat_eval --router
    python -m job_matching_bot.evaluation.chat_eval --run
    python -m job_matching_bot.evaluation.chat_eval --sheet
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from job_matching_bot.config import ARTIFACTS_DIR, FIXTURES_DIR

CASES = FIXTURES_DIR / "chat_cases.json"
RUNS_DIR = ARTIFACTS_DIR / "chat_eval"
DEFAULT_BASE_URL = "http://127.0.0.1:8000"

# 반말로 끝나는 말. 하나라도 있으면 존댓말 약속을 어긴 것으로 본다.
_CASUAL_ENDINGS = (
    "해봐", "그래", "알아", "해줄게", "있어.", "없어.", "야.", "지.", "거든.",
    "하자", "해라", "인가", "같아.", "볼까", "돼.", "이야.", "이지.",
)


def ask(base_url: str, body: dict, timeout: int = 120) -> tuple[dict, float]:
    """챗봇에 한 번 묻는다. (응답, 걸린 초)."""
    data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        f"{base_url}/api/v1/jobs/chat",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    began = time.time()
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8")), time.time() - began


def _listy(value: Any) -> list[str]:
    return [str(v).strip() for v in (value or []) if str(v).strip()]


def check(expect: dict, sent: dict, got: dict, elapsed: float) -> list[tuple[str, bool, str]]:
    """정답과 대조한다. (항목, 맞았나, 설명)의 목록.

    `expect`에 적지 않은 칸은 보지 않는다. 케이스마다 관심사가 다르고, 모든 칸을
    다 적게 하면 관심 없는 칸이 바뀔 때마다 케이스를 고쳐야 한다.
    """
    out: list[tuple[str, bool, str]] = []
    filters = got.get("filters") or {}

    def add(name: str, ok: bool, detail: str) -> None:
        out.append((name, ok, detail))

    if "mode" in expect:
        add("mode", got.get("mode") == expect["mode"],
            f"{expect['mode']} ↔ {got.get('mode')}")
    if "mode_not" in expect:
        add("mode(아님)", got.get("mode") != expect["mode_not"],
            f"{expect['mode_not']} 이면 안 됨 ↔ {got.get('mode')}")

    for field in ("roles", "skills", "regions", "employment_types", "keywords"):
        want = (expect.get("filters") or {}).get(field)
        if want is None:
            continue
        have = _listy(filters.get(field))
        # 적은 것이 다 들어 있으면 맞은 것으로 본다. 더 뽑는 것은 벌하지 않는다 —
        # "서울 백엔드"에서 keywords 에 무언가 더 담겨도 검색은 여전히 걸린다.
        add(f"조건 {field}", all(w in have for w in want), f"{want} ⊂ {have}")

    want_career = (expect.get("filters") or {}).get("career")
    if want_career is not None:
        add("조건 career", filters.get("career") == want_career,
            f"{want_career} ↔ {filters.get('career')}")

    if expect.get("roles_not"):
        have = _listy(filters.get("roles"))
        add("조건 roles(아님)", not any(r in have for r in expect["roles_not"]),
            f"{expect['roles_not']} 이 빠져야 함 ↔ {have}")

    if expect.get("filters_empty"):
        empty = not any(_listy(filters.get(f)) for f in
                        ("roles", "skills", "regions", "employment_types", "keywords"))
        empty = empty and filters.get("career", "무관") == "무관"
        add("조건 비우기", empty, f"비어야 함 ↔ {filters}")

    if expect.get("deadline_set"):
        add("마감 조건", filters.get("deadline_within_days") is not None,
            f"숫자여야 함 ↔ {filters.get('deadline_within_days')}")

    if expect.get("picked_rank"):
        want_id = (sent.get("last_job_ids") or [None] * 99)[expect["picked_rank"] - 1]
        shown = [j.get("job_id") for j in (got.get("jobs") or [])]
        add("가리킨 공고", bool(want_id) and want_id in shown,
            f"{want_id} ∈ {shown}")

    if "resume_scope" in expect:
        add("이력서 범위", got.get("resume_scope") == expect["resume_scope"],
            f"{expect['resume_scope']} ↔ {got.get('resume_scope')}")

    if "polite" in expect:
        reply = got.get("reply") or ""
        casual = [e for e in _CASUAL_ENDINGS if e in reply]
        add("존댓말", not casual, f"반말 흔적 {casual}" if casual else "없음")

    add("응답 시간", elapsed < 30.0, f"{elapsed:.1f}초")
    return out


# ── 적어 두고 안 보는 칸이 다시 생기지 않게 ────────────────────────

# 응답으로 나오는 것. `check`가 본다.
HTTP_KEYS = frozenset({
    "mode", "mode_not", "filters", "roles_not", "filters_empty",
    "deadline_set", "picked_rank", "resume_scope", "polite",
})
# 응답에 안 나오는 것. `check_router`가 본다.
ROUTER_KEYS = frozenset({
    "intent", "topic_not", "counts_jobs", "job_refs", "unavailable",
    "requirement_query_nonempty",
})


def unknown_keys(cases: list[dict]) -> set[str]:
    """어느 쪽도 안 보는 칸. 케이스에 적어 두고 안 재던 일이 실제로 있었다."""
    known = HTTP_KEYS | ROUTER_KEYS
    return {
        key
        for case in cases
        for turn in case["turns"]
        for key in (turn.get("expect") or {})
        if key not in known
    }


def load_cases() -> list[dict]:
    cases = json.loads(CASES.read_text(encoding="utf-8"))["cases"]
    unknown = unknown_keys(cases)
    if unknown:
        print(f"  경고: 아무도 안 보는 칸이 있습니다 — {sorted(unknown)}")
    return cases


def check_router(expect: dict, turn: Any) -> list[tuple[str, bool, str]]:
    """말을 가른 결과를 대조한다. 응답에 안 실리는 칸만 여기서 본다."""
    out: list[tuple[str, bool, str]] = []

    def add(name: str, ok: bool, detail: str) -> None:
        out.append((name, ok, detail))

    if "intent" in expect:
        add("갈래 intent", turn.intent == expect["intent"],
            f"{expect['intent']} ↔ {turn.intent}")
    if "topic_not" in expect:
        add("갈래 topic(아님)", turn.topic != expect["topic_not"],
            f"{expect['topic_not']} 이면 안 됨 ↔ {turn.topic}")
    if "counts_jobs" in expect:
        add("셀 물음인가", turn.counts_jobs is expect["counts_jobs"],
            f"{expect['counts_jobs']} ↔ {turn.counts_jobs}")
    if "job_refs" in expect:
        add("가리킨 번호", list(turn.job_refs) == list(expect["job_refs"]),
            f"{expect['job_refs']} ↔ {list(turn.job_refs)}")
    if "unavailable" in expect:
        add("없는 정보", turn.unavailable == expect["unavailable"],
            f"{expect['unavailable']} ↔ {turn.unavailable!r}")
    if expect.get("requirement_query_nonempty"):
        add("뜻으로 찾을 문장", bool(turn.requirement_query.strip()),
            f"{turn.requirement_query!r}")
    return out


def run_router() -> Path:
    """서버를 안 거치고 라우터만 부른다. 앞 턴이 뽑은 조건을 그대로 잇는다."""
    from job_matching_bot.api import schemas
    from job_matching_bot.api.service import ChatService
    from job_matching_bot.env import ensure_loaded

    # 서버를 안 거치므로 키를 읽어 주는 것도 없다. API가 뜰 때 하는 일을 여기서 한다.
    ensure_loaded()
    route = ChatService().generator
    cases = load_cases()
    results: list[dict] = []
    started = time.time()

    for case in cases:
        previous = schemas.ChatFilters()
        turns: list[dict] = []
        for step in case["turns"]:
            began = time.time()
            turn = route({
                "previous": previous.model_dump_json(),
                "message": step["message"],
            })
            elapsed = time.time() - began
            checks = check_router(step.get("expect") or {}, turn)
            checks.append(("응답 시간", elapsed < 30.0, f"{elapsed:.1f}초"))
            turns.append({
                "message": step["message"],
                "got": json.loads(turn.model_dump_json()),
                "elapsed": elapsed,
                "checks": checks,
            })
            previous = turn.filters

        passed = all(ok for t in turns for _, ok, _ in t["checks"])
        results.append({"id": case["id"], "note": case.get("note", ""),
                        "turns": turns, "passed": passed})
        print(f"  {case['id']:24} {'통과' if passed else '실패'}"
              f"  {sum(t['elapsed'] for t in turns):5.1f}초")

    RUNS_DIR.mkdir(parents=True, exist_ok=True)
    path = RUNS_DIR / f"{time.strftime('%Y%m%d-%H%M%S')}-router.json"
    path.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    _report(results, time.time() - started)
    print(f"\n결과 원본: {path}")
    return path


def run(base_url: str) -> Path:
    cases = load_cases()
    results: list[dict] = []
    started = time.time()

    for case in cases:
        filters = None
        last_job_ids: list[str] = []
        turns: list[dict] = []
        broke = False
        for turn in case["turns"]:
            body = {
                "message": turn["message"],
                "filters": filters,
                "last_job_ids": last_job_ids,
                "top_k": 5,
            }
            try:
                got, elapsed = ask(base_url, body)
            except urllib.error.URLError as error:
                print(f"  {case['id']}: 서버 호출 실패 — {error}")
                broke = True
                break
            checks = check(turn.get("expect") or {}, body, got, elapsed)
            turns.append({
                "message": turn["message"], "sent": body, "got": got,
                "elapsed": elapsed, "checks": checks,
            })
            # 앱이 하는 것과 같이 앞 턴의 결과를 다음 턴에 실어 보낸다.
            filters = got.get("filters")
            if got.get("jobs"):
                last_job_ids = [j["job_id"] for j in got["jobs"]]
        if broke:
            break
        passed = all(ok for t in turns for _, ok, _ in t["checks"])
        results.append({"id": case["id"], "note": case.get("note", ""),
                        "turns": turns, "passed": passed})
        mark = "통과" if passed else "실패"
        print(f"  {case['id']:24} {mark}  {sum(t['elapsed'] for t in turns):5.1f}초")

    RUNS_DIR.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    path = RUNS_DIR / f"{stamp}.json"
    path.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    _report(results, time.time() - started)
    print(f"\n결과 원본: {path}")
    return path


def _report(results: list[dict], elapsed: float) -> None:
    if not results:
        return
    checks = [(name, ok) for r in results for t in r["turns"] for name, ok, _ in t["checks"]]
    by_kind: dict[str, list[int]] = {}
    for name, ok in checks:
        kind = name.split()[0]
        by_kind.setdefault(kind, [0, 0])
        by_kind[kind][1] += 1
        by_kind[kind][0] += ok

    passed = sum(1 for r in results if r["passed"])
    times = [t["elapsed"] for r in results for t in r["turns"]]
    print(f"\n케이스 {passed}/{len(results)} 통과 · {elapsed:.0f}초")
    print(f"{'항목':16} {'맞음':>8}")
    for kind, (ok, total) in sorted(by_kind.items(), key=lambda x: -x[1][1]):
        print(f"  {kind:14} {ok:>3}/{total:<3} ({ok/total*100:3.0f}%)")
    times.sort()
    print(f"\n응답 시간  중앙값 {times[len(times)//2]:.1f}초 · 최대 {times[-1]:.1f}초")

    failed = [r for r in results if not r["passed"]]
    if failed:
        print("\n어긋난 케이스")
        for r in failed:
            print(f"  {r['id']} — {r['note']}")
            for t in r["turns"]:
                for name, ok, detail in t["checks"]:
                    if not ok:
                        print(f"      “{t['message'][:28]}”  {name}: {detail}")


def latest_run() -> Path | None:
    """가장 최근 `--run` 결과. 라우터 결과에는 답 문장이 없으니 세지 않는다."""
    runs = sorted(p for p in RUNS_DIR.glob("*.json") if not p.stem.endswith("-router"))
    return runs[-1] if runs else None


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="챗봇 평가")
    parser.add_argument("--router", action="store_true",
                        help="말을 가른 결과만 대조한다. 서버가 필요 없다")
    parser.add_argument("--run", action="store_true", help="케이스를 돌려 정답과 대조한다")
    parser.add_argument("--sheet", action="store_true", help="답 문장을 사람이 매길 페이지를 만든다")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--run-file", type=Path, default=None)
    args = parser.parse_args()

    if args.router:
        run_router()
        return 0
    if args.run:
        run(args.base_url)
        return 0
    if args.sheet:
        from job_matching_bot.evaluation.chat_grader_page import write_page

        path = args.run_file or latest_run()
        if path is None:
            print("먼저 --run 으로 결과를 만드세요.")
            return 1
        if path.stem.endswith("-router"):
            print("라우터 결과에는 답 문장이 없습니다. --run 결과를 주세요.")
            return 1
        results = json.loads(path.read_text(encoding="utf-8"))
        page = write_page(path.with_name(path.stem + "-채점.html"), results)
        print(f"채점 페이지: {page}   ← 답 문장만 매기면 된다")
        return 0

    parser.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
