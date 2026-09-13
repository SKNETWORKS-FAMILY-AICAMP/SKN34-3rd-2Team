// 역할별 시연 영상을 녹화한다. 결과: onboarding/output/videos/<순번>_<역할>_시연.mp4
// 사용: node record.mjs              (전체)
//       node record.mjs student      (한 역할만)
// Playwright 녹화에는 마우스 커서가 안 찍히므로, 가짜 커서와 자막을 DOM에 얹어 함께 녹화한다.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { chromium } from 'playwright';
import { serveBuild, waitForApp, accounts, go, outRoot, deliverRoot, sleep } from './lib/app.mjs';

const only = process.argv[2];
const size = { width: 1440, height: 900 };
const videoDir = path.join(deliverRoot, 'videos');
const rawDir = path.join(outRoot, 'videos-raw');
fs.mkdirSync(videoDir, { recursive: true });
fs.mkdirSync(rawDir, { recursive: true });

async function installOverlay(page) {
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
      #demo-caption { position: fixed; left: 50%; bottom: 36px; transform: translateX(-50%); z-index: 2147483646;
        pointer-events: none; background: rgba(17,24,39,.88); color: #fff; border-radius: 14px;
        padding: 14px 26px; font: 600 22px/1.4 'Noto Sans KR','Malgun Gothic',sans-serif; letter-spacing: -.01em;
        box-shadow: 0 8px 24px rgba(0,0,0,.25); opacity: 0; transition: opacity .35s; max-width: 80vw; text-align: center; }
      #demo-caption small { display: block; font-weight: 400; font-size: 16px; color: #cbd5e1; margin-top: 2px; }
      #demo-caption.show { opacity: 1; }
    `;
    document.head.appendChild(style);
    const cursor = document.createElement('div');
    cursor.id = 'demo-cursor';
    cursor.innerHTML =
      '<svg width="22" height="22" viewBox="0 0 24 24"><path d="M3 2l7.5 19 2.6-7.9L21 10.5z" fill="#111" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>';
    document.body.appendChild(cursor);
    const caption = document.createElement('div');
    caption.id = 'demo-caption';
    document.body.appendChild(caption);
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

async function caption(page, title, sub = '', holdMs = 1600) {
  await page.evaluate(
    ([t, s]) => {
      const el = document.getElementById('demo-caption');
      el.innerHTML = s ? `${t}<small>${s}</small>` : t;
      el.classList.add('show');
    },
    [title, sub],
  );
  await sleep(holdMs);
}

async function hideCaption(page) {
  await page.evaluate(() => document.getElementById('demo-caption')?.classList.remove('show'));
}

let mouse = { x: size.width / 2, y: size.height / 2 };
async function moveTo(page, x, y) {
  const steps = Math.max(8, Math.round(Math.hypot(x - mouse.x, y - mouse.y) / 25));
  await page.mouse.move(x, y, { steps });
  mouse = { x, y };
}

/// 사람이 누르는 것처럼 커서를 옮긴 뒤 누른다.
async function tap(page, locator, { pause = 700 } = {}) {
  const target = locator.first();
  await target.waitFor({ state: 'attached', timeout: 15_000 });
  const box = await target.boundingBox();
  if (!box) throw new Error('누를 위치를 찾지 못했습니다');
  await moveTo(page, box.x + box.width / 2, box.y + box.height / 2);
  await sleep(250);
  await page.mouse.down();
  await page.mouse.up();
  await sleep(pause);
}

async function typeInto(page, locator, text) {
  await tap(page, locator, { pause: 200 });
  await page.keyboard.type(text, { delay: 55 });
  await sleep(300);
}

const btn = (page, name) => page.getByRole('button', { name, exact: true });

/// 사이드바 메뉴를 누른다. 라벨이 semantics에 없으면 hash 이동으로 대신한다.
async function openMenu(page, label, fallbackRoute) {
  const loc = page.getByRole('button', { name: label, exact: true });
  if (await loc.count()) {
    await tap(page, loc, { pause: 1800 });
  } else {
    await go(page, fallbackRoute, 1800);
  }
}

async function login(page, role) {
  const { email, password } = accounts[role];
  await typeInto(page, page.getByRole('textbox').nth(0), email);
  await typeInto(page, page.getByRole('textbox').nth(1), password);
  await tap(page, btn(page, '로그인'), { pause: 3500 });
  await installOverlay(page);
}

/// 앱의 이용 안내 투어를 끝까지 넘긴다.
async function walkTour(page, perStepMs = 1900) {
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

const scripts = {
  async student(page) {
    await caption(page, '학생으로 로그인', '매니저에게 받은 이메일과 비밀번호를 입력합니다', 900);
    await login(page, 'student');
    await hideCaption(page);

    await caption(page, '처음 로그인하면 이용 안내가 뜹니다', '「다음」을 눌러 메뉴를 하나씩 살펴봅니다', 2200);
    await walkTour(page);
    await hideCaption(page);

    await caption(page, '성취도평가 응시하기', '공개된 평가를 골라 문제를 풀고 제출합니다', 2000);
    await openMenu(page, '성취도평가', '/assessments');
    await hideCaption(page);
    const card = page.getByText('34기 2차 성취도평가', { exact: false });
    if (await card.count()) {
      await tap(page, card, { pause: 1500 });
    } else {
      await go(page, '/assessments/a1/take', 1500);
    }
    const choice = page.getByText('정규화를 사용한다', { exact: false });
    if (await choice.count()) await tap(page, choice, { pause: 900 });
    const answer = page.getByRole('textbox');
    if (await answer.count()) await typeInto(page, answer.last(), 'label');
    const submit = btn(page, '제출');
    if (await submit.count()) {
      await tap(page, submit, { pause: 1200 });
      const confirm = btn(page, '제출');
      if (await confirm.count()) await tap(page, confirm, { pause: 1200 });
    }
    await caption(page, '제출하면 바로 점수를 확인할 수 있습니다', '', 2600);
    await hideCaption(page);

    await go(page, '/', 1200);
    await caption(page, '기록실에 기록 제출하기', '자격증·스터디·블로그 기록이 승인되면 마일리지가 쌓입니다', 2000);
    await openMenu(page, '기록실', '/records');
    const add = page.getByRole('button', { name: /새로운 기록 추가/ });
    if (await add.count()) await tap(page, add, { pause: 2500 });
    else await go(page, '/records/create', 2500);
    await hideCaption(page);

    await caption(page, '마일리지로 상품 교환하기', '상품을 담아 구매를 요청하면 매니저가 승인합니다', 2000);
    await openMenu(page, '마일리지', '/mileage');
    const shop = page.getByRole('button', { name: /마일리지 사용하기/ });
    if (await shop.count()) await tap(page, shop, { pause: 2600 });
    else await go(page, '/mileage/shop', 2600);
    await hideCaption(page);

    await caption(page, '마이페이지', '프로필·비밀번호 관리, 이용 안내 다시보기', 1800);
    await go(page, '/my-page', 2400);
    await hideCaption(page);
    await caption(page, '학생 시연 끝', 'PLAYDATA LMS', 2200);
  },

  async instructor(page) {
    await caption(page, '강사로 로그인', '', 900);
    await login(page, 'instructor');
    await hideCaption(page);

    await caption(page, '강사 메뉴 둘러보기', '이용 안내 투어로 주요 메뉴를 확인합니다', 2200);
    await walkTour(page);
    await hideCaption(page);

    await caption(page, '성취도평가 만들기', '제목·기간을 정하고 문항을 추가합니다', 2000);
    await openMenu(page, '성취도평가', '/instructor/assessments');
    const create = page.getByRole('button', { name: /평가 만들기/ });
    if (await create.count()) await tap(page, create, { pause: 2200 });
    else await go(page, '/instructor/assessments/create', 2200);
    const titleBox = page.getByRole('textbox');
    if (await titleBox.count()) await typeInto(page, titleBox.first(), '34기 3차 성취도평가');
    await caption(page, '「문제 생성 AI」로 커리큘럼 기반 문항 초안을 만들 수 있습니다', '', 2800);
    await hideCaption(page);

    await go(page, '/instructor', 800);
    await caption(page, '커리큘럼 등록', '구글 시트를 CSV로 내려받아 올립니다', 2000);
    await openMenu(page, '커리큘럼', '/instructor/curriculum');
    await sleep(1500);
    await hideCaption(page);
    await caption(page, '강사 시연 끝', 'PLAYDATA LMS', 2200);
  },

  async admin(page) {
    await caption(page, '관리자로 로그인', '', 900);
    await login(page, 'admin');
    await hideCaption(page);

    await caption(page, '관리자 메뉴 둘러보기', '이용 안내 투어로 사이드바 메뉴 전체를 확인합니다', 2200);
    await walkTour(page, 1700);
    await hideCaption(page);

    await caption(page, '기수 관리', '교육 기간과 기수 설정을 관리합니다', 1800);
    await go(page, '/admin/cohorts', 2200);
    await hideCaption(page);

    await caption(page, '출석 관리', '당일 출석 조회·수정과 08:30 출결 공지 등록', 1800);
    await go(page, '/admin/attendance', 2400);
    await hideCaption(page);

    await caption(page, '마일리지 관리', '상품·구매 요청·수동 지급·적립 규칙', 1800);
    await go(page, '/admin/mileage', 1500);
    const products = page.getByText('상품 관리', { exact: false });
    if (await products.count()) await tap(page, products, { pause: 2400 });
    await hideCaption(page);
    await caption(page, '관리자 시연 끝', 'PLAYDATA LMS', 2200);
  },
};

const order = ['student', 'instructor', 'admin'];
const labels = { student: '학생', instructor: '강사', admin: '관리자' };
const server = await serveBuild(5180);
const browser = await chromium.launch();

try {
  for (const [i, role] of order.entries()) {
    if (only && only !== role) continue;
    const ctx = await browser.newContext({
      viewport: size,
      locale: 'ko-KR',
      recordVideo: { dir: rawDir, size },
    });
    const page = await ctx.newPage();
    mouse = { x: size.width / 2, y: size.height / 2 };
    await page.goto(server.url);
    await waitForApp(page);
    await installOverlay(page);
    await sleep(800);
    try {
      await scripts[role](page);
    } catch (e) {
      console.error(`[${role}] 시나리오 중단:`, e.message);
    }
    const video = page.video();
    await ctx.close();
    const raw = await video.path();
    const mp4 = path.join(videoDir, `${i + 1}_${labels[role]}_시연.mp4`);
    // 첫 1.5초는 앱 로딩 흰 화면이라 잘라낸다.
    execFileSync('ffmpeg', [
      '-hide_banner', '-loglevel', 'error', '-y',
      '-ss', '1.5', '-i', raw,
      '-c:v', 'libx264', '-preset', 'medium', '-crf', '22', '-pix_fmt', 'yuv420p',
      '-movflags', '+faststart', mp4,
    ]);
    console.log(mp4);
  }
} finally {
  await browser.close();
  server.close();
}
