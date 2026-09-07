import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {db, fieldValue} from "./firebase";

const callOptions = {
  region: "asia-northeast3" as const,
  invoker: "public" as const,
};

type UserRole = "admin" | "instructor" | "student";

interface CallerUser {
  uid: string;
  role: UserRole;
  cohortId?: string;
  displayName?: string;
}

async function getCaller(uid: string): Promise<CallerUser> {
  const snap = await db.collection("users").doc(uid).get();
  if (!snap.exists) {
    throw new HttpsError("permission-denied", "사용자 정보를 찾을 수 없습니다.");
  }
  const data = snap.data()!;
  if (data.isActive === false) {
    throw new HttpsError("permission-denied", "비활성 계정입니다.");
  }
  return {
    uid,
    role: data.role as UserRole,
    cohortId: data.cohortId as string | undefined,
    displayName: data.displayName as string | undefined,
  };
}

function assertStaffOfCohort(caller: CallerUser, cohortId: string): void {
  if (caller.role === "admin") return;
  if (caller.role === "instructor" && caller.cohortId === cohortId) return;
  throw new HttpsError(
    "permission-denied",
    "강사 또는 관리자만 수행할 수 있습니다.",
  );
}

function assertCohortMember(caller: CallerUser, cohortId: string): void {
  if (caller.role === "admin") return;
  if (caller.cohortId === cohortId) return;
  throw new HttpsError("permission-denied", "해당 기수에 접근할 수 없습니다.");
}

function normalizeShortAnswer(value: unknown): string {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");
}

function gradeAnswer(
  question: Record<string, unknown>,
  rawValue: unknown,
): {autoScore: number; finalScore: number; isCorrect: boolean; value: unknown} {
  const points = Number(question.points ?? 0);
  const type = question.type as string;

  if (type === "mc") {
    const selected =
      typeof rawValue === "number"
        ? rawValue
        : Number.parseInt(String(rawValue ?? ""), 10);
    const correct = Number(question.correctIndex);
    const isCorrect =
      Number.isFinite(selected) && selected === correct;
    const score = isCorrect ? points : 0;
    return {
      value: Number.isFinite(selected) ? selected : rawValue,
      autoScore: score,
      finalScore: score,
      isCorrect,
    };
  }

  // short answer
  const normalized = normalizeShortAnswer(rawValue);
  const accepted: string[] = Array.isArray(question.acceptedAnswers)
    ? question.acceptedAnswers.map(normalizeShortAnswer)
    : [];
  const isCorrect =
    normalized.length > 0 && accepted.includes(normalized);
  const score = isCorrect ? points : 0;
  return {
    value: String(rawValue ?? "").trim(),
    autoScore: score,
    finalScore: score,
    isCorrect,
  };
}

/**
 * 학생용 — 정답 없는 문항 페이로드
 */
export const getAssessmentForTake = onCall(callOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "인증이 필요합니다.");
  }
  const caller = await getCaller(request.auth.uid);
  const {cohortId, assessmentId} = request.data as {
    cohortId?: string;
    assessmentId?: string;
  };
  if (!cohortId || !assessmentId) {
    throw new HttpsError("invalid-argument", "cohortId, assessmentId가 필요합니다.");
  }
  assertCohortMember(caller, cohortId);

  const assessmentRef = db
    .collection("cohorts")
    .doc(cohortId)
    .collection("assessments")
    .doc(assessmentId);
  const assessmentSnap = await assessmentRef.get();
  if (!assessmentSnap.exists) {
    throw new HttpsError("not-found", "평가를 찾을 수 없습니다.");
  }
  const assessment = assessmentSnap.data()!;
  if (!assessment.published && caller.role === "student") {
    throw new HttpsError("failed-precondition", "아직 공개되지 않은 평가입니다.");
  }

  const now = Date.now();
  const startAt = assessment.startAt?.toDate?.()?.getTime?.() ?? 0;
  const endAt = assessment.endAt?.toDate?.()?.getTime?.() ?? 0;
  if (caller.role === "student") {
    if (now < startAt) {
      throw new HttpsError("failed-precondition", "아직 응시 기간이 아닙니다.");
    }
    if (now > endAt) {
      throw new HttpsError("failed-precondition", "응시 기간이 종료되었습니다.");
    }
  }

  const submissionId = `${assessmentId}_${caller.uid}`;
  const submissionSnap = await db
    .collection("cohorts")
    .doc(cohortId)
    .collection("assessmentSubmissions")
    .doc(submissionId)
    .get();
  if (submissionSnap.exists && caller.role === "student") {
    throw new HttpsError(
      "already-exists",
      "이미 응시한 평가입니다. 결과만 확인할 수 있습니다.",
    );
  }

  const questionsSnap = await assessmentRef
    .collection("questions")
    .orderBy("order")
    .get();

  const questions = questionsSnap.docs.map((doc) => {
    const q = doc.data();
    const type = String(q.type ?? "mc");
    return {
      id: doc.id,
      order: Number(q.order ?? 0),
      type,
      prompt: String(q.prompt ?? ""),
      points: Number(q.points ?? 0),
      choices: type === "mc" || type === "multipleChoice"
        ? (Array.isArray(q.choices) ? q.choices.map(String) : [])
        : [],
    };
  });

  const toMillis = (v: unknown): number | null => {
    if (v && typeof v === "object" && "toDate" in (v as object)) {
      try {
        return (v as {toDate: () => Date}).toDate().getTime();
      } catch {
        return null;
      }
    }
    return null;
  };

  return {
    assessment: {
      id: assessmentId,
      title: assessment.title ?? "",
      tags: assessment.tags ?? [],
      questionCount: assessment.questionCount ?? questions.length,
      maxScore: assessment.maxScore ?? 0,
      startAtMs: toMillis(assessment.startAt),
      endAtMs: toMillis(assessment.endAt),
      thumbnailUrl: assessment.thumbnailUrl ?? null,
    },
    questions,
  };
});

/**
 * 학생 제출 + 서버 자동채점 (1회)
 */
export const submitAssessment = onCall(callOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "인증이 필요합니다.");
  }
  const caller = await getCaller(request.auth.uid);
  const {cohortId, assessmentId, answers} = request.data as {
    cohortId?: string;
    assessmentId?: string;
    answers?: Record<string, unknown>;
  };
  if (!cohortId || !assessmentId || !answers || typeof answers !== "object") {
    throw new HttpsError(
      "invalid-argument",
      "cohortId, assessmentId, answers가 필요합니다.",
    );
  }
  assertCohortMember(caller, cohortId);
  if (caller.role !== "student") {
    throw new HttpsError("permission-denied", "학생만 제출할 수 있습니다.");
  }

  const assessmentRef = db
    .collection("cohorts")
    .doc(cohortId)
    .collection("assessments")
    .doc(assessmentId);
  const submissionRef = db
    .collection("cohorts")
    .doc(cohortId)
    .collection("assessmentSubmissions")
    .doc(`${assessmentId}_${caller.uid}`);

  const assessmentSnap = await assessmentRef.get();
  if (!assessmentSnap.exists) {
    throw new HttpsError("not-found", "평가를 찾을 수 없습니다.");
  }
  const assessment = assessmentSnap.data()!;
  if (!assessment.published) {
    throw new HttpsError("failed-precondition", "공개되지 않은 평가입니다.");
  }
  const now = Date.now();
  const startAt = assessment.startAt?.toDate?.()?.getTime?.() ?? 0;
  const endAt = assessment.endAt?.toDate?.()?.getTime?.() ?? 0;
  if (now < startAt || now > endAt) {
    throw new HttpsError("failed-precondition", "응시 가능 기간이 아닙니다.");
  }

  const existing = await submissionRef.get();
  if (existing.exists) {
    throw new HttpsError("already-exists", "이미 응시한 평가입니다.");
  }

  const questionsSnap = await assessmentRef
    .collection("questions")
    .orderBy("order")
    .get();

  const graded: Record<
    string,
    {value: unknown; autoScore: number; finalScore: number; isCorrect: boolean}
  > = {};
  let autoTotal = 0;
  for (const doc of questionsSnap.docs) {
    const q = doc.data() as Record<string, unknown>;
    const gradedOne = gradeAnswer(q, answers[doc.id]);
    graded[doc.id] = gradedOne;
    autoTotal += gradedOne.finalScore;
  }

  try {
    await submissionRef.create({
      assessmentId,
      userId: caller.uid,
      userDisplayName: caller.displayName ?? "",
      answers: graded,
      autoTotalScore: autoTotal,
      totalScore: autoTotal,
      status: "submitted",
      submittedAt: fieldValue.serverTimestamp(),
      scoreAdjustments: [],
    });
  } catch (e: unknown) {
    const err = e as {code?: number | string};
    if (err.code === 6 || err.code === "already-exists") {
      throw new HttpsError("already-exists", "이미 응시한 평가입니다.");
    }
    throw e;
  }

  return {
    totalScore: autoTotal,
    autoTotalScore: autoTotal,
    submissionId: submissionRef.id,
  };
});

/**
 * 제출 후 리뷰 — 문항(정답 포함) + 내 제출 답안
 * 학생: 본인 제출이 있을 때만 / 스태프: submissionId로 조회 가능
 */
export const getAssessmentReview = onCall(callOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "인증이 필요합니다.");
  }
  const caller = await getCaller(request.auth.uid);
  const {cohortId, assessmentId, submissionId} = request.data as {
    cohortId?: string;
    assessmentId?: string;
    submissionId?: string;
  };
  if (!cohortId || !assessmentId) {
    throw new HttpsError(
      "invalid-argument",
      "cohortId, assessmentId가 필요합니다.",
    );
  }
  assertCohortMember(caller, cohortId);

  const isStaff =
    caller.role === "admin" ||
    (caller.role === "instructor" && caller.cohortId === cohortId);

  const resolvedSubmissionId =
    submissionId ||
    (isStaff ? undefined : `${assessmentId}_${caller.uid}`);

  if (!resolvedSubmissionId) {
    throw new HttpsError(
      "invalid-argument",
      "스태프는 submissionId가 필요합니다.",
    );
  }

  const submissionRef = db
    .collection("cohorts")
    .doc(cohortId)
    .collection("assessmentSubmissions")
    .doc(resolvedSubmissionId);
  const submissionSnap = await submissionRef.get();
  if (!submissionSnap.exists) {
    throw new HttpsError("not-found", "제출 기록이 없습니다.");
  }
  const submission = submissionSnap.data()!;
  if (!isStaff && submission.userId !== caller.uid) {
    throw new HttpsError("permission-denied", "본인 결과만 조회할 수 있습니다.");
  }
  if (submission.assessmentId !== assessmentId) {
    throw new HttpsError("invalid-argument", "평가 ID가 일치하지 않습니다.");
  }

  const questionsSnap = await db
    .collection("cohorts")
    .doc(cohortId)
    .collection("assessments")
    .doc(assessmentId)
    .collection("questions")
    .orderBy("order")
    .get();

  const questions = questionsSnap.docs.map((doc) => {
    const q = doc.data();
    return {
      id: doc.id,
      order: q.order ?? 0,
      type: q.type,
      prompt: q.prompt,
      points: q.points ?? 0,
      choices: q.choices ?? [],
      correctIndex: q.correctIndex ?? null,
      acceptedAnswers: q.acceptedAnswers ?? [],
      explanation: q.explanation ?? null,
    };
  });

  return {
    questions,
    submission: {
      id: submissionSnap.id,
      totalScore: submission.totalScore ?? 0,
      autoTotalScore: submission.autoTotalScore ?? 0,
      answers: submission.answers ?? {},
      userDisplayName: submission.userDisplayName ?? "",
    },
  };
});

/**
 * 강사 — 문항별 점수 수정 → 총점 재계산
 */
export const adjustAssessmentScores = onCall(callOptions, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "인증이 필요합니다.");
  }
  const caller = await getCaller(request.auth.uid);
  const {cohortId, submissionId, adjustments, note} = request.data as {
    cohortId?: string;
    submissionId?: string;
    adjustments?: Array<{questionId: string; finalScore: number}>;
    note?: string;
  };
  if (!cohortId || !submissionId || !Array.isArray(adjustments)) {
    throw new HttpsError(
      "invalid-argument",
      "cohortId, submissionId, adjustments가 필요합니다.",
    );
  }
  assertStaffOfCohort(caller, cohortId);

  const submissionRef = db
    .collection("cohorts")
    .doc(cohortId)
    .collection("assessmentSubmissions")
    .doc(submissionId);

  const submissionSnap = await submissionRef.get();
  if (!submissionSnap.exists) {
    throw new HttpsError("not-found", "제출을 찾을 수 없습니다.");
  }
  const submission = submissionSnap.data()!;
  const answers = {...(submission.answers ?? {})} as Record<
    string,
    {value: unknown; autoScore: number; finalScore: number; isCorrect: boolean}
  >;
  const history = [...(submission.scoreAdjustments ?? [])];

  for (const adj of adjustments) {
    const qid = adj.questionId;
    if (!qid || answers[qid] == null) continue;
    const previous = Number(answers[qid].finalScore ?? 0);
    const next = Math.max(0, Math.floor(Number(adj.finalScore)));
    if (previous === next) continue;
    answers[qid] = {
      ...answers[qid],
      finalScore: next,
      isCorrect: next > 0,
    };
    history.push({
      questionId: qid,
      previous,
      next,
      by: caller.uid,
      byName: caller.displayName ?? "",
      // Firestore: serverTimestamp()는 배열 요소 안에서 사용 불가
      at: new Date(),
      ...(note ? {note} : {}),
    });
  }

  const totalScore = Object.values(answers).reduce(
    (sum, a) => sum + Number(a.finalScore ?? 0),
    0,
  );

  await submissionRef.update({
    answers,
    totalScore,
    scoreAdjustments: history,
    updatedAt: fieldValue.serverTimestamp(),
  });

  return {totalScore, submissionId};
});

function resolveOpenaiApiKey(): string {
  // functions/.env → firebase deploy 시 Cloud Functions 환경변수로 주입됨
  const fromEnv = process.env.OPENAI_API_KEY?.trim();
  if (fromEnv) return fromEnv;

  throw new HttpsError(
    "failed-precondition",
    "OPENAI_API_KEY가 없습니다. functions/.env 에 OPENAI_API_KEY=... 를 넣고 " +
      "firebase deploy --only functions 로 배포하세요. (Flutter R만으로는 반영되지 않습니다)",
  );
}

/**
 * 커리큘럼 CSV 시트 구간 → AI 문제 초안 생성
 */
export const generateAssessmentQuestions = onCall(
  {
    ...callOptions,
    timeoutSeconds: 300,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "인증이 필요합니다.");
    }
    const caller = await getCaller(request.auth.uid);
    const {
      cohortId,
      sheetId,
      dayFrom,
      dayTo,
      mcCount = 5,
      saCount = 3,
      subjectFilter,
    } = request.data as {
      cohortId?: string;
      sheetId?: string;
      dayFrom?: number;
      dayTo?: number;
      mcCount?: number;
      saCount?: number;
      subjectFilter?: string;
    };

    if (!cohortId || !sheetId) {
      throw new HttpsError("invalid-argument", "cohortId, sheetId가 필요합니다.");
    }
    assertStaffOfCohort(caller, cohortId);

    if (dayFrom == null || dayTo == null) {
      throw new HttpsError("invalid-argument", "dayFrom, dayTo가 필요합니다.");
    }

    const sheetSnap = await db
      .collection("cohorts")
      .doc(cohortId)
      .collection("curriculumSheets")
      .doc(sheetId)
      .get();
    if (!sheetSnap.exists) {
      throw new HttpsError("not-found", "커리큘럼 시트를 찾을 수 없습니다.");
    }
    const sheet = sheetSnap.data()!;
    const rows = (Array.isArray(sheet.rows) ? sheet.rows : []) as Array<
      Record<string, unknown>
    >;
    const from = Math.min(dayFrom, dayTo);
    const to = Math.max(dayFrom, dayTo);
    const filtered = rows.filter((r) => {
      const day = Number(r.dayIndex ?? 0);
      if (day < from || day > to) return false;
      if (subjectFilter && String(r.subject ?? "") !== subjectFilter) {
        return false;
      }
      return true;
    });

    if (filtered.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "선택한 일수 구간에 커리큘럼 행이 없습니다.",
      );
    }

    const corpus = filtered
      .map((r) => {
        const day = r.dayIndex ?? "?";
        const date = r.dateLabel ? ` (${r.dateLabel})` : "";
        const subject = r.subject ?? "";
        const topic = r.topic ?? "";
        const detail = r.detail ?? "";
        const extra =
          detail && String(detail) !== String(topic) ? ` | 세부: ${detail}` : "";
        return `- 일수 ${day}${date} | 교과목: ${subject} | 내용: ${topic}${extra}`;
      })
      .join("\n")
      .slice(0, 24000);

    const topicList = [
      ...new Set(
        filtered
          .map((r) => String(r.topic ?? "").trim())
          .filter((t) => t.length > 0),
      ),
    ].join(", ");
    const subjectList = [
      ...new Set(
        filtered
          .map((r) => String(r.subject ?? "").trim())
          .filter((t) => t.length > 0),
      ),
    ].join(", ");

    const apiKey = resolveOpenaiApiKey();

    const system = `당신은 코딩 부트캠프 성취도 평가 출제자입니다.
반드시 아래 규칙을 지키세요.

[범위 제한 — 최우선]
1. 제공된 커리큘럼 행의 "교과목"과 "내용"(및 "세부"가 있으면 세부)에만 근거해 출제합니다.
2. 커리큘럼에 없는 기술·라이브러리·심화 주제·다른 과목 문제는 절대 출제하지 마세요.
3. "내용"이 짧은 키워드(예: Python, Database)이면, 그 키워드의 입문·기초 개념만 내고 범위를 넓히지 마세요.
4. 객관식 오답( distractors )도 같은 교과목·내용 안에서만 만드세요. 다른 과목 지식을 끌어오지 마세요.
5. 각 문제는 커리큘럼의 특정 일수(sourceDay)와 내용(sourceTopic)에 연결되어야 합니다.
6. 여러 내용이 섞인 구간이면, 문항을 내용별로 고르게 분배하세요.

[형식]
응답은 JSON만 출력합니다:
{"questions":[{"type":"mc"|"sa","prompt":"...","points":4,"choices":["A","B","C","D"],"correctIndex":0,"acceptedAnswers":["정답1"],"explanation":"...","sourceDay":1,"sourceTopic":"Python"}]}
- 객관식(mc): choices 정확히 4개, correctIndex는 0~3
- 단답(sa): acceptedAnswers 1개 이상(동의어·대소문자 변형 가능)
- explanation에는 왜 이 교과목/내용에서 출제했는지 한 줄로 적으세요
- sourceDay, sourceTopic은 커리큘럼 행과 일치해야 합니다`;

    const userPrompt = `커리큘럼 시트: ${sheet.title ?? sheetId}
일수 구간: ${from} ~ ${to}
허용 교과목: ${subjectList || "(없음)"}
허용 내용(토픽): ${topicList || "(없음)"}
객관식 ${mcCount}문항, 단답 ${saCount}문항.

위 허용 교과목·내용 밖의 문제는 만들지 마세요.
각 문항의 sourceTopic은 아래 목록의 "내용" 중 하나여야 합니다.

커리큘럼 행:
${corpus}`;

    const openaiRes = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        temperature: 0.2,
        response_format: {type: "json_object"},
        messages: [
          {role: "system", content: system},
          {role: "user", content: userPrompt},
        ],
      }),
    });

    if (!openaiRes.ok) {
      const errText = await openaiRes.text();
      logger.error("OpenAI error", {status: openaiRes.status, errText});
      throw new HttpsError(
        "internal",
        `AI 문제 생성 실패 (${openaiRes.status}). OPENAI_API_KEY를 확인하세요.`,
      );
    }

    const openaiJson = (await openaiRes.json()) as {
      choices?: Array<{message?: {content?: string}}>;
    };
    const content = openaiJson.choices?.[0]?.message?.content ?? "{}";
    let parsed: {questions?: unknown[]};
    try {
      parsed = JSON.parse(content);
    } catch {
      throw new HttpsError("internal", "AI 응답을 파싱하지 못했습니다.");
    }

    const questions = (parsed.questions ?? []).map((raw, index) => {
      const q = raw as Record<string, unknown>;
      const type = q.type === "sa" ? "sa" : "mc";
      const sourceDay = q.sourceDay != null ? String(q.sourceDay) : "";
      const sourceTopic = q.sourceTopic ? String(q.sourceTopic) : "";
      const baseExplanation = q.explanation ? String(q.explanation) : "";
      const sourceTag = [sourceDay && `일수 ${sourceDay}`, sourceTopic]
        .filter(Boolean)
        .join(" · ");
      const explanation = [sourceTag, baseExplanation]
        .filter((s) => s.length > 0)
        .join(" — ") || null;
      return {
        id: `draft_${index}`,
        order: index,
        type,
        prompt: String(q.prompt ?? ""),
        points: Number(q.points ?? (type === "mc" ? 4 : 5)),
        choices: type === "mc"
          ? (Array.isArray(q.choices) ? q.choices.map(String) : [])
          : [],
        correctIndex: type === "mc" ? Number(q.correctIndex ?? 0) : null,
        acceptedAnswers: type === "sa"
          ? (Array.isArray(q.acceptedAnswers)
            ? q.acceptedAnswers.map(String)
            : [])
          : [],
        explanation,
      };
    });

    return {questions, rowCount: filtered.length};
  },
);
