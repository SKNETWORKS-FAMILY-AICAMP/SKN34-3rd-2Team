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
      await page.screenshot({ path: path.join(dir, `${s.id}.png`) });
      console.log(`${role}/${s.id}${settled ? '' : '  (로딩 표시 남음)'}`);
    }
    await ctx.close();
  }
} finally {
  await browser.close();
  server.close();
}
