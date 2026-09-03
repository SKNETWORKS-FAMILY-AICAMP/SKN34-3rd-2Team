import {HttpsError} from "firebase-functions/v2/https";

import {db} from "./firebase";

export interface ParsedCurriculumDay {
  dayNumber: number;
  classDate: string;
  subject: string;
  content: string;
}

const KOREAN_DATE_RE =
  /(\d{4})\s*년\s*(\d{1,2})\s*월\s*(\d{1,2})\s*일(?:\s*[월화수목금토일]요일)?/;

const NUMERIC_DATE_RE =
  /(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})/;

const SHORT_DATE_RE =
  /(\d{1,2})\s*월\s*(\d{1,2})\s*일(?:\s*[월화수목금토일]요일)?/;

const DAY_ONLY_RE = /^(\d{1,3})$/;
const WEEKDAY_RE = /^[월화수목금토일]요일$/;

const HEADER_RE = /수업일자/;
const TITLE_RE = /SK네트웍스|커리큘럼|트랙|Family\s*AI|서울캠프/i;

export async function assertAdmin(uid: string): Promise<void> {
  const callerDoc = await db.collection("users").doc(uid).get();
  if (!callerDoc.exists || callerDoc.data()?.role !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "관리자만 이 작업을 수행할 수 있습니다.",
    );
  }
}

function pad2(n: number): string {
  return n.toString().padStart(2, "0");
}

function toIsoDate(y: number, m: number, d: number): string {
  return `${y}-${pad2(m)}-${pad2(d)}`;
}

function normalizeText(text: string): string {
  return text
    .replace(/\r/g, "")
    .replace(/\u00a0/g, " ")
    .replace(/[０-９]/g, (ch) =>
      String.fromCharCode(ch.charCodeAt(0) - 0xff10 + 0x30),
    )
    .replace(/[．。]/g, ".");
}

function normalizeLines(text: string): string[] {
  return normalizeText(text)
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);
}

function shouldSkipLine(line: string): boolean {
  if (!line.trim()) return true;
  if (HEADER_RE.test(line) && /일수/.test(line) && /교과목/.test(line)) {
    return true;
  }
  if (TITLE_RE.test(line) && !KOREAN_DATE_RE.test(line) && !NUMERIC_DATE_RE.test(line)) {
    return true;
  }
  if (/^page\s*\d+/i.test(line)) return true;
  return false;
}

interface DateParts {
  y: number;
  m: number;
  d: number;
}

function extractDate(line: string, defaultYear?: number): DateParts | null {
  const korean = line.match(KOREAN_DATE_RE);
  if (korean) {
    return {
      y: parseInt(korean[1], 10),
      m: parseInt(korean[2], 10),
      d: parseInt(korean[3], 10),
    };
  }

  const numeric = line.match(NUMERIC_DATE_RE);
  if (numeric) {
    return {
      y: parseInt(numeric[1], 10),
      m: parseInt(numeric[2], 10),
      d: parseInt(numeric[3], 10),
    };
  }

  const short = line.match(SHORT_DATE_RE);
  if (short && defaultYear) {
    return {
      y: defaultYear,
      m: parseInt(short[1], 10),
      d: parseInt(short[2], 10),
    };
  }

  return null;
}

function splitSubjectContent(rest: string): {subject: string; content: string} {
  const trimmed = rest.trim();
  if (!trimmed) return {subject: "", content: ""};

  const tabParts = trimmed.split(/\t+/).map((s) => s.trim()).filter(Boolean);
  if (tabParts.length >= 2) {
    return {
      subject: tabParts[0],
      content: tabParts.slice(1).join(" ").trim(),
    };
  }

  const multiSpace = trimmed
    .split(/\s{2,}/)
    .map((s) => s.trim())
    .filter(Boolean);
  if (multiSpace.length >= 2) {
    return {
      subject: multiSpace[0],
      content: multiSpace.slice(1).join(" ").trim(),
    };
  }

  return {subject: trimmed, content: ""};
}

function parseDayNumberToken(token: string): number | null {
  const n = parseInt(token.trim(), 10);
  if (!Number.isFinite(n) || n < 1 || n > 400) return null;
  return n;
}

function finalizeDay(day: ParsedCurriculumDay | null): ParsedCurriculumDay | null {
  if (!day || !day.classDate || day.dayNumber < 1) return null;
  return day;
}

/** 한 줄에 날짜+일수+교과목+내용이 모두 있는 형식 */
function parseInlineRows(lines: string[]): ParsedCurriculumDay[] {
  const days: ParsedCurriculumDay[] = [];
  let current: ParsedCurriculumDay | null = null;

  for (const line of lines) {
    if (shouldSkipLine(line)) continue;

    const korean = line.match(
      /(\d{4})\s*년\s*(\d{1,2})\s*월\s*(\d{1,2})\s*일(?:\s*[월화수목금토일]요일)?\s*(\d+)\s+(.+)/,
    );
    if (korean) {
      if (current) {
        const done = finalizeDay(current);
        if (done) days.push(done);
      }
      const {subject, content} = splitSubjectContent(korean[5]);
      current = {
        dayNumber: parseInt(korean[4], 10),
        classDate: toIsoDate(
          parseInt(korean[1], 10),
          parseInt(korean[2], 10),
          parseInt(korean[3], 10),
        ),
        subject,
        content,
      };
      continue;
    }

    const dayFirst = line.match(
      /^(\d{1,3})\s+(\d{4})\s*년\s*(\d{1,2})\s*월\s*(\d{1,2})\s*일(?:\s*[월화수목금토일]요일)?\s+(.+)/,
    );
    if (dayFirst) {
      if (current) {
        const done = finalizeDay(current);
        if (done) days.push(done);
      }
      const {subject, content} = splitSubjectContent(dayFirst[5]);
      current = {
        dayNumber: parseInt(dayFirst[1], 10),
        classDate: toIsoDate(
          parseInt(dayFirst[2], 10),
          parseInt(dayFirst[3], 10),
          parseInt(dayFirst[4], 10),
        ),
        subject,
        content,
      };
      continue;
    }

    if (current) {
      current.content = `${current.content} ${line}`.trim();
    }
  }

  if (current) {
    const done = finalizeDay(current);
    if (done) days.push(done);
  }

  return days;
}

/** 탭/다중공백으로 열이 구분된 한 줄 형식 */
function parseDelimitedRows(lines: string[]): ParsedCurriculumDay[] {
  const days: ParsedCurriculumDay[] = [];
  let defaultYear: number | undefined;

  for (const line of lines) {
    if (shouldSkipLine(line)) continue;

    const date = extractDate(line, defaultYear);
    if (!date) continue;
    defaultYear = date.y;

    const afterDate = line
      .replace(KOREAN_DATE_RE, "")
      .replace(NUMERIC_DATE_RE, "")
      .replace(SHORT_DATE_RE, "")
      .replace(/[월화수목금토일]요일/g, "")
      .trim();

    const parts = afterDate
      .split(/\t+|\s{2,}/)
      .map((s) => s.trim())
      .filter(Boolean);

    if (parts.length === 0) continue;

    let dayNumber = 0;
    let subject = "";
    let content = "";

    if (parts.length >= 3 && parseDayNumberToken(parts[0]) != null) {
      dayNumber = parseDayNumberToken(parts[0])!;
      subject = parts[1];
      content = parts.slice(2).join(" ");
    } else if (parts.length >= 2 && parseDayNumberToken(parts[0]) != null) {
      dayNumber = parseDayNumberToken(parts[0])!;
      const rest = splitSubjectContent(parts.slice(1).join(" "));
      subject = rest.subject;
      content = rest.content;
    } else if (parts.length >= 2) {
      dayNumber = parseDayNumberToken(parts[0]) ?? days.length + 1;
      subject = parts.length >= 3 ? parts[1] : parts[0];
      content = parts.length >= 3 ? parts.slice(2).join(" ") : parts[1] ?? "";
    } else {
      continue;
    }

    days.push({
      dayNumber,
      classDate: toIsoDate(date.y, date.m, date.d),
      subject,
      content,
    });
  }

  return days;
}

function mergeFragmentedDateLines(lines: string[]): string[] {
  const result: string[] = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];

    if (
      /^\d{4}\s*년$/.test(line) &&
      i + 2 < lines.length &&
      /월/.test(lines[i + 1]) &&
      /일/.test(lines[i + 2])
    ) {
      let merged = `${line} ${lines[i + 1]} ${lines[i + 2]}`;
      i += 3;
      if (i < lines.length && WEEKDAY_RE.test(lines[i])) {
        merged += ` ${lines[i]}`;
        i++;
      }
      result.push(merged);
      continue;
    }

    if (
      /^\d{4}\s*년\s+\d{1,2}\s*월$/.test(line) &&
      i + 1 < lines.length &&
      /일/.test(lines[i + 1])
    ) {
      let merged = `${line} ${lines[i + 1]}`;
      i += 2;
      if (i < lines.length && WEEKDAY_RE.test(lines[i])) {
        merged += ` ${lines[i]}`;
        i++;
      }
      result.push(merged);
      continue;
    }

    result.push(line);
    i++;
  }

  return result;
}

/**
 * 수업일자 / 일수 / 교과목 / 내용 이 각각 다른 줄
 */
function parseStackedRows(lines: string[]): ParsedCurriculumDay[] {
  const days: ParsedCurriculumDay[] = [];
  let defaultYear: number | undefined;
  let current: ParsedCurriculumDay | null = null;
  let phase: "date" | "day" | "subject" | "content" = "date";

  const flush = () => {
    const done = finalizeDay(current);
    if (done) days.push(done);
    current = null;
    phase = "date";
  };

  for (const rawLine of lines) {
    if (shouldSkipLine(rawLine)) continue;
    if (WEEKDAY_RE.test(rawLine)) continue;

    const date = extractDate(rawLine, defaultYear);
    if (date) {
      flush();
      defaultYear = date.y;
      current = {
        dayNumber: 0,
        classDate: toIsoDate(date.y, date.m, date.d),
        subject: "",
        content: "",
      };
      phase = "day";

      const remainder = rawLine
        .replace(KOREAN_DATE_RE, "")
        .replace(NUMERIC_DATE_RE, "")
        .replace(SHORT_DATE_RE, "")
        .replace(/[월화수목금토일]요일/g, "")
        .trim();

      if (remainder) {
        const tokens = remainder
          .split(/\t+|\s{2,}/)
          .map((s) => s.trim())
          .filter(Boolean);
        if (tokens.length >= 1 && parseDayNumberToken(tokens[0]) != null) {
          current.dayNumber = parseDayNumberToken(tokens[0])!;
          phase = "subject";
          if (tokens.length >= 2) {
            const rest = splitSubjectContent(tokens.slice(1).join(" "));
            current.subject = rest.subject;
            current.content = rest.content;
            phase = rest.content ? "content" : "subject";
          }
        }
      }
      continue;
    }

    if (!current) continue;

    const dayOnly = rawLine.match(DAY_ONLY_RE);
    if (phase === "day" && dayOnly) {
      current.dayNumber = parseInt(dayOnly[1], 10);
      phase = "subject";
      continue;
    }

    if (phase === "subject") {
      current.subject = rawLine;
      phase = "content";
      continue;
    }

    if (phase === "content") {
      current.content = current.content
        ? `${current.content} ${rawLine}`.trim()
        : rawLine;
    }
  }

  flush();
  return days;
}

function dedupeDays(days: ParsedCurriculumDay[]): ParsedCurriculumDay[] {
  const byKey = new Map<string, ParsedCurriculumDay>();
  for (const day of days) {
    const key = `${day.classDate}:${day.dayNumber}`;
    const existing = byKey.get(key);
    if (!existing) {
      byKey.set(key, day);
      continue;
    }
    if (day.content.length > existing.content.length) {
      byKey.set(key, {
        ...existing,
        subject: day.subject || existing.subject,
        content: day.content,
      });
    }
  }
  return [...byKey.values()].sort((a, b) => a.dayNumber - b.dayNumber);
}

/**
 * 스프레드시트 PDF 텍스트 → 일수 행 파싱
 */
export function parseCurriculumText(text: string): ParsedCurriculumDay[] {
  const lines = mergeFragmentedDateLines(normalizeLines(text));
  if (lines.length === 0) return [];

  const strategies = [parseInlineRows, parseDelimitedRows, parseStackedRows];
  let best: ParsedCurriculumDay[] = [];

  for (const strategy of strategies) {
    const parsed = dedupeDays(strategy(lines));
    if (parsed.length > best.length) {
      best = parsed;
    }
  }

  return best;
}
