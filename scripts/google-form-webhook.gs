/**
 * Google Forms → PLAYDATA LMS Webhook
 *
 * 1. WEBHOOK_SECRET = firebase functions:secrets:set GOOGLE_FORM_WEBHOOK_SECRET 에 넣은 값
 * 2. TASK_ID = LMS 관리자 → 설문 상세 화면에서 복사
 * 3. 트리거: onFormSubmit / 폼 제출 시
 * 4. 구글폼: 설정 → 이메일 주소 수집 ON
 */

const WEBHOOK_URL =
  'https://asia-northeast3-skn34-3rd-2team.cloudfunctions.net/googleFormWebhook';
const WEBHOOK_SECRET = 'asdfghjkl'; // ← Firebase Secret과 동일하게!
const COHORT_ID = 'cohort_34';
const TASK_ID = 'vFsOtY9w7Xx2vIVkeyLB';

function onFormSubmit(e) {
  const answers = collectAnswers(e);
  const email = extractEmail(e) || '';
  if (!email && !answers['이름']) {
    console.warn('이메일/이름을 찾을 수 없습니다. 이메일 수집을 켜거나 이름 문항을 확인하세요.');
    return;
  }

  if (WEBHOOK_SECRET === 'YOUR_SECRET_HERE') {
    console.error('WEBHOOK_SECRET을 Firebase Secret 값으로 바꿔주세요.');
    return;
  }

  const payload = {
    cohortId: COHORT_ID,
    taskId: TASK_ID,
    email: String(email).trim().toLowerCase(),
    responseId: e.response.getId(),
    answers: answers,
  };

  const response = UrlFetchApp.fetch(WEBHOOK_URL, {
    method: 'post',
    contentType: 'application/json',
    headers: { 'X-Webhook-Secret': WEBHOOK_SECRET },
    payload: JSON.stringify(payload),
    muteHttpExceptions: true,
  });

  const code = response.getResponseCode();
  const body = response.getContentText();
  console.log('Webhook', code, body, 'email:', payload.email);

  if (code !== 200) {
    console.error('LMS 연동 실패:', code, body);
  }
}

function collectAnswers(e) {
  const answers = {};
  const items = e.response.getItemResponses();
  for (var i = 0; i < items.length; i++) {
    const title = items[i].getItem().getTitle();
    const resp = items[i].getResponse();
    answers[title] = Array.isArray(resp) ? resp.join(', ') : String(resp);
  }
  return answers;
}

function extractEmail(e) {
  const respondent = e.response.getRespondentEmail();
  if (respondent) return respondent;

  const items = e.response.getItemResponses();
  for (var i = 0; i < items.length; i++) {
    const title = items[i].getItem().getTitle();
    if (title.includes('이메일') || title.toLowerCase().includes('email')) {
      return items[i].getResponse();
    }
  }
  return null;
}

/** 트리거 없이 수동 테스트 (최근 응답 1건) */
function testWebhookManual() {
  const form = FormApp.getActiveForm();
  const responses = form.getResponses();
  if (responses.length === 0) {
    console.log('응답이 없습니다. 폼을 먼저 제출하세요.');
    return;
  }
  onFormSubmit({ response: responses[responses.length - 1] });
}
