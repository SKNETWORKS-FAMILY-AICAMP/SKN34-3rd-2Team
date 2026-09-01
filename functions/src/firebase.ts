import * as admin from "firebase-admin";

function ensureInitialized(): void {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
}

export {admin};

let dbInstance: FirebaseFirestore.Firestore | undefined;
let authInstance: admin.auth.Auth | undefined;

/** 배포 분석 시 top-level init 타임아웃 방지 — 첫 사용 시 초기화 */
export const db = new Proxy({} as FirebaseFirestore.Firestore, {
  get(_target, prop, receiver) {
    ensureInitialized();
    if (!dbInstance) dbInstance = admin.firestore();
    const value = Reflect.get(dbInstance, prop, receiver);
    return typeof value === "function"
      ? (value as (...args: unknown[]) => unknown).bind(dbInstance)
      : value;
  },
});

export const auth = new Proxy({} as admin.auth.Auth, {
  get(_target, prop, receiver) {
    ensureInitialized();
    if (!authInstance) authInstance = admin.auth();
    const value = Reflect.get(authInstance, prop, receiver);
    return typeof value === "function"
      ? (value as (...args: unknown[]) => unknown).bind(authInstance)
      : value;
  },
});
