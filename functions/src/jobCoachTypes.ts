/**
 * AI 취업 코치가 사용하는 공용 타입.
 *
 * `CollectedJob`은 Python 수집 파이프라인이 내보내는 레코드와 1:1로 대응한다.
 * 필드를 바꾸려면 job_matching_bot/exporters/typescript.py 의 FIELD_NAMES도
 * 함께 고쳐야 한다.
 */

export type CareerType = "ENTRY" | "ANY" | "EXPERIENCED" | "UNKNOWN";
export type FilterStatus = "PASS" | "CHECK_REQUIRED" | "FAIL";
export type EvidenceState = "EVIDENCED" | "NOT_EVIDENCED" | "CONFIRMED_MISSING";
export type JobStatus = "OPEN" | "EXPIRED";

/** 수집 파이프라인이 내보낸 채용공고 한 건. */
export interface CollectedJob {
  jobId: string;
  company: string;
  title: string;
  description: string;
  requiredSkills: string[];
  preferredSkills: string[];
  /** 기업이 공고 등록 때 고른 기술 태그. 필수·우대 구분이 없다. */
  techStack: string[];
  /** 본문이 이미지뿐이라 요구역량을 텍스트로 확보하지 못한 공고. 예전 데이터에는 없다. */
  bodyIsImage?: boolean;
  /** 자격요건 구간에서 뽑은 전공·자격증·병역 요건. 예전 데이터에는 없다. */
  requiredMajors?: string[];
  requiredMajorTerms?: string[];
  requiredCertifications?: string[];
  militaryRequired?: boolean;
  careerType: CareerType;
  minCareerYears: number | null;
  /** "학력무관" / "대졸" 등. 확인할 수 없으면 "미기재". */
  education: string;
  region: string;
  /** 공고에 명시되지 않았으면 null이며, Hard Filter에서 확인 필요로 다룬다. */
  employmentType: string | null;
  status: JobStatus;
  source: string;
  sourceUrl: string;
  deadline: string | null;
}

export interface FilterResult {
  status: FilterStatus;
  passed: string[];
  failed: string[];
  unknown: string[];
}
