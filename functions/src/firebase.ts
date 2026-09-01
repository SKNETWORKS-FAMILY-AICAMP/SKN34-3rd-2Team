import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}

export {admin};
export const db = admin.firestore();
export const auth = admin.auth();

export const fieldValue = admin.firestore.FieldValue;

export function ensureInitialized(): void {
  // 하위 호환 — 이미 모듈 로드 시 초기화됨
}
