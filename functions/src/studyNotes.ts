import {createHash} from "crypto";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {ASSESSMENT_MODEL} from "./ai/assessmentPrompt";
import {db, ensureInitialized, fieldValue} from "./firebase";

const REGION = "asia-northeast3" as const;
const LEARNER_LEVEL = "수업을 일부 놓친 초보자";
const MAX_FILES = 8;
const MAX_CHARS = 18_000;
const GENERATING_LOCK_MS = 10 * 60 * 1000;
const ALLOWED_SUFFIXES = [".ipynb", ".py", ".md"];

const callOptions = {
  region: REGION,
  invoker: "public" as const,
  timeoutSeconds: 540,
  memory: "1GiB" as const,
};

type UserRole = "admin" | "instructor" | "student";
type ScopeType = "date" | "prefix" | "files";

interface CallerUser {
  uid: string;
  role: UserRole;
  cohortId?: string;
}

interface StudySource {
  id: string;
  title: string;
  repoUrl: string;
  branch: string;
  allowedPrefixes: string[];
  isActive: boolean;
}

interface RepoRef {
  owner: string;
  repo: string;
}

interface LearningFile {
  path: string;
  commit: string;
  content: string;
  truncated: boolean;
}

interface TooBroadResult {
  status: "too_broad";
  noteId: string;
  message: string;
  files: Array<{path: string; commit: string}>;
}

function asHttpsError(error: unknown): HttpsError {
  if (error instanceof HttpsError) return error;
  const message = error instanceof Error ? error.message : String(error);
  logger.error("studyNotes unhandled", error);
  return new HttpsError(
    "internal",
    message.slice(0, 240) || "수업 자료를 처리하지 못했습니다.",
  );
}

export const listStudySourceTree = onCall(callOptions, async (request) => {
  try {
    return await listStudySourceTreeHandler(request);
  } catch (error) {
    throw asHttpsError(error);
  }
});

async function listStudySourceTreeHandler(
  request: {auth?: {uid: string}; data: unknown},
) {
  ensureInitialized();
  const caller = await requireCaller(request.auth?.uid);
  const {cohortId, sourceId} = request.data as {
    cohortId?: string;
    sourceId?: string;
  };
  if (!cohortId || !sourceId) {
    throw new HttpsError("invalid-argument", "cohortId와 sourceId가 필요합니다.");
  }
  assertCohortAccess(caller, cohortId);
  const source = await loadActiveSource(cohortId, sourceId);
  const repo = parseRepoUrl(source.repoUrl);

  const [dates, tree] = await Promise.all([
    listRecentLessonDates(repo, source.branch, source.allowedPrefixes),
    listLearningEntries(repo, source.branch, source.allowedPrefixes),
  ]);

  return {
    dates,
    entries: tree.entries,
    truncated: tree.truncated,
  };
}

export const getStudyNote = onCall(callOptions, async (request) => {
  ensureInitialized();
  const caller = await requireCaller(request.auth?.uid);
  const data = request.data as {
    cohortId?: string;
    noteId?: string;
    sourceId?: string;
    scopeType?: string;
    scopeValue?: unknown;
  };
  if (!data.cohortId) {
    throw new HttpsError("invalid-argument", "cohortId가 필요합니다.");
  }
  assertCohortAccess(caller, data.cohortId);

  const noteId = data.noteId?.trim() ||
    (data.sourceId && data.scopeType ?
      buildNoteId(data.sourceId, data.scopeType, data.scopeValue) :
      "");
  if (!noteId) {
    throw new HttpsError("invalid-argument", "noteId 또는 sourceId+scope가 필요합니다.");
  }

  const snap = await noteRef(data.cohortId, noteId).get();
  if (!snap.exists) {
    return {noteId, status: "missing"};
  }
  return serializeNote(snap.id, snap.data() ?? {}, caller);
});

export const generateStudyNote = onCall(callOptions, async (request) => {
  ensureInitialized();
  const caller = await requireCaller(request.auth?.uid);
  const data = request.data as {
    cohortId?: string;
    sourceId?: string;
    scopeType?: string;
    scopeValue?: unknown;
  };
  if (!data.cohortId || !data.sourceId || !data.scopeType) {
    throw new HttpsError(
      "invalid-argument",
      "cohortId, sourceId, scopeType이 필요합니다.",
    );
  }
  assertCohortAccess(caller, data.cohortId);

  const source = await loadActiveSource(data.cohortId, data.sourceId);
  const scopeType = parseScopeType(data.scopeType);
  const scopeValue = normalizeScopeValue(scopeType, data.scopeValue);
  assertScopeAllowed(source, scopeType, scopeValue);

  const scopeKey = buildScopeKey(scopeType, scopeValue);
  const noteId = `${source.id}_${scopeKey}`;
  const ref = noteRef(data.cohortId, noteId);
  const claim = await db.runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    if (existing.exists) {
      const current = existing.data() ?? {};
      if (current.status === "ready") return {kind: "ready" as const, data: current};
      if (current.status === "generating" && !lockExpired(current)) {
        return {kind: "generating" as const, data: current};
      }
    }
    tx.set(ref, {
      sourceId: source.id,
      scopeType,
      scopeValue,
      scopeKey,
      status: "generating",
      generatingByUid: caller.uid,
      generatingStartedAt: fieldValue.serverTimestamp(),
      updatedAt: fieldValue.serverTimestamp(),
      errorMessage: fieldValue.delete(),
    }, {merge: true});
    return {kind: "start" as const};
  });

  if (claim.kind === "ready") {
    return serializeNote(noteId, claim.data, caller);
  }
  if (claim.kind === "generating") {
    if (claim.data.generatingByUid !== caller.uid && caller.role !== "admin") {
      return {
        noteId,
        status: "generating",
        message: "다른 학생이 이 범위를 정리하는 중입니다.",
      };
    }
    return {
      noteId,
      status: "generating",
      message: "이미 정리 중입니다. 잠시 후 다시 열어 주세요.",
    };
  }

  try {
    const repo = parseRepoUrl(source.repoUrl);
    const collected = await collectFiles(repo, source, scopeType, scopeValue);
    if ("tooBroad" in collected) {
      await ref.delete().catch(() => undefined);
      const result: TooBroadResult = {
        status: "too_broad",
        noteId,
        message: "파일을 선택하세요. 한 번에 최대 8개까지 정리할 수 있습니다.",
        files: collected.files,
      };
      return result;
    }
    if (collected.files.length === 0) {
      throw new HttpsError(
        "not-found",
        "이 범위에서 분석 가능한 .ipynb/.py/.md 파일이 없습니다.",
      );
    }

    const materials = await loadFileContents(repo, collected.files);
    const summaries = await analyzeFiles(materials);
    let report = await compileReport({
      scopeType,
      scopeValue,
      commits: collected.commits,
      summaries,
    });
    const review = await reviewReport(summaries, report);
    if (!review.passed) {
      report = await reviseReport(report, review.feedback);
    }
    const reviewMarkdown = await createReviewMaterial(report);
    const now = fieldValue.serverTimestamp();
    await ref.set({
      sourceId: source.id,
      scopeType,
      scopeValue,
      scopeKey,
      status: "ready",
      commits: collected.commits,
      files: collected.files,
      reportMarkdown: report,
      reviewMarkdown,
      errorMessage: fieldValue.delete(),
      generatedAt: now,
      updatedAt: now,
      generatingByUid: fieldValue.delete(),
      generatingStartedAt: fieldValue.delete(),
    }, {merge: true});

    return {
      noteId,
      status: "ready",
      reportMarkdown: report,
      reviewMarkdown,
    };
  } catch (error) {
    const message = error instanceof HttpsError ?
      error.message :
      error instanceof Error ? error.message : String(error);
    logger.error("generateStudyNote failed", {noteId, message});
    await ref.set({
      status: "failed",
      errorMessage: message.slice(0, 500),
      updatedAt: fieldValue.serverTimestamp(),
      generatingByUid: fieldValue.delete(),
      generatingStartedAt: fieldValue.delete(),
    }, {merge: true});
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", message.slice(0, 240));
  }
});

async function requireCaller(uid: string | undefined): Promise<CallerUser> {
  if (!uid) {
    throw new HttpsError("unauthenticated", "인증이 필요합니다.");
  }
  const snap = await db.collection("users").doc(uid).get();
  if (!snap.exists) {
    throw new HttpsError("permission-denied", "사용자 정보를 찾을 수 없습니다.");
  }
  const data = snap.data() ?? {};
  if (data.isActive === false) {
    throw new HttpsError("permission-denied", "비활성 계정입니다.");
  }
  return {
    uid,
    role: data.role as UserRole,
    cohortId: data.cohortId as string | undefined,
  };
}

function assertCohortAccess(caller: CallerUser, cohortId: string): void {
  if (caller.role === "admin") return;
  if (caller.cohortId === cohortId) return;
  throw new HttpsError("permission-denied", "해당 기수에 접근할 수 없습니다.");
}

async function loadActiveSource(
  cohortId: string,
  sourceId: string,
): Promise<StudySource> {
  const snap = await db
    .collection("cohorts")
    .doc(cohortId)
    .collection("studySources")
    .doc(sourceId)
    .get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "공부 소스를 찾을 수 없습니다.");
  }
  const data = snap.data() ?? {};
  if (data.isActive === false) {
    throw new HttpsError("failed-precondition", "비활성 수업 저장소입니다.");
  }
  const repoUrl = String(data.repoUrl ?? "");
  parseRepoUrl(repoUrl);
  return {
    id: snap.id,
    title: String(data.title ?? ""),
    repoUrl,
    branch: sanitizeBranch(String(data.branch ?? "main")),
    allowedPrefixes: normalizePrefixes(data.allowedPrefixes),
    isActive: true,
  };
}

function noteRef(cohortId: string, noteId: string) {
  return db
    .collection("cohorts")
    .doc(cohortId)
    .collection("studyNotes")
    .doc(noteId);
}

function parseScopeType(raw: string): ScopeType {
  if (raw === "date" || raw === "prefix" || raw === "files") return raw;
  throw new HttpsError("invalid-argument", "scopeType은 date, prefix, files만 가능합니다.");
}

function normalizeScopeValue(scopeType: ScopeType, raw: unknown): string | string[] {
  if (scopeType === "files") {
    if (!Array.isArray(raw) || raw.length === 0) {
      throw new HttpsError("invalid-argument", "파일을 1개 이상 선택하세요.");
    }
    if (raw.length > MAX_FILES) {
      throw new HttpsError(
        "invalid-argument",
        "한 번에 최대 8개 파일만 정리할 수 있습니다. 범위를 좁혀 주세요.",
      );
    }
    const paths = [...new Set(raw.map((item) => sanitizePath(String(item))))];
    if (paths.length === 0) {
      throw new HttpsError("invalid-argument", "유효한 파일 경로가 없습니다.");
    }
    return paths.sort();
  }
  const value = String(raw ?? "").trim();
  if (!value) {
    throw new HttpsError("invalid-argument", "범위를 선택하세요.");
  }
  if (scopeType === "date") {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
      throw new HttpsError("invalid-argument", "날짜는 YYYY-MM-DD 형식이어야 합니다.");
    }
    return value;
  }
  return sanitizePath(value).replace(/\/+$/, "");
}

function assertScopeAllowed(
  source: StudySource,
  scopeType: ScopeType,
  scopeValue: string | string[],
): void {
  if (scopeType === "prefix") {
    assertPrefixAllowed(source.allowedPrefixes, String(scopeValue));
    return;
  }
  if (scopeType === "files") {
    for (const path of scopeValue as string[]) {
      assertLearningFile(path);
      assertPrefixAllowed(source.allowedPrefixes, path);
    }
  }
}

function assertPrefixAllowed(allowed: string[], path: string): void {
  if (allowed.length === 0) return;
  const normalized = path.replace(/\/+$/, "");
  const ok = allowed.some((prefix) => {
    const base = prefix.replace(/\/+$/, "");
    return normalized === base || normalized.startsWith(`${base}/`);
  });
  if (!ok) {
    throw new HttpsError("invalid-argument", "허용된 폴더 밖의 경로는 정리할 수 없습니다.");
  }
}

function buildNoteId(
  sourceId: string,
  scopeTypeRaw: string,
  scopeValue: unknown,
): string {
  const scopeType = parseScopeType(scopeTypeRaw);
  const value = normalizeScopeValue(scopeType, scopeValue);
  return `${sanitizeDocId(sourceId)}_${buildScopeKey(scopeType, value)}`;
}

function buildScopeKey(scopeType: ScopeType, scopeValue: string | string[]): string {
  if (scopeType === "date") return String(scopeValue);
  if (scopeType === "prefix") {
    const safe = String(scopeValue)
      .replace(/[^A-Za-z0-9._-]+/g, "_")
      .replace(/^_+|_+$/g, "")
      .slice(0, 80);
    return `prefix_${safe || "root"}`;
  }
  const joined = (scopeValue as string[]).join("\n");
  const hash = createHash("sha1").update(joined).digest("hex").slice(0, 12);
  return `files_${hash}`;
}

function sanitizeDocId(value: string): string {
  return value.replace(/[/\s]/g, "_");
}

function lockExpired(data: Record<string, unknown>): boolean {
  const startedRaw = data.generatingStartedAt as {toDate?: () => Date} | undefined;
  const started = startedRaw?.toDate?.();
  if (!started) return true;
  return Date.now() - started.getTime() > GENERATING_LOCK_MS;
}

function serializeNote(
  noteId: string,
  data: Record<string, unknown>,
  caller: CallerUser,
) {
  const status = String(data.status ?? "missing");
  const base = {
    noteId,
    status,
    scopeType: data.scopeType ?? null,
    scopeValue: data.scopeValue ?? null,
    errorMessage: data.errorMessage ?? null,
  };
  if (status === "ready") {
    return {
      ...base,
      reportMarkdown: String(data.reportMarkdown ?? ""),
      reviewMarkdown: String(data.reviewMarkdown ?? ""),
      files: data.files ?? [],
    };
  }
  if (status === "generating") {
    const canSee = caller.role === "admin" || data.generatingByUid === caller.uid;
    if (!canSee) {
      return {
        noteId,
        status,
        message: "정리 중입니다.",
      };
    }
    return {
      ...base,
      message: "정리 중입니다.",
    };
  }
  return base;
}

function parseRepoUrl(repoUrl: string): RepoRef {
  let parsed: URL;
  try {
    parsed = new URL(repoUrl.trim());
  } catch {
    throw new HttpsError("invalid-argument", "GitHub 저장소 주소가 올바르지 않습니다.");
  }
  if (parsed.protocol !== "https:" || parsed.hostname !== "github.com") {
    throw new HttpsError("invalid-argument", "https://github.com/ 저장소만 허용됩니다.");
  }
  const parts = parsed.pathname.split("/").filter(Boolean);
  if (parts.length < 2) {
    throw new HttpsError("invalid-argument", "GitHub 저장소 주소가 올바르지 않습니다.");
  }
  const owner = parts[0];
  const repo = parts[1].replace(/\.git$/, "");
  if (!/^[\w.-]+$/.test(owner) || !/^[\w.-]+$/.test(repo)) {
    throw new HttpsError("invalid-argument", "GitHub 저장소 주소가 올바르지 않습니다.");
  }
  return {owner, repo};
}

function sanitizeBranch(branch: string): string {
  const value = branch.trim() || "main";
  if (value.includes("..") || value.includes("\\") || !/^[\w./-]+$/.test(value)) {
    throw new HttpsError("invalid-argument", "브랜치 이름이 올바르지 않습니다.");
  }
  return value;
}

function sanitizePath(path: string): string {
  const value = path.trim().replace(/\\/g, "/").replace(/^\/+/, "");
  if (!value || value.includes("..") || value.includes("\0")) {
    throw new HttpsError("invalid-argument", "파일 경로가 올바르지 않습니다.");
  }
  return value;
}

function normalizePrefixes(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((item) => String(item).trim().replace(/\\/g, "/").replace(/^\/+/, "").replace(/\/+$/, ""))
    .filter((item) => item.length > 0 && !item.includes(".."));
}

function isLearningFile(path: string): boolean {
  const lower = path.toLowerCase();
  return ALLOWED_SUFFIXES.some((suffix) => lower.endsWith(suffix));
}

function assertLearningFile(path: string): void {
  sanitizePath(path);
  if (!isLearningFile(path)) {
    throw new HttpsError("invalid-argument", "분석 가능한 파일은 .ipynb, .py, .md 뿐입니다.");
  }
}

function pathAllowed(path: string, prefixes: string[]): boolean {
  if (prefixes.length === 0) return true;
  return prefixes.some((prefix) => {
    const base = prefix.replace(/\/+$/, "");
    return path === base || path.startsWith(`${base}/`);
  });
}

async function githubFetch(path: string, accept = "application/vnd.github+json"): Promise<Response> {
  const headers: Record<string, string> = {
    Accept: accept,
    "User-Agent": "playdata-lms",
    "X-GitHub-Api-Version": "2022-11-28",
  };
  const token = process.env.GITHUB_TOKEN?.trim();
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(`https://api.github.com${path}`, {headers});
  if (response.status === 401 || response.status === 403 || response.status === 404) {
    throw new HttpsError(
      "failed-precondition",
      `GitHub 저장소를 읽지 못했습니다 (${response.status}). 주소·권한·토큰을 확인하세요.`,
    );
  }
  if (!response.ok) {
    const body = await response.text();
    logger.error("GitHub API error", {path, status: response.status, body: body.slice(0, 300)});
    throw new HttpsError("internal", `GitHub API 오류 (${response.status})`);
  }
  return response;
}

function seoulDateKey(iso: string): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Seoul",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(iso));
}

function nextDateKey(date: string): string {
  const [year, month, day] = date.split("-").map(Number);
  const utc = new Date(Date.UTC(year, month - 1, day));
  utc.setUTCDate(utc.getUTCDate() + 1);
  return utc.toISOString().slice(0, 10);
}

async function listRecentLessonDates(
  repo: RepoRef,
  branch: string,
  prefixes: string[],
): Promise<string[]> {
  const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const response = await githubFetch(
    `/repos/${repo.owner}/${repo.repo}/commits?sha=${encodeURIComponent(branch)}` +
      `&since=${encodeURIComponent(since)}&per_page=100`,
  );
  const commits = await response.json() as Array<{
    sha?: string;
    commit?: {author?: {date?: string}};
  }>;
  const dates = new Set<string>();
  for (const commit of commits.slice(0, 40)) {
    const date = commit.commit?.author?.date;
    const sha = commit.sha;
    if (!date || !sha) continue;
    const detailRes = await githubFetch(
      `/repos/${repo.owner}/${repo.repo}/commits/${sha}`,
    );
    const detail = await detailRes.json() as {
      files?: Array<{filename?: string}>;
    };
    const matches = (detail.files ?? []).some((file) => {
      const path = String(file.filename ?? "");
      return isLearningFile(path) && pathAllowed(path, prefixes);
    });
    if (matches) dates.add(seoulDateKey(date));
  }
  return [...dates].sort().reverse();
}

async function listLearningEntries(
  repo: RepoRef,
  branch: string,
  prefixes: string[],
): Promise<{entries: Array<{path: string; type: "blob"}>; truncated: boolean}> {
  const branchRes = await githubFetch(
    `/repos/${repo.owner}/${repo.repo}/branches/${encodeURIComponent(branch)}`,
  );
  const branchJson = await branchRes.json() as {commit?: {sha?: string; commit?: {tree?: {sha?: string}}}};
  const treeSha = branchJson.commit?.commit?.tree?.sha;
  if (!treeSha) {
    throw new HttpsError("not-found", "저장소 브랜치를 찾지 못했습니다.");
  }

  const treeRes = await githubFetch(
    `/repos/${repo.owner}/${repo.repo}/git/trees/${treeSha}?recursive=1`,
  );
  const treeJson = await treeRes.json() as {
    truncated?: boolean;
    tree?: Array<{path?: string; type?: string}>;
  };
  let truncated = treeJson.truncated === true;
  let blobs = (treeJson.tree ?? [])
    .filter((item) => item.type === "blob" && item.path && isLearningFile(item.path))
    .map((item) => item.path as string)
    .filter((path) => pathAllowed(path, prefixes));

  if (truncated && prefixes.length > 0) {
    blobs = [];
    truncated = false;
    for (const prefix of prefixes) {
      const listed = await listPrefixBlobs(repo, branch, prefix);
      blobs.push(...listed);
    }
  } else if (truncated) {
    blobs = blobs.slice(0, 400);
  }

  const unique = [...new Set(blobs)].sort();
  return {
    truncated,
    entries: unique.map((path) => ({path, type: "blob" as const})),
  };
}

async function listPrefixBlobs(
  repo: RepoRef,
  branch: string,
  prefix: string,
): Promise<string[]> {
  const collected: string[] = [];
  const queue = [prefix];
  while (queue.length > 0 && collected.length < 400) {
    const current = queue.shift()!;
    const response = await githubFetch(
      `/repos/${repo.owner}/${repo.repo}/contents/${encodePath(current)}?ref=${encodeURIComponent(branch)}`,
    );
    const payload = await response.json() as
      | Array<{type?: string; path?: string}>
      | {type?: string; path?: string};
    const items = Array.isArray(payload) ? payload : [payload];
    for (const item of items) {
      const path = String(item.path ?? "");
      if (!path || !pathAllowed(path, [prefix])) continue;
      if (item.type === "dir") queue.push(path);
      else if (item.type === "file" && isLearningFile(path)) collected.push(path);
    }
  }
  return collected;
}

function encodePath(path: string): string {
  return path.split("/").map(encodeURIComponent).join("/");
}

async function collectFiles(
  repo: RepoRef,
  source: StudySource,
  scopeType: ScopeType,
  scopeValue: string | string[],
): Promise<
  | {commits: string[]; files: Array<{path: string; commit: string}>}
  | {tooBroad: true; files: Array<{path: string; commit: string}>}
> {
  if (scopeType === "date") {
    return collectByDate(repo, source, String(scopeValue));
  }
  const head = await resolveHead(repo, source.branch);
  if (scopeType === "prefix") {
    const tree = await listLearningEntries(repo, source.branch, [String(scopeValue)]);
    const files = tree.entries.map((entry) => ({path: entry.path, commit: head}));
    if (files.length > MAX_FILES) return {tooBroad: true, files};
    return {commits: [head], files};
  }
  const files = (scopeValue as string[]).map((path) => ({path, commit: head}));
  return {commits: [head], files};
}

async function collectByDate(
  repo: RepoRef,
  source: StudySource,
  date: string,
): Promise<
  | {commits: string[]; files: Array<{path: string; commit: string}>}
  | {tooBroad: true; files: Array<{path: string; commit: string}>}
> {
  const since = `${date}T00:00:00+09:00`;
  const until = `${nextDateKey(date)}T00:00:00+09:00`;
  const response = await githubFetch(
    `/repos/${repo.owner}/${repo.repo}/commits?sha=${encodeURIComponent(source.branch)}` +
      `&since=${encodeURIComponent(since)}&until=${encodeURIComponent(until)}&per_page=50`,
  );
  const commits = await response.json() as Array<{sha?: string}>;
  const shas = commits.map((item) => item.sha).filter((sha): sha is string => Boolean(sha));
  const latest = new Map<string, string>();
  for (const sha of shas) {
    const detailRes = await githubFetch(`/repos/${repo.owner}/${repo.repo}/commits/${sha}`);
    const detail = await detailRes.json() as {
      files?: Array<{filename?: string; status?: string}>;
    };
    for (const file of detail.files ?? []) {
      const path = String(file.filename ?? "");
      if (!path || file.status === "removed") continue;
      if (!isLearningFile(path) || !pathAllowed(path, source.allowedPrefixes)) continue;
      if (!latest.has(path)) latest.set(path, sha);
    }
  }
  const files = [...latest.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([path, commit]) => ({path, commit}));
  if (files.length > MAX_FILES) return {tooBroad: true, files};
  return {commits: shas, files};
}

async function resolveHead(repo: RepoRef, branch: string): Promise<string> {
  const response = await githubFetch(
    `/repos/${repo.owner}/${repo.repo}/commits/${encodeURIComponent(branch)}`,
  );
  const json = await response.json() as {sha?: string};
  if (!json.sha) {
    throw new HttpsError("not-found", "저장소 HEAD를 찾지 못했습니다.");
  }
  return json.sha;
}

async function loadFileContents(
  repo: RepoRef,
  files: Array<{path: string; commit: string}>,
): Promise<LearningFile[]> {
  const loaded: LearningFile[] = [];
  for (const file of files) {
    const response = await githubFetch(
      `/repos/${repo.owner}/${repo.repo}/contents/${encodePath(file.path)}?ref=${file.commit}`,
      "application/vnd.github.raw",
    );
    const raw = await response.text();
    const text = file.path.toLowerCase().endsWith(".ipynb") ?
      notebookToText(raw) :
      raw;
    loaded.push({
      path: file.path,
      commit: file.commit.slice(0, 8),
      content: text.slice(0, MAX_CHARS),
      truncated: text.length > MAX_CHARS,
    });
  }
  return loaded;
}

function notebookToText(raw: string): string {
  let notebook: {cells?: Array<{cell_type?: string; source?: string | string[]}>};
  try {
    notebook = JSON.parse(raw) as {cells?: Array<{cell_type?: string; source?: string | string[]}>};
  } catch {
    return raw;
  }
  const sections: string[] = [];
  for (const [index, cell] of (notebook.cells ?? []).entries()) {
    const cellType = cell.cell_type ?? "unknown";
    if (cellType !== "markdown" && cellType !== "code") continue;
    const source = Array.isArray(cell.source) ? cell.source.join("") : String(cell.source ?? "");
    const text = source.trim();
    if (!text) continue;
    sections.push(`[${cellType.toUpperCase()} CELL ${index}]\n${text}`);
  }
  return sections.join("\n\n");
}

function resolveOpenaiApiKey(): string {
  const fromEnv = process.env.OPENAI_API_KEY?.trim();
  if (fromEnv) return fromEnv;
  throw new HttpsError(
    "failed-precondition",
    "OPENAI_API_KEY가 없습니다. 루트 .env에 키를 넣고 Functions를 배포하세요.",
  );
}

async function chat(system: string, user: string, json = false): Promise<string> {
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resolveOpenaiApiKey()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: ASSESSMENT_MODEL || "gpt-4o-mini",
      temperature: 0.2,
      max_tokens: json ? 800 : 4000,
      ...(json ? {response_format: {type: "json_object"}} : {}),
      messages: [
        {role: "system", content: system},
        {role: "user", content: user},
      ],
    }),
  });
  if (!response.ok) {
    const errText = await response.text();
    logger.error("OpenAI error", {status: response.status, errText: errText.slice(0, 400)});
    throw new HttpsError(
      "internal",
      `AI 수업 노트 생성 실패 (OpenAI ${response.status}). API 키·쿼터를 확인하세요.`,
    );
  }
  const jsonBody = await response.json() as {
    choices?: Array<{message?: {content?: string}}>;
  };
  return jsonBody.choices?.[0]?.message?.content ?? "";
}

async function analyzeFiles(files: LearningFile[]): Promise<Array<{path: string; commit: string; summary: string}>> {
  const summaries = [];
  for (const file of files) {
    const summary = await chat(
      "당신은 AI 부트캠프 수업자료를 분석하는 교육 전문가입니다. 학습자가 실제 코드를 다시 실행할 수 있도록 정확하고 구체적으로 설명하세요. 자료에 없는 내용을 수업 내용인 것처럼 만들지 마세요.",
      `학습자 수준: ${LEARNER_LEVEL}
파일: ${file.path}
잘림: ${file.truncated ? "있음" : "없음"}

다음 수업자료를 분석하세요.

${file.content}

아래 항목으로 정리하세요.
1. 이 파일의 학습 목표
2. 핵심 개념
3. 코드 실행 흐름
4. 중요한 클래스·함수·도구
5. 실행 전 필요한 환경·API·데이터
6. 예상 오류와 확인할 부분
7. 직접 해볼 작은 실습`,
    );
    summaries.push({path: file.path, commit: file.commit, summary});
  }
  return summaries;
}

async function compileReport(params: {
  scopeType: ScopeType;
  scopeValue: string | string[];
  commits: string[];
  summaries: Array<{path: string; commit: string; summary: string}>;
}): Promise<string> {
  const summaryText = params.summaries
    .map((item) => `### ${item.path}\n${item.summary}`)
    .join("\n\n");
  const scopeLabel = params.scopeType === "files" ?
    (params.scopeValue as string[]).join(", ") :
    String(params.scopeValue);
  return chat(
    "당신은 여러 수업 파일의 분석을 하나의 학습 노트로 편집합니다. 중복 설명은 합치고, 파일 사이의 선후 관계와 전체 실행 흐름을 분명히 보여주세요. 초보자가 복습할 수 있으면서 취업 포트폴리오 회고에도 활용할 수 있게 작성하세요.",
    `수업 범위: ${params.scopeType} ${scopeLabel}
학습자 수준: ${LEARNER_LEVEL}
변경 커밋: ${params.commits.map((commit) => commit.slice(0, 8)).join(", ") || "없음"}

파일별 분석:
${summaryText}

다음 구조의 한국어 Markdown 보고서를 작성하세요.

# 날짜별 수업 정리
## 오늘의 핵심 한 문장
## 전체 수업 흐름
## 파일별 학습 내용
## 핵심 코드와 개념
## 이전 학습과의 연결
## 실행 체크리스트
## 내가 직접 해볼 실습
## 포트폴리오 회고 포인트

변경된 파일 경로를 반드시 표시하세요. 자료에 없는 내용은 지어내지 마세요.`,
  );
}

async function reviewReport(
  summaries: Array<{path: string; summary: string}>,
  report: string,
): Promise<{passed: boolean; feedback: string}> {
  const summaryText = summaries
    .map((item) => `### ${item.path}\n${item.summary}`)
    .join("\n\n");
  const raw = await chat(
    "당신은 수업 요약 품질 검토자입니다. 원본 파일별 분석과 통합 보고서를 비교해 누락, 잘못된 연결, 실행 정보 부족을 검사하세요. JSON만 출력하세요.",
    `파일별 분석:
${summaryText}

통합 보고서:
${report}

다음 기준을 모두 만족하면 passed=true로 평가하세요.
- 모든 변경 파일이 언급됨
- 핵심 개념과 코드 흐름이 포함됨
- 필요한 API·데이터·환경이 포함됨
- 자료에 없는 사실을 단정하지 않음
- 학습자가 실행할 다음 단계가 명확함

{"passed": true, "feedback": "부족한 내용과 구체적인 보완 지시"}`,
    true,
  );
  try {
    const parsed = JSON.parse(raw) as {passed?: boolean; feedback?: string};
    return {
      passed: parsed.passed === true,
      feedback: String(parsed.feedback ?? ""),
    };
  } catch {
    return {passed: true, feedback: "검토 JSON을 읽지 못해 초안을 유지합니다."};
  }
}

async function reviseReport(report: string, feedback: string): Promise<string> {
  return chat(
    "품질 검토 의견을 반영해 수업 보고서를 정확하고 완결된 Markdown 문서로 수정하세요.",
    `기존 보고서:
${report}

검토 의견:
${feedback}

기존 보고서의 유용한 내용은 유지하고 지적받은 부분만 명확하게 보완하세요.`,
  );
}

async function createReviewMaterial(report: string): Promise<string> {
  return chat(
    "수업 보고서를 바탕으로 학습자가 스스로 이해도를 점검할 복습 자료를 만드세요.",
    `수업 보고서:
${report}

다음을 한국어 Markdown으로 작성하세요.
## 복습 문제
- 개념 확인 문제 3개
- 코드 흐름 문제 2개
- 응용 문제 1개

## 정답과 해설
각 문제의 정답과 짧은 해설을 작성하세요.`,
  );
}
