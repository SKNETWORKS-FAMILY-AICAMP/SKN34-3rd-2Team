// scenes.mjs의 화면을 역할별로 찍어 build/onboarding/shots/<role>/<id>.png 로 저장한다.
// 사용: node capture.mjs            (전체)
//       node capture.mjs student    (한 역할만)
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { serveBuild, waitForApp, login, go, dismissTour, outRoot, sleep } from './lib/app.mjs';
import { roles } from './scenes.mjs';

const only = process.argv[2];
const server = await serveBuild();
const browser = await chromium.launch();

async function waitForSpinners(page, maxMs = 6000) {
  // 로딩 표시(progressbar)가 사라질 때까지 기다리되, 끝없이 도는 것은 maxMs에서 끊는다.
  const end = Date.now() + maxMs;
  while (Date.now() < end) {
    const n = await page.locator('flt-semantics[role="progressbar"]').count();
    if (n === 0) return true;
    await sleep(400);
  }
  return false;
}

// 경로 이동만으로는 안 보이는 화면을 열어 둔다. scenes.mjs의 action 이름과 맞춘다.
const sceneActions = {
  async chatbot(page) {
    await page.getByRole('button', { name: '학생 챗봇 열기', exact: true }).click();
    await sleep(1500);
    const input = page.getByRole('textbox', { name: /메시지를 입력하세요/ });
    await input.click();
    await sleep(400);
    await page.keyboard.insertText('3단위기간 출석률 85%면 훈련장려금 받을 수 있어?');
    await page.getByRole('button', { name: '질문 보내기', exact: true }).click();
    // 데모 챗봇은 답을 몇 글자씩 흘려보낸다. 다 나올 때까지 기다린다.
    await sleep(6000);
  },
};
sceneActions.recommend = async (page) => {
  if (!(await page.getByRole('button', { name: /공고 맞춤 첨삭/ }).count())) {
    await page.getByRole('button', { name: '맞춤 공고 추천', exact: true }).click();
    // 데모 추천은 단계 표시를 거쳐 몇 초 뒤 결과가 나온다.
    await sleep(7000);
  }
};
sceneActions.review = async (page) => {
  await sceneActions.recommend(page);
  await page.getByRole('button', { name: /공고 맞춤 첨삭/ }).first().click();
  await sleep(1800);
  await page.getByRole('button', { name: /첨삭 시작/ }).click();
  await sleep(5000);
};

const closeActions = {
  async review(page) {
    await page.getByRole('button', { name: '닫기', exact: true }).first().click().catch(() => {});
    await sleep(800);
  },
  async chatbot(page) {
    await page.getByRole('button', { name: '챗봇 닫기', exact: true }).click().catch(() => {});
    await sleep(500);
  },
};

// 화면 설정에서 테마 항목을 누른다. 항목 전체가 하나의 탭 영역이라 라벨 텍스트로 찾는다.
async function pickTheme(page, label) {
  const byRole = page.getByRole('button', { name: new RegExp(`^${label}`) });
  const target = (await byRole.count()) ? byRole.first() : page.getByText(label, { exact: true }).first();
  await target.click();
  await sleep(800);
}

// 학생 대시보드를 라이트·사이드바 다크·전체 다크로 한 장씩 찍는다 → shots/themes/<id>.png
async function captureThemes(page) {
  const dir = path.join(outRoot, 'shots', 'themes');
  fs.mkdirSync(dir, { recursive: true });
  const themes = [
    ['light', '라이트'],
    ['railDark', '사이드바 다크'],
    ['dark', '전체 다크'],
  ];
  try {
    for (const [id, label] of themes) {
      await go(page, '/settings', 1500);
      await pickTheme(page, label);
      await go(page, '/', 1800);
      await waitForSpinners(page);
      await sleep(500);
      await page.screenshot({ path: path.join(dir, `${id}.png`) });
      console.log(`themes/${id}`);
    }
  } finally {
    // 다음 캡처가 라이트로 찍히도록 되돌린다.
    await go(page, '/settings', 1200);
    await pickTheme(page, '라이트').catch(() => {});
  }
}

try {
  // 로그인 화면은 역할과 무관하게 한 번만 찍는다.
  {
    const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: 'ko-KR' });
    const page = await ctx.newPage();
    await page.goto(server.url);
    await waitForApp(page);
    fs.mkdirSync(path.join(outRoot, 'shots'), { recursive: true });
    await page.screenshot({ path: path.join(outRoot, 'shots', 'login.png') });
    await ctx.close();
  }

  for (const { role, scenes } of roles) {
    if (only && only !== role) continue;
    const dir = path.join(outRoot, 'shots', role);
    fs.mkdirSync(dir, { recursive: true });
    // 역할마다 새 컨텍스트: 데모 세션과 온보딩 dismiss 기록이 섞이지 않는다.
    const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: 'ko-KR' });
    const page = await ctx.newPage();
    page.on('pageerror', (e) => console.error(`[${role}] pageerror`, e.message));
    await page.goto(server.url);
    await waitForApp(page);
    await login(page, role);
    await page.screenshot({ path: path.join(dir, '_tour.png') });
    await dismissTour(page);

    for (const s of scenes) {
      await go(page, s.route, 1800);
      await dismissTour(page);
      const settled = await waitForSpinners(page);
      await sleep(500);
      if (s.action) await sceneActions[s.action](page);
      await page.screenshot({ path: path.join(dir, `${s.id}.png`) });
      if (s.action && closeActions[s.action]) await closeActions[s.action](page);
      console.log(`${role}/${s.id}${settled ? '' : '  (로딩 표시 남음)'}`);
    }
    if (role === 'student') await captureThemes(page);
    await ctx.close();
  }
} finally {
  await browser.close();
  server.close();
}
