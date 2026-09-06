import {createHash} from "crypto";
import {onCall, HttpsError} from "firebase-functions/v2/https";

import {admin, db} from "./firebase";
import {COLLECTED_JOBS} from "./generated/collectedJobs";
import {CollectedJob, EvidenceState, FilterResult} from "./jobCoachTypes";
import {
  ROLE_HITS_FOR_FULL_SCORE,
  SKILL_POOL_FLOOR,
  WEIGHTS,
  canonicalSet,
  canonicalSkill,
  educationPasses,
  gradeOf,
  matchedTerms,
} from "./jobCoachScoring";

interface AnalyzeRequest {
  cohortId?: string;
  resumeId?: string;
  targetRoles?: unknown;
  preferredRegions?: unknown;
  preferredEmploymentTypes?: unknown;
  confirmedMissingSkills?: unknown;
  draftContent?: unknown;
}

interface ResumeProfile {
  skills: Set<string>;
  projectSkills: Set<string>;
  educationLevel: "대졸" | "미기재";
  careerYears: number;
  hasCareerEvidence: boolean;
  hasEducationEvidence: boolean;
  targetRoles: string[];
  preferredRegions: string[];
  preferredEmploymentTypes: string[];
  confirmedMissingSkills: Set<string>;
  /** 학력사항의 전공과 자격사항 이름. 전공·자격증 요건 판정에 쓴다. */
  majors: string[];
  certifications: string[];
}


// job_matching_bot/matching/ranking.py 의 ROLE_TERMS 와 같아야 한다.
const ROLE_TERMS: Record<string, string[]> = {
  "백엔드 개발자": ["백엔드", "backend", "fastapi", "django", "api", "전산", "시스템운영"],
  "AI 엔지니어": ["ai engineering", "ai", "인공지능", "머신러닝", "추천 시스템", "데이터"],
  "프론트엔드 개발자": ["프론트엔드", "frontend", "front-end", "react", "vue", "웹개발", "ui개발"],
  "데이터 엔지니어": ["데이터엔지니어", "데이터 엔지니어", "data engineer", "데이터", "etl", "spark", "빅데이터"],
  "임베디드 개발자": ["임베디드", "embedded", "펌웨어", "firmware", "rtos", "h/w"],
};

const LEARNING_CATALOG: Record<string, Record<string, string>> = {
  kubernetes: {
    provider: "Kubernetes 공식 문서",
    title: "Kubernetes Basics",
    url: "https://kubernetes.io/docs/tutorials/kubernetes-basics/",
    level: "입문",
    estimatedDuration: "2~3시간",
    lastCheckedAt: "TEST_FIXTURE",
  },
  redis: {
    provider: "Redis 공식 문서",
    title: "Redis Get started",
    url: "https://redis.io/docs/latest/get-started/",
    level: "입문",
    estimatedDuration: "1~2시간",
    lastCheckedAt: "TEST_FIXTURE",
  },
};

function stringList(value: unknown, fallback: string[], max = 20): string[] {
  if (!Array.isArray(value)) return fallback;
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, max);
}

function readMapList(value: unknown): Record<string, unknown>[] {
  if (!Array.isArray(value)) return [];
  return value.filter(
    (item): item is Record<string, unknown> => typeof item === "object" && item !== null,
  );
}

function splitSkills(value: unknown): string[] {
  if (typeof value !== "string") return [];
  return value.split(/[,/|·\n]+/).map((item) => item.trim()).filter(Boolean);
}

function parseDate(value: unknown): Date | null {
  if (typeof value !== "string" || !value.trim()) return null;
  const normalized = /^\d{4}-\d{2}$/.test(value) ? `${value}-01` : value;
  const date = new Date(normalized);
  return Number.isNaN(date.getTime()) ? null : date;
}

function estimateCareerYears(experience: Record<string, unknown>[]): number {
  let months = 0;
  const now = new Date();
  for (const item of experience) {
    const start = parseDate(item.startDate);
    const end = item.isCurrent === true ? now : parseDate(item.endDate);
    if (!start || !end || end < start) continue;
    months += Math.max(
      0,
      (end.getFullYear() - start.getFullYear()) * 12 + end.getMonth() - start.getMonth(),
    );
  }
  return Math.round((months / 12) * 10) / 10;
}

function buildResumeProfile(
  content: Record<string, unknown>,
  request: AnalyzeRequest,
): ResumeProfile {
  const techStack = readMapList(content.techStack)
    .map((item) => item.name)
    .filter((name): name is string => typeof name === "string" && Boolean(name.trim()));
  const projects = readMapList(content.projects);
  const projectSkills = projects.flatMap((item) => splitSkills(item.techStack));
  const education = readMapList(content.education);
  const experience = readMapList(content.experience);

  return {
    skills: canonicalSet(techStack),
    projectSkills: canonicalSet(projectSkills),
    educationLevel: education.length > 0 ? "대졸" : "미기재",
    careerYears: estimateCareerYears(experience),
    hasCareerEvidence: experience.length > 0,
    hasEducationEvidence: education.length > 0,
    targetRoles: stringList(request.targetRoles, []),
    preferredRegions: stringList(request.preferredRegions, []),
    preferredEmploymentTypes: stringList(request.preferredEmploymentTypes, []),
    confirmedMissingSkills: canonicalSet(stringList(request.confirmedMissingSkills, [])),
    majors: education
      .map((item) => item.major)
      .filter((major): major is string => typeof major === "string" && Boolean(major.trim()))
      .map((major) => major.trim()),
    certifications: readMapList(content.certifications)
      .map((item) => item.name)
      .filter((name): name is string => typeof name === "string" && Boolean(name.trim()))
      .map((name) => name.trim()),
  };
}

/** 공백·기호를 지우고 소문자로. qualifications.py / local_job_matcher.dart 와 같은 정규화. */
function normalizeTerm(text: string): string {
  return text.replace(/[\s\-_/·.()[\]]/g, "").toLowerCase();
}

/** 전공·자격증·병역. 맞으면 통과, 확인할 수 없으면 확인 필요. 탈락시키지 않는다. */
function qualificationChecks(
  job: CollectedJob,
  resume: ResumeProfile,
  passed: string[],
  unknown: string[],
): void {
  const requiredMajors = job.requiredMajors ?? [];
  const majorTerms = job.requiredMajorTerms ?? [];
  if (requiredMajors.length > 0) {
    const resumeMajors = resume.majors.map((m) => m.trim()).filter(Boolean);
    if (resumeMajors.length === 0) {
      unknown.push(`전공 확인 필요: ${requiredMajors.join(", ")}`);
    } else {
      const matched = resumeMajors.filter((m) =>
        majorTerms.some((t) => t.length > 0 && normalizeTerm(m).includes(t)),
      );
      if (matched.length > 0) passed.push(`전공 요건 충족: ${matched[0]}`);
      else {
        unknown.push(`전공 요건 미확인: 공고 ${requiredMajors.join(", ")} / 이력서 ${resumeMajors.join(", ")}`);
      }
    }
  }
  const resumeCerts = resume.certifications.filter((c) => c.trim()).map(normalizeTerm);
  for (const cert of job.requiredCertifications ?? []) {
    const key = normalizeTerm(cert);
    if (resumeCerts.some((c) => key.length > 0 && (c.includes(key) || key.includes(c)))) {
      passed.push(`자격증 요건 충족: ${cert}`);
    } else unknown.push(`자격증 확인 필요: ${cert}`);
  }
  if (job.militaryRequired) unknown.push("병역 조건 확인 필요 (병역필 또는 면제)");
}

const NATIONWIDE = "전국";

/** 공고 지역이 "전국"을 포함하면 어느 희망 지역이든 통과시킨다. hard_filter.py / local_job_matcher.dart 와 같은 규칙. */
function isNationwide(jobRegion: string): boolean {
  return jobRegion.includes(NATIONWIDE);
}

function hardFilter(job: CollectedJob, resume: ResumeProfile): FilterResult {
  const passed: string[] = [];
  const failed: string[] = [];
  const unknown: string[] = [];

  if (job.status !== "OPEN") failed.push(`공고 상태 ${job.status}`);
  else passed.push("공고 진행 중");

  // 본문이 이미지뿐이면 텍스트로 확인한 요구사항이 없다. 탈락이 아니라 확인 필요다.
  if (job.bodyIsImage) unknown.push("공고 상세가 이미지라 요구사항 미확인");

  if (job.careerType === "EXPERIENCED") {
    if (job.minCareerYears === null) {
      // "경력자"라고만 쓰고 연차가 없는 공고. 경력이 있으면 충족, 신입은 확인 필요.
      // hard_filter.py / local_job_matcher.dart 와 같은 규칙.
      if (resume.hasCareerEvidence && resume.careerYears >= 1) {
        passed.push("경력 조건 충족 (연차 미기재, 경력 보유)");
      } else unknown.push("경력 연수 미기재");
    } else if (!resume.hasCareerEvidence) unknown.push("이력서 경력 근거 미입력");
    else if (resume.careerYears < job.minCareerYears) {
      failed.push(`최소 경력 ${job.minCareerYears}년`);
    } else passed.push("경력 조건 충족");
  } else if (job.careerType === "UNKNOWN") unknown.push("경력 조건 미기재");
  else passed.push("경력 조건 충족");

  // 이력서에 학력을 아직 입력하지 않은 것과 요건을 못 채운 것은 다르다.
  if (job.education !== "학력무관" && !resume.hasEducationEvidence) {
    unknown.push("이력서 학력 근거 미입력");
  } else {
    const educationResult = educationPasses(resume.educationLevel, job.education);
    if (educationResult === true) passed.push("학력 조건 충족");
    else if (educationResult === false) failed.push(`필수 학력 ${job.education}`);
    else unknown.push("학력 조건 미기재");
  }

  qualificationChecks(job, resume, passed, unknown);

  if (resume.preferredRegions.length === 0) {
    unknown.push("희망 근무지역 미입력");
  } else if (isNationwide(job.region) || resume.preferredRegions.includes(NATIONWIDE)) {
    // 공고가 전국 근무이거나 사용자가 전국을 골랐으면 지역은 따지지 않는다.
    passed.push("전국 근무 가능 — 지역 조건 충족");
  } else if (resume.preferredRegions.some((region) => job.region.includes(region))) {
    passed.push("희망 근무지역 일치");
  } else failed.push(`희망지역 불일치: ${job.region}`);

  if (resume.preferredEmploymentTypes.length === 0) {
    unknown.push("희망 고용형태 미입력");
  } else if (job.employmentType === null) unknown.push("고용형태 미기재");
  else if (resume.preferredEmploymentTypes.includes(job.employmentType)) {
    passed.push("희망 고용형태 일치");
  } else failed.push(`희망 고용형태 불일치: ${job.employmentType}`);

  return {
    status: failed.length > 0 ? "FAIL" : unknown.length > 0 ? "CHECK_REQUIRED" : "PASS",
    passed,
    failed,
    unknown,
  };
}

/**
 * 공고가 언급한 기술. 표준 키 → 표시용 원문. 필수/우대/기술스택을 한 목록으로
 * 합치고 표기 변형은 하나로 센다. job_matching_bot/matching/ranking.py 의
 * declared_skills 와 같은 규칙이다.
 */
/** 공고가 언급한 기술의 출처. 필수 > 우대 > 태그 순으로 앞선 곳을 쓴다. ranking.py / local_job_matcher.dart 와 같은 규칙. */
function skillBuckets(job: CollectedJob): Map<string, string> {
  const buckets = new Map<string, string>();
  const sources: [string, string[]][] = [
    ["required", job.requiredSkills],
    ["preferred", job.preferredSkills],
    ["tag", job.techStack],
  ];
  for (const [bucket, values] of sources) {
    for (const value of values) {
      const key = canonicalSkill(value);
      if (!buckets.has(key)) buckets.set(key, bucket);
    }
  }
  return buckets;
}

function declaredSkills(job: CollectedJob): [Map<string, string>, string[]] {
  const pool = new Map<string, string>();
  const sources: string[] = [];
  const buckets: [string, string[]][] = [
    ["required_skills", job.requiredSkills],
    ["preferred_skills", job.preferredSkills],
    ["tech_stack", job.techStack],
  ];
  for (const [source, values] of buckets) {
    if (values.length > 0) sources.push(source);
    for (const value of values) {
      const key = canonicalSkill(value);
      if (!pool.has(key)) pool.set(key, value);
    }
  }
  return [pool, sources];
}

/** 겹치는 비율과, 겹친 기술의 공고 쪽 원문 표기. */
function skillScore(resumeKeys: Set<string>, pool: Map<string, string>): [number, string[]] {
  if (pool.size === 0) return [0, []];
  const matched = [...pool.entries()]
    .filter(([key]) => resumeKeys.has(key))
    .map(([, display]) => display)
    .sort();
  return [matched.length / Math.max(pool.size, SKILL_POOL_FLOOR), matched];
}

function roleScore(resume: ResumeProfile, job: CollectedJob): [number, string[]] {
  const text = `${job.title} ${job.description}`.toLowerCase();
  const terms = resume.targetRoles.flatMap((role) => ROLE_TERMS[role] ?? [role.toLowerCase()]);
  const hits = matchedTerms(text, terms);
  return [Math.min(1, hits.length / ROLE_HITS_FOR_FULL_SCORE), hits];
}

function rankJobs(resume: ResumeProfile): Record<string, unknown>[] {
  const ranked: Record<string, unknown>[] = [];
  for (const job of COLLECTED_JOBS) {
    const filter = hardFilter(job, resume);
    if (filter.status === "FAIL") continue;
    const [role, roleTerms] = roleScore(resume, job);
    // 필수/우대/기술스택을 한 목록으로 보고 겹침을 잰다. 필수/우대가 갈린
    // 공고가 거의 없어 따로 채점하면 그 몫이 0이 된다.
    const [pool, skillsSource] = declaredSkills(job);
    const [skills, matchedSkills] = skillScore(resume.skills, pool);
    // 프로젝트 경험은 공고가 언급한 기술 어디에 닿아도 근거가 된다.
    const [project, projectSkills] = skillScore(resume.projectSkills, pool);
    // 공고가 요구하지만 이력서 어디에도 근거가 없는 기술. 경험 없음 판단이 아니다.
    const unmatchedSkills = [...pool.entries()]
      .filter(([key]) => !resume.skills.has(key) && !resume.projectSkills.has(key))
      .map(([, value]) => value)
      .sort();
    const buckets = skillBuckets(job);
    const knownKeys = new Set([...resume.skills, ...resume.projectSkills]);
    const pick = (bucket: string, matched: boolean): string[] =>
      [...pool.entries()]
        .filter(([key]) => buckets.get(key) === bucket && knownKeys.has(key) === matched)
        .map(([, value]) => value)
        .sort();
    const conditions = filter.status === "PASS" ? 1 : 0.5;
    const score = Math.round(
      (role * WEIGHTS.role +
        skills * WEIGHTS.skills +
        project * WEIGHTS.project +
        conditions * WEIGHTS.conditions) *
        1000,
    ) / 10;
    ranked.push({
      jobId: job.jobId,
      source: job.source,
      sourceUrl: job.sourceUrl,
      company: job.company,
      title: job.title,
      bodyIsImage: job.bodyIsImage ?? false,
      region: job.region,
      employmentType: job.employmentType,
      careerType: job.careerType,
      minCareerYears: job.minCareerYears,
      education: job.education,
      requiredMajors: job.requiredMajors ?? [],
      requiredCertifications: job.requiredCertifications ?? [],
      militaryRequired: job.militaryRequired ?? false,
      recommendationScore: score,
      grade: gradeOf(score),
      hardFilter: filter,
      scoreDetail: {
        role,
        skills,
        skillsSource,
        skillsTotal: pool.size,
        project,
        conditions,
      },
      evidence: {
        roleTerms,
        matchedSkills,
        projectSkills,
        unmatchedSkills,
        matchedRequired: pick("required", true),
        matchedPreferred: pick("preferred", true),
        matchedTags: pick("tag", true),
        unmatchedRequired: pick("required", false),
        unmatchedPreferred: pick("preferred", false),
        unmatchedTags: pick("tag", false),
      },
    });
  }
  return ranked.sort(
    (left, right) =>
      (right.recommendationScore as number) - (left.recommendationScore as number),
  );
}

function analyzeSkills(job: CollectedJob, resume: ResumeProfile): Record<string, unknown> {
  const judgements: Record<string, unknown>[] = [];
  const resumeFeedback: string[] = [];
  const learningRecommendations: Record<string, string>[] = [];
  // REQUIRED/PREFERRED는 LLM이 본문에서 가른 것, DECLARED는 기업이 공고 등록
  // 때 고른 기술스택 태그다. 같은 기술이 여러 층에 있으면 더 구체적인 층 하나로만
  // 판정한다. job_matching_bot/coach/skill_gap.py 와 같은 규칙이다.
  const requirements: ["REQUIRED" | "PREFERRED" | "DECLARED", string[]][] = [
    ["REQUIRED", job.requiredSkills],
    ["PREFERRED", job.preferredSkills],
    ["DECLARED", job.techStack],
  ];
  const tierLabel = {REQUIRED: "REQUIRED", PREFERRED: "PREFERRED", DECLARED: "기술스택 태그"};
  const seen = new Set<string>();

  for (const [requirementType, skills] of requirements) {
    for (const skill of skills) {
      const key = canonicalSkill(skill);
      if (!key || seen.has(key)) continue;
      seen.add(key);
      let judgement: EvidenceState;
      let resumeEvidence: string[] = [];
      let confirmationQuestion: string | null = null;
      if (resume.skills.has(key)) {
        judgement = "EVIDENCED";
        resumeEvidence = [`기술스택: ${skill}`];
        if (resume.projectSkills.has(key)) resumeEvidence.push(`프로젝트 기술: ${skill}`);
        else {
          resumeFeedback.push(
            `${skill}: 기술스택에는 있으나 프로젝트에서 사용한 기능·역할·결과 근거를 보강하세요.`,
          );
        }
      } else if (resume.confirmedMissingSkills.has(key)) {
        judgement = "CONFIRMED_MISSING";
        resumeEvidence = [`사용자 확인: ${skill} 실사용 경험 없음`];
        const catalog = LEARNING_CATALOG[key];
        if (catalog) learningRecommendations.push({skill, ...catalog});
      } else {
        judgement = "NOT_EVIDENCED";
        confirmationQuestion = `이력서에서는 ${skill} 경험을 확인하지 못했습니다. 실제 사용 경험이 있나요?`;
      }
      judgements.push({
        criterion: skill,
        requirementType,
        judgement,
        resumeEvidence,
        jobEvidence: [`${tierLabel[requirementType]}: ${skill}`],
        confirmationQuestion,
        confidence: 1,
        method: "deterministic_poc_rule",
      });
    }
  }
  return {judgements, resumeFeedback, learningRecommendations};
}

function runJobCoach(resume: ResumeProfile): Record<string, unknown> {
  const hardFilterResults = COLLECTED_JOBS.map((job) => ({
    jobId: job.jobId,
    company: job.company,
    title: job.title,
    result: hardFilter(job, resume),
  }));
  const recommendations = rankJobs(resume);
  if (recommendations.length === 0) {
    return {
      testMode: true,
      recommendations: [],
      hardFilterResults,
      selectedJob: null,
      skillAnalysis: {judgements: [], resumeFeedback: [], learningRecommendations: []},
    };
  }
  const selectedId = recommendations[0].jobId as string;
  const selectedJob = COLLECTED_JOBS.find((job) => job.jobId === selectedId);
  if (!selectedJob) throw new HttpsError("internal", "선택된 테스트 공고를 찾지 못했습니다.");
  return {
    testMode: true,
    recommendationNotice: "IT 채용공고만 대상으로 하며, 추천 점수는 합격 확률이 아닌 POC 정렬 점수입니다.",
    hardFilterResults,
    recommendations,
    selectedJob,
    skillAnalysis: analyzeSkills(selectedJob, resume),
  };
}

/**
 * 맞춤 공고 추천 전에 반드시 채워야 하는 섹션.
 *
 * lib/features/resume/ai_coach/models/resume_readiness.dart 의
 * requiredSectionsForRecommendation 과 같은 목록이어야 한다.
 * 클라이언트에서만 막으면 Callable을 직접 호출해 우회할 수 있으므로
 * 서버에서도 같은 조건을 확인한다.
 */
const REQUIRED_SECTION_LABELS: Record<string, string> = {
  basicInfo: "기본정보",
  coreCompetencies: "핵심역량/강점",
  education: "학력사항",
  techStack: "기술스택",
  projects: "프로젝트 경험",
  selfIntroduction: "자기소개서",
};

/** 문자열 필드 중 하나라도 채워져 있으면 true. */
function hasText(value: unknown, fields: string[]): boolean {
  if (typeof value !== "object" || value === null) return false;
  const record = value as Record<string, unknown>;
  return fields.some(
    (field) => typeof record[field] === "string" && Boolean((record[field] as string).trim()),
  );
}

/** 목록 안에 내용이 있는 항목이 하나라도 있으면 true. */
function hasFilledItem(value: unknown, fields: string[]): boolean {
  return readMapList(value).some((item) => hasText(item, fields));
}

/** 섹션별로 실제 내용이 있는지 판정한다. */
function filledSections(content: Record<string, unknown>): Set<string> {
  const filled = new Set<string>();
  // 기본정보는 이름과 이메일이 모두 있어야 채운 것으로 본다.
  const basicInfo = content.basicInfo;
  if (hasText(basicInfo, ["name"]) && hasText(basicInfo, ["email"])) {
    filled.add("basicInfo");
  }
  if (hasText(content.coreCompetencies, ["text"])) filled.add("coreCompetencies");
  if (hasFilledItem(content.education, ["school", "major"])) filled.add("education");
  if (hasFilledItem(content.experience, ["company", "role", "description"])) {
    filled.add("experience");
  }
  if (hasFilledItem(content.techStack, ["name"])) filled.add("techStack");
  if (hasFilledItem(content.projects, ["name", "role", "techStack", "description"])) {
    filled.add("projects");
  }
  if (hasSelfIntroduction(content.selfIntroduction)) filled.add("selfIntroduction");
  return filled;
}

/** 자기소개서는 어느 항목이든 부제목이나 본문이 있으면 채운 것으로 본다. */
function hasSelfIntroduction(value: unknown): boolean {
  if (typeof value !== "object" || value === null) return false;
  return Object.values(value as Record<string, unknown>).some((section) =>
    hasText(section, ["subtitle", "body"]),
  );
}

/** 맞춤 공고 추천에 필요하지만 비어 있는 섹션의 한글 라벨. */
function missingRequiredSections(content: Record<string, unknown>): string[] {
  const filled = filledSections(content);
  return Object.entries(REQUIRED_SECTION_LABELS)
    .filter(([key]) => !filled.has(key))
    .map(([, label]) => label);
}

export const analyzeResumeAndMatch = onCall(
  {region: "asia-northeast3", timeoutSeconds: 60},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "인증이 필요합니다.");
    const data = (request.data ?? {}) as AnalyzeRequest;
    const cohortId = data.cohortId?.trim();
    const resumeId = data.resumeId?.trim();
    if (!cohortId || !resumeId) {
      throw new HttpsError("invalid-argument", "cohortId와 resumeId는 필수입니다.");
    }

    const resumeRef = db.collection("cohorts").doc(cohortId).collection("resumes").doc(resumeId);
    const resumeDoc = await resumeRef.get();
    if (!resumeDoc.exists) throw new HttpsError("not-found", "이력서를 찾을 수 없습니다.");
    const resumeData = resumeDoc.data() ?? {};
    const isOwner = resumeData.userId === request.auth.uid;
    if (!isOwner) {
      throw new HttpsError("permission-denied", "본인 이력서만 분석할 수 있습니다.");
    }

    const storedContent =
      typeof resumeData.content === "object" && resumeData.content !== null ?
        (resumeData.content as Record<string, unknown>) :
        {};
    const content =
      typeof data.draftContent === "object" && data.draftContent !== null ?
        (data.draftContent as Record<string, unknown>) :
        storedContent;
    const missing = missingRequiredSections(content);
    if (missing.length > 0) {
      throw new HttpsError(
        "failed-precondition",
        `맞춤 공고를 추천하려면 다음 항목을 먼저 작성해주세요: ${missing.join(", ")}`,
      );
    }
    const profile = buildResumeProfile(content, data);
    const result = runJobCoach(profile);
    const inputHash = createHash("sha256")
      .update(JSON.stringify({content, data, version: "job-coach-poc-0.1.0"}))
      .digest("hex");
    const analysisRef = resumeRef.collection("aiAnalyses").doc();
    await analysisRef.set({
      ...result,
      userId: resumeData.userId,
      requestedBy: request.auth.uid,
      inputHash,
      engineVersion: "job-coach-poc-0.1.0",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {...result, analysisId: analysisRef.id, engineVersion: "job-coach-poc-0.1.0"};
  },
);
