import {defineSecret} from "firebase-functions/params";
import {onRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {admin, db} from "./firebase";
export const googleFormWebhookSecret = defineSecret("GOOGLE_FORM_WEBHOOK_SECRET");

interface WebhookPayload {
  cohortId?: string;
  taskId?: string;
  email?: string;
  responseId?: string;
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

async function findUserByEmail(email: string) {
  const normalized = normalizeEmail(email);

  const byPersonal = await db
    .collection("users")
    .where("personalEmail", "==", normalized)
    .limit(1)
    .get();
  if (!byPersonal.empty) return byPersonal.docs[0];

  const byLogin = await db
    .collection("users")
    .where("email", "==", normalized)
    .limit(1)
    .get();
  if (!byLogin.empty) return byLogin.docs[0];

  return null;
}

/**
 * Google Apps Script → Firebase
 * POST JSON: { cohortId, taskId, email, responseId? }
 * Header: X-Webhook-Secret
 *
 * email: 상담 시 등록한 personalEmail (Gmail) 우선 매칭
 */
export const googleFormWebhook = onRequest(
  {
    region: "asia-northeast3",
    secrets: [googleFormWebhookSecret],
    cors: false,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const secret = req.get("X-Webhook-Secret");
    if (!secret || secret !== googleFormWebhookSecret.value()) {
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    const body = req.body as WebhookPayload;
    const {cohortId, taskId, email, responseId} = body;

    if (!cohortId || !taskId || !email) {
      res.status(400).json({
        error: "cohortId, taskId, email are required",
      });
      return;
    }

    try {
      const taskRef = db
        .collection("cohorts")
        .doc(cohortId)
        .collection("formTasks")
        .doc(taskId);
      const taskDoc = await taskRef.get();
      if (!taskDoc.exists) {
        res.status(404).json({error: "Form task not found"});
        return;
      }

      const userDoc = await findUserByEmail(email);
      if (!userDoc) {
        logger.warn("Google form submit: user not found", {email, taskId});
        res.status(404).json({error: "User not found for email"});
        return;
      }

      const userId = userDoc.id;
      const userData = userDoc.data();
      const responseRef = taskRef.collection("responses").doc(userId);
      const existing = await responseRef.get();

      const batch = db.batch();
      batch.set(
        responseRef,
        {
          userId,
          userEmail: normalizeEmail(email),
          userDisplayName: userData?.displayName ?? "",
          taskId,
          cohortId,
          source: "google_form",
          googleResponseId: responseId ?? null,
          submittedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );

      if (!existing.exists) {
        batch.update(taskRef, {
          responseCount: admin.firestore.FieldValue.increment(1),
        });
      }

      await batch.commit();

      logger.info("Google form response recorded", {cohortId, taskId, userId});
      res.status(200).json({
        ok: true,
        userId,
        message: "Submission recorded",
      });
    } catch (error) {
      logger.error("Google form webhook failed", error);
      res.status(500).json({error: "Internal error"});
    }
  },
);
