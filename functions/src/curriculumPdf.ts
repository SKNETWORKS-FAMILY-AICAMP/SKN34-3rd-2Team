import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {assertAdmin, parseCurriculumText} from "./curriculumPdfParser";

export interface ParsedCurriculumDay {
  dayNumber: number;
  classDate: string;
  subject: string;
  content: string;
}

const MAX_PDF_BYTES = 10 * 1024 * 1024;

/**
 * 관리자 전용 — 커리큘럼 PDF(스프레드시트 export) 파싱
 */
export const parseCurriculumPdf = onCall(
  {
    region: "asia-northeast3",
    timeoutSeconds: 120,
    memory: "512MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "인증이 필요합니다.");
    }
    await assertAdmin(request.auth.uid);

    const {pdfBase64} = request.data as {pdfBase64?: string};
    if (!pdfBase64 || typeof pdfBase64 !== "string") {
      throw new HttpsError("invalid-argument", "pdfBase64가 필요합니다.");
    }

    let buffer: Buffer;
    try {
      buffer = Buffer.from(pdfBase64, "base64");
    } catch {
      throw new HttpsError("invalid-argument", "PDF 데이터가 올바르지 않습니다.");
    }

    if (buffer.length === 0) {
      throw new HttpsError("invalid-argument", "빈 PDF 파일입니다.");
    }
    if (buffer.length > MAX_PDF_BYTES) {
      throw new HttpsError(
        "invalid-argument",
        "PDF는 10MB 이하만 파싱할 수 있습니다.",
      );
    }

    let text = "";
    try {
      const pdfParse = (await import("pdf-parse")).default;
      const parsed = await pdfParse(buffer);
      text = parsed.text ?? "";
    } catch {
      throw new HttpsError(
        "failed-precondition",
        "PDF 텍스트를 읽을 수 없습니다. 스프레드시트에서보낸 PDF인지 확인하세요.",
      );
    }

    const days = parseCurriculumText(text);
    if (days.length === 0) {
      logger.warn("parseCurriculumPdf: no rows matched", {
        textLength: text.length,
        preview: text.slice(0, 800).replace(/\s+/g, " "),
        lineCount: text.split("\n").length,
      });
      throw new HttpsError(
        "failed-precondition",
        "커리큘럼 표를 찾지 못했습니다. PDF 양식(수업일자·일수·교과목·내용)을 확인하세요.",
      );
    }

    return {
      days,
      parsedCount: days.length,
      textLength: text.length,
    };
  },
);
