// 녹화용 공통 조작: 가짜 커서·강조 상자, 사람처럼 누르기·입력, 로그인, 투어 넘기기.
// record.mjs(역할별 영상)와 guide.mjs(통합 가이드 영상)가 함께 쓴다.
import { accounts, go, sleep } from './app.mjs';

export const size = { width: 1440, height: 900 };

/// Playwright 녹화에는 마우스 커서가 안 찍히므로 가짜 커서와 강조 상자를 DOM에 얹는다.
export async function installCursor(page) {
  await page.evaluate(() => {
    if (document.getElementById('demo-cursor')) return;
    const style = document.createElement('style');
    style.textContent = `
      #demo-cursor { position: fixed; left: 0; top: 0; width: 22px; height: 22px; z-index: 2147483647;
        pointer-events: none; transform: translate(-3px, -2px); transition: transform .02s; }
      #demo-cursor svg { filter: drop-shadow(0 1px 2px rgba(0,0,0,.35)); }
      #demo-cursor.down::after { content: ''; position: absolute; left: -12px; top: -12px; width: 28px; height: 28px;
        border-radius: 50%; background: rgba(11,87,208,.28); animation: ripple .45s ease-out; }
      @keyframes ripple { from { transform: scale(.3); opacity: 1 } to { transform: scale(1.4); opacity: 0 } }
      .demo-highlight { position: fixed; z-index: 2147483646; pointer-events: none; border-radius: 10px;
        border: 3px solid #f97316; box-shadow: 0 0 0 4px rgba(249,115,22,.22);
        animation: demo-hl-in .25s ease-out, demo-hl-pulse 1.2s ease-in-out .25s infinite; transition: opacity .3s; }
      @keyframes demo-hl-in { from { transform: scale(1.08); opacity: 0 } to { transform: scale(1); opacity: 1 } }
      @keyframes demo-hl-pulse { 50% { box-shadow: 0 0 0 9px rgba(249,115,22,.12); } }
    `;
    document.head.appendChild(style);
    const cursor = document.createElement('div');
    cursor.id = 'demo-cursor';
    cursor.innerHTML =
      '<svg width="22" height="22" viewBox="0 0 24 24"><path d="M3 2l7.5 19 2.6-7.9L21 10.5z" fill="#111" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>';
    document.body.appendChild(cursor);
    const move = (e) => (cursor.style.transform = `translate(${e.clientX - 3}px, ${e.clientY - 2}px)`);
    window.addEventListener('pointermove', move, true);
    window.addEventListener('mousemove', move, true);
    window.addEventListener('pointerdown', () => {
      cursor.classList.remove('down');
      void cursor.offsetWidth;
      cursor.classList.add('down');
    }, true);
  });
}

/// 대상이 화면 밖(스크롤로 밀려난 곳)에 있으면 그 자리에서 휠을 굴려 화면 안으로 들인다.
/// Flutter 웹은 DOM 스크롤이 아니라 캔버스 안에서 스크롤하므로 마우스 휠로 움직인다.
/// 돌려주는 값은 화면 안에 들어온 뒤의 위치(없으면 null).
export async function ensureVisible(page, locator) {
  const target = locator.first();
  let box = await target.boundingBox();
  for (let i = 0; box && i < 4; i++) {
    // 상단 고정 헤더(저장·출결 폼 등)는 0 가까이에 있으므로 창 밖으로 벗어났을 때만 굴린다.
    const top = 0;
    const bottom = size.height;
    if (box.y >= top && box.y + box.height <= bottom) break;
    // 대상의 가로 위치(같은 스크롤 영역)에서, 화면 가운데쯤 오도록 굴린다.
    const x = Math.min(Math.max(box.x + box.width / 2, 10), size.width - 10);
    const delta = box.y < top ? box.y - top - 120 : box.y + box.height - bottom + 120;
    await moveTo(page, x, size.height / 2);
    await page.mouse.wheel(0, delta);
    await sleep(600);
    box = await target.boundingBox();
  }
  return box;
}

/// 설명하는 곳에 주황색 상자를 잠깐 띄운다. 기다리지 않고 바로 돌아온다.
export async function highlight(page, locator, ms = 2600, pad = 6) {
  if (!(await locator.count())) return;
  const box = await ensureVisible(page, locator);
  if (!box) return;
  await page.evaluate(
    ([b, ms, pad]) => {
      const el = document.createElement('div');
      el.className = 'demo-highlight';
      Object.assign(el.style, {
        left: `${b.x - pad}px`,
        top: `${b.y - pad}px`,
        width: `${b.width + pad * 2}px`,
        height: `${b.height + pad * 2}px`,
      });
      document.body.appendChild(el);
      setTimeout(() => (el.style.opacity = '0'), ms);
      setTimeout(() => el.remove(), ms + 400);
    },
    [box, ms, pad],
  );
}

let mouse = { x: size.width / 2, y: size.height / 2 };
export function resetMouse() {
  mouse = { x: size.width / 2, y: size.height / 2 };
}

export async function moveTo(page, x, y) {
  const steps = Math.max(8, Math.round(Math.hypot(x - mouse.x, y - mouse.y) / 25));
  await page.mouse.move(x, y, { steps });
  mouse = { x, y };
}

/// 사람이 누르는 것처럼 커서를 옮긴 뒤 누른다.
export async function tap(page, locator, { pause = 700 } = {}) {
  const target = locator.first();
  await target.waitFor({ state: 'attached', timeout: 15_000 });
  const box = await ensureVisible(page, target);
  if (!box) throw new Error('누를 위치를 찾지 못했습니다');
  await moveTo(page, box.x + box.width / 2, box.y + box.height / 2);
  await sleep(250);
  await page.mouse.down();
  await page.mouse.up();
  await sleep(pause);
}

/// 좌표를 누른다(접근성 라벨이 없는 아이콘 버튼용).
export async function tapAt(page, x, y, pause = 700) {
  await moveTo(page, x, y);
  await sleep(250);
  await page.mouse.down();
  await page.mouse.up();
  await sleep(pause);
}

/// 있으면 누르고, 없으면 넘어간다.
export async function tapIf(page, locator, opts) {
  if (await locator.count()) {
    await tap(page, locator, opts);
    return true;
  }
  return false;
}

/// 누르지 않고 커서만 올린다.
export async function hover(page, locator, holdMs = 800) {
  if (!(await locator.count())) return;
  const box = await ensureVisible(page, locator);
  if (box) await moveTo(page, box.x + box.width / 2, box.y + box.height / 2);
  await sleep(holdMs);
}

export async function typeInto(page, locator, text) {
  // 누른 직후 바로 치면 앞 글자가 빠진다(포커스 전환 전). 잠깐 기다린다.
  await tap(page, locator, { pause: 450 });
  // 한 글자씩 keyboard.type 하면 녹화 중에는 키마다 한참 걸려 로그인만 20초가 넘는다.
  // 두세 글자씩 끊어 넣어 타이핑처럼 보이게 한다.
  for (let i = 0; i < text.length; i += 3) {
    await page.keyboard.insertText(text.slice(i, i + 3));
    await sleep(70);
  }
  await sleep(300);
}

export const btn = (page, name) => page.getByRole('button', { name, exact: true });
export const btnLike = (page, re) => page.getByRole('button', { name: re });

/// 사이드바 메뉴를 누른다. 라벨이 semantics에 없으면 hash 이동으로 대신한다.
export async function openMenu(page, label, fallbackRoute) {
  if (!(await tapIf(page, btn(page, label), { pause: 1800 }))) await go(page, fallbackRoute, 1800);
}

export async function login(page, role) {
  const { email, password } = accounts[role];
  await typeInto(page, page.getByRole('textbox').nth(0), email);
  await typeInto(page, page.getByRole('textbox').nth(1), password);
  await tap(page, btn(page, '로그인'), { pause: 3500 });
  await installCursor(page);
}

/// 앱의 이용 안내 투어를 끝까지 넘긴다.
export async function walkTour(page, perStepMs = 1900) {
  for (let i = 0; i < 30; i++) {
    const done = btn(page, '완료');
    if (await done.count()) {
      await sleep(perStepMs);
      await tap(page, done, { pause: 1200 });
      return;
    }
    const next = btn(page, '다음');
    if (!(await next.count())) return;
    await sleep(perStepMs);
    await tap(page, next, { pause: 900 });
  }
}

/// 이력서 편집 화면 오른쪽 AI 코치 패널을 맨 위로 되돌린다.
/// 추천 결과를 펼치거나 내리면 패널 안에서만 스크롤되어, 위의 「이력서 첨삭」 버튼이
/// 패널 영역 밖으로 가려진다(창 좌표로는 화면 안이라 ensureVisible이 못 잡는다).
export async function scrollCoachPanelToTop(page) {
  await moveTo(page, size.width - 200, size.height / 2);
  await page.mouse.wheel(0, -3000);
  await sleep(700);
}

/// 화면 설정의 테마 항목. "라벨 + 설명"이 한 버튼이라 라벨로 시작하는 이름으로 찾는다.
export const themeOption = (page, label) => btnLike(page, new RegExp(`^${label} `));
