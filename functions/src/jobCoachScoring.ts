/**
 * 매칭 규칙 중 Python 파이프라인과 반드시 같아야 하는 부분.
 *
 * 값이 갈라지면 같은 이력서로 Python POC와 Functions가 서로 다른 점수를 낸다.
 * 대응하는 Python 위치를 각 상수에 적어 둔다.
 */

/**
 * job_matching_bot/matching/ranking.py 의 WEIGHT_* 와 같아야 한다.
 *
 * 기술 점수는 필수/우대를 따로 채점하지 않고 공고가 언급한 기술 전체와의
 * 겹침 하나로 본다. 실제 수집본에서 필수/우대가 갈린 공고가 거의 없어서,
 * 그 구분에 가중치를 걸면 그 몫이 통째로 0이 되기 때문이다.
 */
export const WEIGHTS = {
  role: 0.35,
  skills: 0.45,
  project: 0.1,
  conditions: 0.1,
} as const;

/**
 * 기술명 별칭. job_matching_bot/matching/skill_normalize.py 의 SKILL_ALIASES 와
 * 같아야 한다. 확신이 있는 것만 넣고, `ts`처럼 뜻이 겹치는 약어는 넣지 않는다.
 */
const SKILL_ALIASES: Record<string, string> = {
  reactjs: "react",
  vuejs: "vue",
  node: "nodejs",
  js: "javascript",
  postgres: "postgresql",
  oracledb: "oracle",
  golang: "go",
  k8s: "kubernetes",
  rest: "restapi",
  restfulapi: "restapi",
  css3: "css",
  html5: "html",
  c언어: "c",
  dotnet: "net",
  sqlserver: "mssql",
  amazonwebservices: "aws",
  googlecloud: "gcp",
  python3: "python",
};

/**
 * 기술명을 비교용 표준 키로 만든다. 소문자화 후 영숫자·`+`·`#`·한글만 남기고
 * 별칭 표로 접는다. `Spring Boot`/`SpringBoot`, `Node.js`/`nodejs`,
 * `ReactJS`/`React`가 같은 키가 된다. 표시용으로는 원문을 그대로 쓴다.
 */
export function canonicalSkill(name: string): string {
  const key = name.trim().toLowerCase().replace(/[^a-z0-9+#가-힣]/g, "");
  return SKILL_ALIASES[key] ?? key;
}

export function canonicalSet(names: string[]): Set<string> {
  return new Set(names.filter((name) => name.trim()).map(canonicalSkill));
}

/** job_matching_bot/matching/ranking.py 의 ROLE_HITS_FOR_FULL_SCORE */
export const ROLE_HITS_FOR_FULL_SCORE = 3;

/**
 * job_matching_bot/matching/ranking.py 의 SKILL_POOL_FLOOR.
 * 기술을 1개만 적은 공고가 1/1 = 1.0으로 만점을 받지 않게 분모에 하한을 둔다.
 */
export const SKILL_POOL_FLOOR = 4;

/** job_matching_bot/matching/ranking.py 의 GRADE_* THRESHOLD */
export const GRADE_HIGH_THRESHOLD = 70;
export const GRADE_MEDIUM_THRESHOLD = 40;

/** job_matching_bot/matching/hard_filter.py 의 EDUCATION_RANK */
export const EDUCATION_RANK: Record<string, number> = {
  학력무관: 0,
  고졸: 1,
  // 초대졸(전문대 2,3년제)은 고졸과 대졸 사이다.
  초대졸: 2,
  대졸: 3,
  석사: 4,
  박사: 5,
};

/**
 * 한글·영문이 섞인 문장에서 키워드를 찾는다.
 *
 * `\b`는 한글이 붙은 자리에서 잘못 동작한다. 한글도 단어 문자라
 * "REST API와"의 api가 잡히지 않고, 반대로 "fastapi" 안의 api가 잡힌다.
 * 그래서 영문 키워드는 앞뒤가 ASCII 영숫자가 아닐 때만 인정한다.
 * job_matching_bot/text_match.py 와 같은 규칙이다.
 */
function termPattern(term: string): RegExp {
  const escaped = term.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const isAscii = /^[\x20-\x7F]*$/.test(term);
  const body = isAscii ? `(?<![a-z0-9])${escaped}(?![a-z0-9])` : escaped;
  return new RegExp(body, "i");
}

/** 텍스트에 실제로 등장한 키워드를 중복 없이 정렬해 돌려준다. */
export function matchedTerms(text: string, terms: string[]): string[] {
  if (!text) return [];
  const found = new Set<string>();
  for (const term of terms) {
    if (termPattern(term).test(text)) found.add(term);
  }
  return [...found].sort();
}

/** 이력서 학력이 공고 요구 학력을 충족하는지. 판단할 수 없으면 null. */
export function educationPasses(
  resumeLevel: string,
  requiredLevel: string,
): boolean | null {
  if (requiredLevel === "학력무관") return true;
  if (requiredLevel === "미기재") return null;
  const required = EDUCATION_RANK[requiredLevel];
  const resume = EDUCATION_RANK[resumeLevel];
  if (required === undefined || resume === undefined) return null;
  return resume >= required;
}

export function gradeOf(score: number): string {
  if (score >= GRADE_HIGH_THRESHOLD) return "높음";
  return score >= GRADE_MEDIUM_THRESHOLD ? "보통" : "낮음";
}
