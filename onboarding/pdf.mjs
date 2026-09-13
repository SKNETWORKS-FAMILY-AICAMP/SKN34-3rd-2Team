// capture.mjs가 찍은 화면으로 A4 사용자 안내서 PDF를 만든다.
// 결과: onboarding/output/PLAYDATA_LMS_사용자_가이드.pdf (중간 .html은 build/onboarding)
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { chromium } from 'playwright';
import { outRoot, deliverRoot } from './lib/app.mjs';
import { roles } from './scenes.mjs';

const shots = path.join(outRoot, 'shots');
const baseName = 'PLAYDATA_LMS_사용자_가이드';
const today = new Date();
const dateLabel = `${today.getFullYear()}.${String(today.getMonth() + 1).padStart(2, '0')}.${String(today.getDate()).padStart(2, '0')}`;

const esc = (s) =>
  String(s).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

function img(rel) {
  const abs = path.join(shots, rel);
  if (!fs.existsSync(abs)) throw new Error(`캡처가 없습니다: ${abs} (node capture.mjs 먼저)`);
  return pathToFileURL(abs).href;
}

const roleColor = { student: '#1f6feb', instructor: '#0f9d76', admin: '#7c4dff' };

function sceneBlock(role, s, index) {
  const tips = s.tips?.length
    ? `<ul class="tips">${s.tips.map((t) => `<li>${esc(t)}</li>`).join('')}</ul>`
    : '';
  return `
  <section class="scene">
    <div class="scene-head">
      <span class="num" style="background:${roleColor[role]}">${index}</span>
      <h3>${esc(s.title)}</h3>
    </div>
    <p class="desc">${esc(s.desc)}</p>
    ${tips}
    <figure><img src="${img(`${role}/${s.id}.png`)}" alt="${esc(s.title)} 화면"></figure>
  </section>`;
}

const toc = roles
  .map(
    (r, i) => `
    <li>
      <span class="toc-part" style="color:${roleColor[r.role]}">PART ${i + 2}</span>
      <strong>${esc(r.label)}</strong>
      <span class="toc-items">${r.scenes.map((s) => esc(s.title)).join(' · ')}</span>
    </li>`,
  )
  .join('');

const roleSections = roles
  .map(
    (r, i) => `
  <section class="divider" style="--accent:${roleColor[r.role]}">
    <p class="part">PART ${i + 2}</p>
    <h2>${esc(r.label)} 화면 안내</h2>
    <p class="intro">${esc(r.intro)}</p>
    <div class="menu-grid">
      ${r.scenes.map((s, j) => `<div><span>${j + 1}</span>${esc(s.title)}</div>`).join('')}
    </div>
  </section>
  ${r.scenes.map((s, j) => sceneBlock(r.role, s, j + 1)).join('')}`,
  )
  .join('');

const html = `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<title>PLAYDATA LMS 사용자 가이드</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;500;700;900&display=swap" rel="stylesheet">
<style>
  @page { size: A4; margin: 12mm 14mm 14mm 14mm; }
  * { box-sizing: border-box; }
  html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  body {
    margin: 0;
    font-family: 'Noto Sans KR', 'Malgun Gothic', sans-serif;
    color: #1d2433;
    font-size: 10pt;
    line-height: 1.65;
    word-break: keep-all;
  }
  h1, h2, h3 { margin: 0; line-height: 1.3; }

  /* 표지 */
  .cover {
    height: 268mm;
    display: flex; flex-direction: column; justify-content: space-between;
    page-break-after: always;
    padding: 6mm 2mm;
  }
  .brand { font-weight: 900; font-size: 13pt; letter-spacing: .06em; color: #0b57d0; }
  .cover h1 { font-size: 32pt; font-weight: 900; letter-spacing: -.02em; margin-top: 50mm; }
  .cover .sub { font-size: 13pt; color: #4b5565; margin-top: 5mm; }
  .cover .roles { display: flex; gap: 3mm; margin-top: 10mm; }
  .cover .roles span {
    border-radius: 99px; padding: 1.5mm 5mm; font-weight: 700; font-size: 10pt; color: #fff;
  }
  .cover img { width: 100%; border-radius: 3mm; border: 1px solid #dfe3ea; box-shadow: 0 2mm 6mm rgba(20,30,60,.12); }
  .cover .meta { color: #7a8494; font-size: 9pt; display: flex; justify-content: space-between; }

  /* 목차 · 시작하기 */
  .page { page-break-after: always; }
  .page h2 { font-size: 20pt; font-weight: 900; margin-bottom: 6mm; }
  .toc { list-style: none; padding: 0; margin: 0 0 10mm; }
  .toc li { padding: 4mm 0; border-bottom: 1px solid #e6e9ef; display: grid; grid-template-columns: 22mm 22mm 1fr; align-items: baseline; }
  .toc-part { font-weight: 900; font-size: 9pt; letter-spacing: .05em; }
  .toc li strong { font-size: 12pt; }
  .toc-items { color: #5b6575; font-size: 9pt; }
  .toc .start .toc-part { color: #0b57d0; }

  .steps { counter-reset: step; list-style: none; padding: 0; margin: 0; }
  .steps > li { counter-increment: step; position: relative; padding: 0 0 5mm 11mm; }
  .steps > li::before {
    content: counter(step); position: absolute; left: 0; top: .5mm;
    width: 7mm; height: 7mm; border-radius: 50%; background: #0b57d0; color: #fff;
    font-weight: 700; font-size: 9pt; display: flex; align-items: center; justify-content: center;
  }
  .steps h4 { margin: 0 0 1mm; font-size: 11pt; }
  .steps p { margin: 0; color: #3d4757; }

  table.accounts { width: 100%; border-collapse: collapse; margin: 2mm 0 0; font-size: 9.5pt; }
  table.accounts th, table.accounts td { border: 1px solid #dfe3ea; padding: 2mm 3mm; text-align: left; }
  table.accounts th { background: #f3f6fb; }

  .note {
    background: #f3f6fb; border-left: 1.2mm solid #0b57d0; border-radius: 1.5mm;
    padding: 3mm 4mm; margin: 4mm 0; color: #334;
  }
  .two { display: grid; grid-template-columns: 1fr 1fr; gap: 5mm; margin-top: 3mm; }
  .two figure { margin: 0; }
  .two img { width: 100%; border: 1px solid #dfe3ea; border-radius: 2mm; }
  .two figcaption { font-size: 8.5pt; color: #6b7585; margin-top: 1mm; }

  /* 역할 구분 페이지 */
  .divider { page-break-before: always; page-break-after: always; padding-top: 55mm; }
  .divider .part { color: var(--accent); font-weight: 900; letter-spacing: .1em; margin: 0; }
  .divider h2 { font-size: 30pt; font-weight: 900; margin: 2mm 0 5mm; }
  .divider .intro { font-size: 12pt; color: #4b5565; max-width: 150mm; }
  .menu-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 2.5mm; margin-top: 14mm; }
  .menu-grid div { border: 1px solid #e1e5ec; border-radius: 2mm; padding: 2.5mm 3mm; font-weight: 500; }
  .menu-grid span { display: inline-block; min-width: 6mm; color: var(--accent); font-weight: 900; }

  /* 화면 설명 — A4 한 쪽에 두 화면이 들어가도록 캡처 폭을 160mm(높이 100mm)로 둔다 */
  .scene { break-inside: avoid; page-break-inside: avoid; margin-bottom: 6mm; }
  .scene + .scene { border-top: 1px solid #e6e9ef; padding-top: 5mm; }
  .scene-head { display: flex; align-items: center; gap: 3mm; margin-bottom: 1.5mm; }
  .num { width: 7mm; height: 7mm; border-radius: 1.5mm; color: #fff; font-weight: 900; font-size: 9pt; display: flex; align-items: center; justify-content: center; }
  .scene h3 { font-size: 14pt; font-weight: 700; }
  .desc { margin: 0 0 1.5mm; color: #333c4b; }
  .tips { margin: 0 0 2mm; padding-left: 5mm; color: #0b57d0; font-size: 9pt; }
  .scene figure { margin: 2mm 0 0; }
  .scene img { width: 160mm; margin: 0 auto; display: block; border: 1px solid #dfe3ea; border-radius: 2mm; box-shadow: 0 1mm 3mm rgba(20,30,60,.08); }

  dl.faq dt { font-weight: 700; margin-top: 4mm; }
  dl.faq dd { margin: 1mm 0 0; color: #3d4757; }
</style>
</head>
<body>

<section class="cover">
  <div class="brand">PLAYDATA</div>
  <div>
    <h1>LMS 사용자 가이드</h1>
    <p class="sub">처음 로그인부터 역할별 주요 화면까지</p>
    <div class="roles">
      ${roles.map((r) => `<span style="background:${roleColor[r.role]}">${esc(r.label)}</span>`).join('')}
    </div>
  </div>
  <img src="${img('student/dashboard.png')}" alt="학생 대시보드">
  <div class="meta"><span>SK네트웍스 Family AI 캠프</span><span>${dateLabel} 기준</span></div>
</section>

<section class="page">
  <h2>목차</h2>
  <ol class="toc">
    <li class="start"><span class="toc-part">PART 1</span><strong>시작하기</strong><span class="toc-items">로그인 · 비밀번호 변경 · 이용 안내 투어 · 화면 구성</span></li>
    ${toc}
    <li class="start"><span class="toc-part">부록</span><strong>자주 묻는 질문</strong><span class="toc-items">로그인이 안 될 때 · 이용 안내 다시 보기 · 문의</span></li>
  </ol>
  <div class="note">
    이 안내서의 화면은 <b>데모 계정</b>으로 찍었습니다. 이름·이메일·점수는 예시이며 실제 수강생 정보가 아닙니다.
    기수 운영 상황에 따라 메뉴 이름이나 표시 내용이 조금 다를 수 있습니다.
  </div>
</section>

<section class="page">
  <h2>PART 1 · 시작하기</h2>
  <ol class="steps">
    <li>
      <h4>접속하기</h4>
      <p>매니저가 안내한 주소로 접속합니다. PC에서는 Chrome 브라우저를 권장합니다.</p>
    </li>
    <li>
      <h4>로그인</h4>
      <p>발급받은 이메일과 비밀번호를 입력하고 「로그인」을 누릅니다. 계정은 관리자가 발급·재설정하므로, 계정이 없거나 비밀번호를 잊었다면 매니저에게 요청하세요.</p>
    </li>
    <li>
      <h4>첫 로그인 시 비밀번호 변경</h4>
      <p>처음 로그인하면 「비밀번호 변경」 화면이 나옵니다. 새 비밀번호를 정해야 다음 화면으로 넘어갑니다.</p>
    </li>
    <li>
      <h4>이용 안내 투어</h4>
      <p>로그인 직후 메뉴를 하나씩 짚어 주는 안내 말풍선이 뜹니다. 「다음」으로 넘기고, 필요 없으면 「다시 보지 않기」를 누르세요. 마이페이지의 「이용 안내 다시보기」로 언제든 다시 볼 수 있습니다.</p>
    </li>
    <li>
      <h4>화면 구성</h4>
      <p>왼쪽 사이드바에서 메뉴를 고르고, 오른쪽 위에서 내 계정과 기수를 확인합니다. 로그인한 역할(학생·강사·관리자)에 따라 보이는 메뉴가 다릅니다.</p>
    </li>
  </ol>
  <div class="two">
    <figure><img src="${img('login.png')}" alt="로그인 화면"><figcaption>로그인 화면</figcaption></figure>
    <figure><img src="${img('student/_tour.png')}" alt="이용 안내 투어"><figcaption>로그인 직후 뜨는 이용 안내 투어</figcaption></figure>
  </div>
</section>

${roleSections}

<section class="page" style="page-break-before: always">
  <h2>부록 · 자주 묻는 질문</h2>
  <dl class="faq">
    <dt>로그인이 안 됩니다.</dt>
    <dd>이메일 앞뒤 공백과 대소문자를 확인하세요. 계속 안 되면 계정 발급 여부와 비밀번호 재설정을 매니저에게 요청합니다.</dd>
    <dt>이용 안내 투어를 닫았는데 다시 보고 싶어요.</dt>
    <dd>마이페이지 → 「이용 안내 다시보기」를 누르면 처음부터 다시 볼 수 있습니다.</dd>
    <dt>출결 폼은 언제 내나요?</dt>
    <dd>지각·조퇴·외출·공가 같은 예외 출결이 있을 때 대시보드 오른쪽 위 「출결 폼」으로 제출합니다.</dd>
    <dt>기록실에 올린 기록은 언제 마일리지로 들어오나요?</dt>
    <dd>매니저가 승인하면 기수 규칙에 따라 자동으로 적립됩니다. 승인 상태는 기록실 목록에서 확인합니다.</dd>
    <dt>마일리지 상품을 구매 요청했는데 포인트가 그대로예요.</dt>
    <dd>구매 요청은 매니저가 승인할 때 차감됩니다. 반려되거나 취소하면 포인트는 변하지 않습니다.</dd>
    <dt>화면이 계속 로딩 중이에요.</dt>
    <dd>새로고침(F5)을 한 번 해 보세요. 그래도 같으면 로그아웃 후 다시 로그인하고, 해결되지 않으면 화면을 캡처해 매니저에게 알려 주세요.</dd>
  </dl>
</section>

</body>
</html>`;

fs.mkdirSync(outRoot, { recursive: true });
fs.mkdirSync(deliverRoot, { recursive: true });
const htmlPath = path.join(outRoot, `${baseName}.html`);
const pdfPath = path.join(deliverRoot, `${baseName}.pdf`);
fs.writeFileSync(htmlPath, html);

const browser = await chromium.launch();
try {
  const page = await browser.newPage();
  await page.goto(pathToFileURL(htmlPath).href, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  await page.pdf({
    path: pdfPath,
    format: 'A4',
    printBackground: true,
    preferCSSPageSize: true,
    displayHeaderFooter: true,
    headerTemplate: '<span></span>',
    footerTemplate:
      '<div style="width:100%;font-size:8px;color:#8a93a3;padding:0 14mm;display:flex;justify-content:space-between;font-family:sans-serif">' +
      '<span>PLAYDATA LMS 사용자 가이드</span><span><span class="pageNumber"></span> / <span class="totalPages"></span></span></div>',
  });
  console.log(pdfPath);
} finally {
  await browser.close();
}
