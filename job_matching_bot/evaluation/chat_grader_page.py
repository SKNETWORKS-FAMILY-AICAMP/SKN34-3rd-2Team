"""챗봇 답 문장을 사람이 매기는 페이지.

## 여기서 매기는 것만 사람이 필요하다

의도·조건·번호 가리키기·응답 시간은 정답이 있어 `chat_eval --run`이 자동으로
대조한다. 사람이 매길 것은 **자동으로는 못 보는 둘**이다.

1. **근거** — 답이 실제 공고·통계에서 나왔는가, 아니면 어디서나 들을 수 있는
   일반론인가. 우리 데이터를 안 보고도 쓸 수 있는 답이면 이 서비스일 이유가 없다.
2. **지어냄** — 공고에 없는 마감일·연봉·복지를 만들어 냈는가. 이게 하나라도 있으면
   나머지 답도 못 믿는다.

## 한 화면에서 끝낸다

추천 채점 페이지와 같은 방식이다. 물음과 답, 그리고 답의 근거가 된 공고를 나란히
놓고 그 자리에서 매긴다. 문서와 표를 오가지 않는다.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

_STYLE = """
:root{--bg:#f6f7f9;--card:#fff;--line:#e5e7eb;--ink:#111827;--dim:#6b7280;
--blue:#0055ff;--green:#16a34a;--red:#dc2626;--warn:#b45309}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);
font:15px/1.6 Pretendard,"Apple SD Gothic Neo","Malgun Gothic",system-ui,sans-serif}
header{position:sticky;top:0;z-index:5;background:var(--card);
border-bottom:1px solid var(--line);padding:10px 20px;display:flex;
align-items:center;gap:14px;flex-wrap:wrap}
h1{font-size:15px;margin:0;font-weight:700}
.bar{flex:1;min-width:160px;height:6px;background:var(--line);border-radius:3px;overflow:hidden}
.bar>i{display:block;height:100%;background:var(--green);width:0;transition:width .2s}
.count{font-variant-numeric:tabular-nums;color:var(--dim);font-size:13px}
main{max-width:960px;margin:0 auto;padding:20px}
.who{color:var(--dim);font-size:13px;margin-bottom:6px}
.turn{background:var(--card);border:1px solid var(--line);border-radius:10px;
padding:14px 16px;margin-bottom:10px}
.turn.prev{opacity:.55}
.me{font-weight:700;margin-bottom:8px}
.me span{color:var(--dim);font-weight:400;font-size:12px;margin-left:8px}
.bot{white-space:pre-wrap}
.mode{display:inline-block;font-size:11px;color:var(--dim);border:1px solid var(--line);
border-radius:4px;padding:1px 6px;margin-left:6px}
.jobs{margin-top:10px;border-top:1px dashed var(--line);padding-top:8px;
font-size:13px;color:var(--dim)}
.jobs b{color:var(--ink);font-weight:600}
.ask{background:var(--card);border:1px solid var(--line);border-radius:10px;
padding:16px;margin-top:16px}
.q{font-size:13px;color:var(--dim);margin:2px 0 8px}
.btns{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:14px}
button{font:inherit;cursor:pointer;border-radius:8px;padding:9px 15px;
border:1px solid var(--line);background:#fff;color:var(--ink)}
button:hover{border-color:var(--blue)}
button.on{color:#fff;border-color:transparent}
button.yes.on{background:var(--green)}button.mid.on{background:var(--warn)}
button.no.on{background:var(--red)}
kbd{font:12px ui-monospace,monospace;background:var(--bg);border:1px solid var(--line);
border-bottom-width:2px;border-radius:4px;padding:1px 5px;margin-left:6px;color:var(--dim)}
textarea{width:100%;margin-top:6px;padding:8px 10px;border:1px solid var(--line);
border-radius:8px;font:inherit;resize:vertical}
nav{display:flex;gap:10px;margin-top:18px;align-items:center}
.hint{color:var(--dim);font-size:12px}
.done{background:var(--card);border:1px solid var(--line);border-radius:10px;
padding:24px;text-align:center;margin-top:18px}
.big{background:var(--blue);color:#fff;border-color:transparent;padding:12px 22px;font-weight:600}
"""

_SCRIPT = r"""
const ITEMS = JSON.parse(document.getElementById('items').textContent);
const KEY = 'chat-eval-' + document.body.dataset.stamp;
let marks = {};
try { marks = JSON.parse(localStorage.getItem(KEY) || '{}'); } catch (e) { marks = {}; }
let at = 0;

const esc = (s) => String(s ?? '').replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
const save = () => { try { localStorage.setItem(KEY, JSON.stringify(marks)); } catch (e) {} };

function mark(field, value) {
  const it = ITEMS[at];
  marks[it.번호] = Object.assign({근거:'', 지어냄:'', 메모:''}, marks[it.번호], {[field]: value});
  save();
  const m = marks[it.번호];
  if (m.근거 && m.지어냄) {
    if (at < ITEMS.length - 1) { at += 1; }
  }
  draw();
}

function turnHtml(t, isLast) {
  const jobs = (t.jobs || []).map(j =>
    '<div><b>' + esc(j.company) + '</b> · ' + esc(j.title) + '</div>').join('');
  return '<div class="turn' + (isLast ? '' : ' prev') + '">'
    + '<div class="me">' + esc(t.message)
    + '<span>' + t.elapsed.toFixed(1) + '초</span></div>'
    + '<div class="bot">' + esc(t.reply) + '</div>'
    + '<span class="mode">' + esc(t.mode) + '</span>'
    + (jobs ? '<div class="jobs">답에 붙은 공고<br>' + jobs + '</div>' : '')
    + '</div>';
}

function draw() {
  const it = ITEMS[at];
  const m = marks[it.번호] || {};
  const graded = Object.values(marks).filter(x => x.근거 && x.지어냄).length;
  document.querySelector('.bar>i').style.width = (graded / ITEMS.length * 100) + '%';
  document.querySelector('.count').textContent = graded + ' / ' + ITEMS.length + ' 매김';
  const on = (f, v) => (m[f] === v ? ' on' : '');
  document.querySelector('main').innerHTML = `
    <div class="who">${esc(it.번호)}번 · ${esc(it.id)} — ${esc(it.note)}</div>
    ${it.turns.map((t, i) => turnHtml(t, i === it.turns.length - 1)).join('')}
    <div class="ask">
      <div class="q">마지막 답이 <b>우리 데이터</b>에서 나왔나요? 공고나 통계를 안 보고도 쓸 수 있는 답이면 "일반론"입니다.</div>
      <div class="btns">
        <button class="yes${on('근거','근거 있음')}" onclick="mark('근거','근거 있음')">근거 있음<kbd>1</kbd></button>
        <button class="mid${on('근거','일반론')}" onclick="mark('근거','일반론')">일반론<kbd>2</kbd></button>
        <button class="no${on('근거','해당 없음')}" onclick="mark('근거','해당 없음')">해당 없음<kbd>3</kbd></button>
      </div>
      <div class="q">공고에 <b>없는 것</b>을 지어냈나요? 마감일·연봉·복지·합격 가능성이 특히 그렇습니다.</div>
      <div class="btns">
        <button class="yes${on('지어냄','없음')}" onclick="mark('지어냄','없음')">지어낸 것 없음<kbd>A</kbd></button>
        <button class="no${on('지어냄','있음')}" onclick="mark('지어냄','있음')">지어냄 있음<kbd>S</kbd></button>
      </div>
      <textarea rows="2" placeholder="메모 (선택)" oninput="memo(this.value)">${esc(m.메모 || '')}</textarea>
    </div>
    <nav>
      <button onclick="go(-1)">← 이전</button>
      <button onclick="go(1)">다음 →</button>
      <span class="hint">1/2/3 으로 근거, A/S 로 지어냄. 둘 다 고르면 자동으로 다음</span>
    </nav>
    ${graded === ITEMS.length ? `
      <div class="done">
        <p>${ITEMS.length}건 전부 매겼습니다.</p>
        <button class="big" onclick="download()">채점표 CSV 내려받기</button>
      </div>` : ''}
  `;
}

function memo(v) {
  const it = ITEMS[at];
  marks[it.번호] = Object.assign({근거:'', 지어냄:''}, marks[it.번호], {메모: v});
  save();
}
function go(d) { at = Math.min(ITEMS.length - 1, Math.max(0, at + d)); draw(); }

function csv() {
  const cell = (v) => {
    const s = String(v ?? '');
    return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  };
  const head = ['번호', 'id', '물음', '근거', '지어냄', '메모'];
  const lines = [head.join(',')];
  for (const it of ITEMS) {
    const m = marks[it.번호] || {};
    const last = it.turns[it.turns.length - 1];
    lines.push([it.번호, it.id, last.message, m.근거 || '', m.지어냄 || '', m.메모 || '']
      .map(cell).join(','));
  }
  return '﻿' + lines.join('\n');
}

function download() {
  const blob = new Blob([csv()], {type: 'text/csv;charset=utf-8'});
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'chat_eval_labels.csv';
  a.click();
}

document.addEventListener('keydown', (e) => {
  if (e.target.tagName === 'TEXTAREA') return;
  const byKey = {'1':['근거','근거 있음'], '2':['근거','일반론'], '3':['근거','해당 없음'],
                 'a':['지어냄','없음'], 's':['지어냄','있음'],
                 'A':['지어냄','없음'], 'S':['지어냄','있음']};
  if (byKey[e.key]) { mark(...byKey[e.key]); return; }
  if (e.key === 'ArrowLeft') go(-1);
  if (e.key === 'ArrowRight') go(1);
});

draw();
"""


def build_page(results: list[dict[str, Any]], stamp: str) -> str:
    """채점 페이지 HTML. 바깥에서 받아오는 것 없이 파일 하나로 열린다."""
    payload = []
    for number, case in enumerate(results, 1):
        payload.append({
            "번호": number,
            "id": case["id"],
            "note": case.get("note", ""),
            "turns": [
                {
                    "message": turn["message"],
                    "reply": (turn["got"].get("reply") or "").strip(),
                    "mode": turn["got"].get("mode", ""),
                    "elapsed": round(float(turn["elapsed"]), 2),
                    "jobs": [
                        {"company": j.get("company", ""), "title": j.get("title", "")}
                        for j in (turn["got"].get("jobs") or [])
                    ],
                }
                for turn in case["turns"]
            ],
        })
    # `</script>`가 답 안에 있으면 블록이 일찍 닫힌다. 그 한 자리만 막는다.
    data = json.dumps(payload, ensure_ascii=False).replace("</", "<\\/")
    return (
        '<!doctype html>\n<html lang="ko"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        f"<title>챗봇 채점 · {stamp}</title><style>{_STYLE}</style></head>"
        f'<body data-stamp="{stamp}">'
        "<header><h1>챗봇 답 채점</h1>"
        '<div class="bar"><i></i></div><div class="count"></div></header>'
        "<main></main>"
        f'<script id="items" type="application/json">{data}</script>'
        f"<script>{_SCRIPT}</script></body></html>"
    )


def write_page(path: Path, results: list[dict[str, Any]]) -> Path:
    path.write_text(build_page(results, path.stem), encoding="utf-8")
    return path
