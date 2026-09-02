import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {Timestamp} from "firebase-admin/firestore";

import {db, fieldValue} from "./firebase";

const REGION = "asia-northeast3";
const KST = "Asia/Seoul";

const DEFAULT_CATEGORY_LIMITS: Record<string, number> = {
  gifticon: 200000,
  book: 100000,
  onlineCourse: 200000,
};

const DEFAULT_ACCRUAL_RULES: Record<string, number> = {
  certification: 5000,
  study: 3000,
  blog: 2000,
};

const LIMIT_STATUSES = ["pending", "approved", "modify_requested"];

interface CartItem {
  productId: string;
  productName: string;
  category: string;
  pricingType: string;
  unitPrice: number;
  quantity: number;
  purchaseLink?: string;
  subtotal?: number;
}

interface CategoryUsage {
  approved: number;
  pending: number;
  modifyRequested: number;
}

async function assertAdmin(uid: string): Promise<void> {
  const doc = await db.collection("users").doc(uid).get();
  if (!doc.exists || doc.data()?.role !== "admin") {
    throw new HttpsError("permission-denied", "관리자만 이 작업을 수행할 수 있습니다.");
  }
}

async function assertActiveUser(uid: string): Promise<FirebaseFirestore.DocumentData> {
  const doc = await db.collection("users").doc(uid).get();
  if (!doc.exists || doc.data()?.isActive !== true) {
    throw new HttpsError("permission-denied", "활성 사용자만 이 작업을 수행할 수 있습니다.");
  }
  return doc.data()!;
}

async function getMileageSettings(cohortId: string): Promise<{
  categoryLimits: Record<string, number>;
  accrualRules: Record<string, number>;
}> {
  const doc = await db
    .collection("cohorts")
    .doc(cohortId)
    .collection("mileageSettings")
    .doc("config")
    .get();

  const data = doc.data() ?? {};
  return {
    categoryLimits: {
      ...DEFAULT_CATEGORY_LIMITS,
      ...(data.categoryLimits as Record<string, number> | undefined),
    },
    accrualRules: {
      ...DEFAULT_ACCRUAL_RULES,
      ...(data.accrualRules as Record<string, number> | undefined),
    },
  };
}

function initCategoryUsage(): Record<string, CategoryUsage> {
  return {
    gifticon: {approved: 0, pending: 0, modifyRequested: 0},
    book: {approved: 0, pending: 0, modifyRequested: 0},
    onlineCourse: {approved: 0, pending: 0, modifyRequested: 0},
  };
}

function addToUsage(
  usage: Record<string, CategoryUsage>,
  category: string,
  amount: number,
  status: string,
): void {
  if (!usage[category]) return;
  const u = usage[category];
  switch (status) {
  case "approved":
    u.approved += amount;
    break;
  case "pending":
    u.pending += amount;
    break;
  case "modify_requested":
    u.modifyRequested += amount;
    break;
  default:
    break;
  }
}

function usageTotal(u: CategoryUsage): number {
  return u.approved + u.pending + u.modifyRequested;
}

async function computeUserCategoryUsage(
  cohortId: string,
  userId: string,
  excludeRequestId?: string,
): Promise<Record<string, CategoryUsage>> {
  const usage = initCategoryUsage();
  const snap = await db
    .collection("cohorts")
    .doc(cohortId)
    .collection("purchaseRequests")
    .where("userId", "==", userId)
    .get();

  for (const doc of snap.docs) {
    if (excludeRequestId && doc.id === excludeRequestId) continue;
    const data = doc.data();
    const status = data.status as string;
    if (!LIMIT_STATUSES.includes(status)) continue;
    const items = (data.items as CartItem[]) ?? [];
    for (const item of items) {
      const amount = item.subtotal ?? item.unitPrice * (item.quantity ?? 1);
      addToUsage(usage, item.category, amount, status);
    }
  }
  return usage;
}

function validateCategoryLimits(
  usage: Record<string, CategoryUsage>,
  newItems: CartItem[],
  limits: Record<string, number>,
): void {
  const added: Record<string, number> = {};
  for (const item of newItems) {
    const amount = item.subtotal ?? item.unitPrice * (item.quantity ?? 1);
    added[item.category] = (added[item.category] ?? 0) + amount;
  }

  for (const [category, addAmount] of Object.entries(added)) {
    const limit = limits[category] ?? 0;
    const current = usage[category] ?? {approved: 0, pending: 0, modifyRequested: 0};
    if (usageTotal(current) + addAmount > limit) {
      throw new HttpsError(
        "failed-precondition",
        `${category} 카테고리 한도를 초과합니다. (한도: ${limit.toLocaleString()}M)`,
      );
    }
  }
}

function normalizeCartItems(items: CartItem[]): CartItem[] {
  return items.map((item) => ({
    ...item,
    quantity: item.quantity ?? 1,
    subtotal: item.subtotal ?? item.unitPrice * (item.quantity ?? 1),
  }));
}

/**
 * 학생 — 장바구니 → 구매 요청 제출
 */
export const submitPurchaseRequest = onCall({region: REGION}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "인증이 필요합니다.");
  }

  const uid = request.auth.uid;
  const userData = await assertActiveUser(uid);
  const {cohortId, studentNote} = request.data as {
    cohortId?: string;
    studentNote?: string;
  };

  if (!cohortId) {
    throw new HttpsError("invalid-argument", "cohortId는 필수입니다.");
  }
  if (userData.cohortId !== cohortId) {
    throw new HttpsError("permission-denied", "해당 기수 소속이 아닙니다.");
  }

  const cartRef = db
    .collection("cohorts")
    .doc(cohortId)
    .collection("mileageCart")
    .doc(uid);
  const cartDoc = await cartRef.get();
  const rawItems = (cartDoc.data()?.items as CartItem[]) ?? [];

  if (rawItems.length === 0) {
    throw new HttpsError("failed-precondition", "장바구니가 비어 있습니다.");
  }

  const items = normalizeCartItems(rawItems);
  const totalAmount = items.reduce((sum, i) => sum + (i.subtotal ?? 0), 0);
  if (totalAmount <= 0) {
    throw new HttpsError("invalid-argument", "유효하지 않은 요청 금액입니다.");
  }

  const settings = await getMileageSettings(cohortId);
  const usage = await computeUserCategoryUsage(cohortId, uid);
  validateCategoryLimits(usage, items, settings.categoryLimits);

  const requestRef = db
    .collection("cohorts")
    .doc(cohortId)
    .collection("purchaseRequests")
    .doc();

  const batch = db.batch();
  batch.set(requestRef, {
    userId: uid,
    userDisplayName: userData.displayName ?? "",
    items,
    totalAmount,
    status: "pending",
    studentNote: studentNote ?? null,
    managerMemo: null,
    managerPurchaseLink: null,
    processedAt: null,
    processedBy: null,
    processedByName: null,
    createdAt: fieldValue.serverTimestamp(),
    updatedAt: fieldValue.serverTimestamp(),
  });
  batch.set(cartRef, {
    items: [],
    updatedAt: fieldValue.serverTimestamp(),
  });

  await batch.commit();

  return {
    message: "구매 요청이 접수되었습니다.",
    requestId: requestRef.id,
  };
});

/**
 * 관리자 — 구매 요청 승인/반려/수정요청
 */
export const reviewPurchaseRequest = onCall({region: REGION}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "인증이 필요합니다.");
  }
  await assertAdmin(request.auth.uid);

  const adminDoc = await db.collection("users").doc(request.auth.uid).get();
  const adminName = adminDoc.data()?.displayName ?? "관리자";

  const {cohortId, requestId, status, managerMemo, managerPurchaseLink} =
    request.data as {
      cohortId?: string;
      requestId?: string;
      status?: "approved" | "rejected" | "modify_requested";
      managerMemo?: string;
      managerPurchaseLink?: string;
    };

  if (!cohortId || !requestId || !status) {
    throw new HttpsError("invalid-argument", "cohortId, requestId, status는 필수입니다.");
  }

  const reqRef = db
    .collection("cohorts")
    .doc(cohortId)
    .collection("purchaseRequests")
    .doc(requestId);

  const reqDoc = await reqRef.get();
  if (!reqDoc.exists) {
    throw new HttpsError("not-found", "구매 요청을 찾을 수 없습니다.");
  }

  const reqData = reqDoc.data()!;
  const currentStatus = reqData.status as string;
  if (!["pending", "modify_requested"].includes(currentStatus)) {
    throw new HttpsError(
      "failed-precondition",
      "대기 또는 수정 요청 상태의 건만 처리할 수 있습니다.",
    );
  }

  const userId = reqData.userId as string;
  const totalAmount = reqData.totalAmount as number;
  const items = (reqData.items as CartItem[]) ?? [];
  const productNames = items.map((i) => i.productName).join(", ");

  if (status === "approved") {
    const userRef = db.collection("users").doc(userId);
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      throw new HttpsError("not-found", "학생을 찾을 수 없습니다.");
    }

    const balance = (userDoc.data()?.mileageBalance as number) ?? 0;
    if (balance < totalAmount) {
      throw new HttpsError(
        "failed-precondition",
        `마일리지 잔액이 부족합니다. (잔액: ${balance.toLocaleString()}M, 필요: ${totalAmount.toLocaleString()}M)`,
      );
    }

    const settings = await getMileageSettings(cohortId);
    const usage = await computeUserCategoryUsage(cohortId, userId, requestId);
    validateCategoryLimits(usage, items, settings.categoryLimits);

    const batch = db.batch();

    batch.update(userRef, {
      mileageBalance: fieldValue.increment(-totalAmount),
      updatedAt: fieldValue.serverTimestamp(),
    });

    const txRef = db
      .collection("cohorts")
      .doc(cohortId)
      .collection("mileageTransactions")
      .doc();

    batch.set(txRef, {
      userId,
      amount: -totalAmount,
      reason: `${productNames} 구매 승인`,
      type: "redemption",
      relatedId: requestId,
      adjustedBy: request.auth.uid,
      createdAt: fieldValue.serverTimestamp(),
    });

    batch.update(reqRef, {
      status: "approved",
      managerMemo: managerMemo ?? null,
      managerPurchaseLink: managerPurchaseLink ?? null,
      processedAt: fieldValue.serverTimestamp(),
      processedBy: request.auth.uid,
      processedByName: adminName,
      updatedAt: fieldValue.serverTimestamp(),
    });

    await batch.commit();

    return {message: "구매 요청이 승인되었습니다.", txId: txRef.id};
  }

  await reqRef.update({
    status,
    managerMemo: managerMemo ?? null,
    managerPurchaseLink: managerPurchaseLink ?? reqData.managerPurchaseLink ?? null,
    processedAt: fieldValue.serverTimestamp(),
    processedBy: request.auth.uid,
    processedByName: adminName,
    updatedAt: fieldValue.serverTimestamp(),
  });

  const label =
    status === "rejected" ? "반려" : "수정 요청";
  return {message: `구매 요청이 ${label} 처리되었습니다.`};
});

/**
 * 학생 — 구매 요청 취소
 */
export const cancelPurchaseRequest = onCall({region: REGION}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "인증이 필요합니다.");
  }

  const uid = request.auth.uid;
  await assertActiveUser(uid);

  const {cohortId, requestId} = request.data as {
    cohortId?: string;
    requestId?: string;
  };

  if (!cohortId || !requestId) {
    throw new HttpsError("invalid-argument", "cohortId, requestId는 필수입니다.");
  }

  const reqRef = db
    .collection("cohorts")
    .doc(cohortId)
    .collection("purchaseRequests")
    .doc(requestId);

  const reqDoc = await reqRef.get();
  if (!reqDoc.exists) {
    throw new HttpsError("not-found", "구매 요청을 찾을 수 없습니다.");
  }

  const reqData = reqDoc.data()!;
  if (reqData.userId !== uid) {
    throw new HttpsError("permission-denied", "본인의 요청만 취소할 수 있습니다.");
  }

  const currentStatus = reqData.status as string;
  if (!["pending", "modify_requested"].includes(currentStatus)) {
    throw new HttpsError(
      "failed-precondition",
      "대기 또는 수정 요청 상태의 건만 취소할 수 있습니다.",
    );
  }

  await reqRef.update({
    status: "cancelled",
    updatedAt: fieldValue.serverTimestamp(),
  });

  return {message: "구매 요청이 취소되었습니다."};
});

/**
 * 기록실 승인 시 자동 마일리지 적립 (reviewSubmission에서 호출)
 */
export async function grantMileageForSubmission(
  cohortId: string,
  submissionId: string,
  submissionType: string,
  userId: string,
  submissionTitle: string,
  reviewedBy: string,
): Promise<number> {
  const settings = await getMileageSettings(cohortId);
  const amount = settings.accrualRules[submissionType] ?? 0;
  if (amount <= 0) return 0;

  const subRef = db
    .collection("cohorts")
    .doc(cohortId)
    .collection("submissions")
    .doc(submissionId);
  const userRef = db.collection("users").doc(userId);

  return db.runTransaction(async (tx) => {
    const subDoc = await tx.get(subRef);
    if (!subDoc.exists) return 0;
    if (subDoc.data()?.mileageGranted === true) return 0;

    const txRef = db
      .collection("cohorts")
      .doc(cohortId)
      .collection("mileageTransactions")
      .doc();

    tx.update(subRef, {
      mileageGranted: true,
      mileageAmount: amount,
    });

    tx.update(userRef, {
      mileageBalance: fieldValue.increment(amount),
      updatedAt: fieldValue.serverTimestamp(),
    });

    tx.set(txRef, {
      userId,
      amount,
      reason: `${submissionTitle} 승인 적립`,
      type: "accrual",
      relatedId: submissionId,
      adjustedBy: reviewedBy,
      createdAt: fieldValue.serverTimestamp(),
    });

    return amount;
  });
}

/**
 * 종강 + 14일 경과 마일리지 소멸 배치 (공통 로직)
 * @param asOf 기준일 — cohort.endDate + 14일 <= asOf 이면 소멸 대상
 */
export async function runExpireMileage(asOf: Date = new Date()): Promise<number> {
  const cutoff = new Date(asOf);
  cutoff.setDate(cutoff.getDate() - 14);
  cutoff.setHours(23, 59, 59, 999);

  const cohortsSnap = await db.collection("cohorts").get();
  let expiredCount = 0;

  for (const cohortDoc of cohortsSnap.docs) {
    const endDateRaw = cohortDoc.data().endDate;
    if (!endDateRaw) continue;

    const endDate =
      endDateRaw instanceof Timestamp ?
        endDateRaw.toDate() :
        new Date(endDateRaw as string);

    if (endDate > cutoff) continue;

    const cohortId = cohortDoc.id;
    const usersSnap = await db
      .collection("users")
      .where("cohortId", "==", cohortId)
      .where("mileageBalance", ">", 0)
      .get();

    for (const userDoc of usersSnap.docs) {
      const balance = userDoc.data().mileageBalance as number;
      if (balance <= 0) continue;
      if (userDoc.data().mileageExpiredAt) continue;

      const batch = db.batch();
      batch.update(userDoc.ref, {
        mileageBalance: 0,
        mileageExpiredAt: fieldValue.serverTimestamp(),
        updatedAt: fieldValue.serverTimestamp(),
      });

      const txRef = db
        .collection("cohorts")
        .doc(cohortId)
        .collection("mileageTransactions")
        .doc();

      batch.set(txRef, {
        userId: userDoc.id,
        amount: -balance,
        reason: "종강 후 마일리지 소멸",
        type: "expiry",
        createdAt: fieldValue.serverTimestamp(),
      });

      await batch.commit();
      expiredCount++;
    }
  }

  return expiredCount;
}

/**
 * 종강 + 14일 경과 마일리지 소멸 (매일 03:00 KST)
 */
export const expireMileage = onSchedule(
  {
    schedule: "0 3 * * *",
    timeZone: KST,
    region: REGION,
  },
  async () => {
    const expiredCount = await runExpireMileage();
    logger.info(`expireMileage completed: ${expiredCount} users`);
  },
);

/**
 * 관리자 수동 소멸 배치 실행 (로컬·스테이징 테스트용)
 * mockDate: ISO 날짜 문자열 — 해당 날짜를 기준으로 소멸 판정
 */
export const expireMileageNow = onCall({region: REGION}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "인증이 필요합니다.");
  }
  await assertAdmin(request.auth.uid);

  const {mockDate} = request.data as {mockDate?: string};
  const asOf = mockDate ? new Date(mockDate) : new Date();
  if (mockDate && Number.isNaN(asOf.getTime())) {
    throw new HttpsError("invalid-argument", "mockDate 형식이 올바르지 않습니다.");
  }

  const expiredCount = await runExpireMileage(asOf);
  return {
    message: `${expiredCount}명의 마일리지가 소멸 처리되었습니다.`,
    expiredCount,
    asOf: asOf.toISOString(),
  };
});

export {DEFAULT_CATEGORY_LIMITS, DEFAULT_ACCRUAL_RULES, getMileageSettings};
