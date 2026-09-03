/// Functions 없이 클라이언트에서 돌리는 매칭.
///
/// 로컬 모드(`AiJobCoachConfig.useLocalFixture`)에서 쓴다. 예전에는 고정
/// 문자열을 돌려줘서 학력을 채워도 "학력 근거 미입력"이 그대로 나왔다. 여기서는
/// 배포 모드와 **같은 규칙**으로 실제 이력서와 수집 공고를 계산한다.
///
/// 규칙의 원본은 다음 둘이고, 값이 갈라지면 같은 이력서로 다른 점수가 난다.
/// - functions/src/jobCoach.ts, jobCoachScoring.ts
/// - job_matching_bot/matching/ranking.py, hard_filter.py, skill_normalize.py
library;

import '../../../../shared/models/resume_content.dart';
import '../models/collected_job.dart';
import 'text_match.dart';

// ── 상수 (원본과 같아야 한다) ─────────────────────────────────────────

/// jobCoachScoring.ts 의 WEIGHTS / ranking.py 의 WEIGHT_*
const _weightRole = 0.35;
const _weightSkills = 0.45;
const _weightProject = 0.10;
const _weightConditions = 0.10;

const _roleHitsForFullScore = 3;

/// ranking.py 의 SKILL_POOL_FLOOR. 기술을 1개만 적은 공고가 만점을 받지 않게 한다.
const _skillPoolFloor = 4;
const _gradeHigh = 70;
const _gradeMedium = 40;

/// hard_filter.py 의 EDUCATION_RANK
const _educationRank = <String, int>{
  '학력무관': 0,
  '고졸': 1,
  '초대졸': 2,
  '대졸': 3,
  '석사': 4,
  '박사': 5,
};

/// ranking.py / jobCoach.ts 의 ROLE_TERMS
const _roleTerms = <String, List<String>>{
  '백엔드 개발자': ['백엔드', 'backend', 'fastapi', 'django', 'api', '전산', '시스템운영'],
  'AI 엔지니어': ['ai engineering', 'ai', '인공지능', '머신러닝', '추천 시스템', '데이터'],
  '프론트엔드 개발자': ['프론트엔드', 'frontend', 'front-end', 'react', 'vue', '웹개발', 'ui개발'],
  '데이터 엔지니어': ['데이터엔지니어', '데이터 엔지니어', 'data engineer', '데이터', 'etl', 'spark', '빅데이터'],
  '임베디드 개발자': ['임베디드', 'embedded', '펌웨어', 'firmware', 'rtos', 'h/w'],
};

/// skill_normalize.py / jobCoachScoring.ts 의 SKILL_ALIASES
const _skillAliases = <String, String>{
  'reactjs': 'react',
  'vuejs': 'vue',
  'node': 'nodejs',
  'js': 'javascript',
  'postgres': 'postgresql',
  'oracledb': 'oracle',
  'golang': 'go',
  'k8s': 'kubernetes',
  'rest': 'restapi',
  'restfulapi': 'restapi',
  'css3': 'css',
  'html5': 'html',
  'c언어': 'c',
  'dotnet': 'net',
  'sqlserver': 'mssql',
  'amazonwebservices': 'aws',
  'googlecloud': 'gcp',
  'python3': 'python',
};

final _skillStrip = RegExp(r'[^a-z0-9+#가-힣]');

/// 기술명을 비교용 표준 키로. `Spring Boot`/`SpringBoot`, `Node.js`/`nodejs`가 같아진다.
String canonicalSkill(String name) {
  final key = name.trim().toLowerCase().replaceAll(_skillStrip, '');
  return _skillAliases[key] ?? key;
}

Set<String> canonicalSet(Iterable<String> names) => {
      for (final name in names)
        if (name.trim().isNotEmpty) canonicalSkill(name),
    };

/// jobCoach.ts 의 LEARNING_CATALOG (표준 키로 찾는다)
const _learningCatalog = <String, Map<String, String>>{
  'kubernetes': {
    'provider': 'Kubernetes 공식 문서',
    'title': 'Kubernetes Basics',
    'url': 'https://kubernetes.io/docs/tutorials/kubernetes-basics/',
    'level': '입문',
    'estimatedDuration': '2~3시간',
    'lastCheckedAt': 'TEST_FIXTURE',
  },
  'redis': {
    'provider': 'Redis 공식 문서',
    'title': 'Redis Get started',
    'url': 'https://redis.io/docs/latest/get-started/',
    'level': '입문',
    'estimatedDuration': '1~2시간',
    'lastCheckedAt': 'TEST_FIXTURE',
  },
};

// ── 이력서 프로필 (jobCoach.ts buildResumeProfile 과 같은 규칙) ────────

class LocalResumeProfile {
  const LocalResumeProfile({
    required this.skills,
    required this.projectSkills,
    required this.educationLevel,
    required this.hasEducationEvidence,
    required this.careerYears,
    required this.hasCareerEvidence,
    required this.targetRoles,
    required this.preferredRegions,
    required this.preferredEmploymentTypes,
    required this.confirmedMissingSkills,
  });

  final Set<String> skills;
  final Set<String> projectSkills;

  /// 앱 이력서에는 학위 필드가 없어 학력 항목이 있으면 '대졸'로 본다.
  final String educationLevel;
  final bool hasEducationEvidence;
  final double careerYears;
  final bool hasCareerEvidence;
  final List<String> targetRoles;
  final List<String> preferredRegions;
  final List<String> preferredEmploymentTypes;
  final Set<String> confirmedMissingSkills;

  factory LocalResumeProfile.fromContent(
    ResumeContent content, {
    List<String> targetRoles = const [],
    List<String> preferredRegions = const [],
    List<String> preferredEmploymentTypes = const [],
    Iterable<String> confirmedMissingSkills = const [],
  }) {
    final education = content.education.where((e) => e.isFilled).toList();
    final experience = content.experience.where((e) => e.isFilled).toList();
    return LocalResumeProfile(
      skills: canonicalSet(content.techStack.map((e) => e.name)),
      projectSkills: canonicalSet(
        content.projects.expand((p) => p.techStack.split(RegExp(r'[,/|·\n]+'))),
      ),
      educationLevel: education.isNotEmpty ? '대졸' : '미기재',
      hasEducationEvidence: education.isNotEmpty,
      careerYears: _estimateCareerYears(experience),
      hasCareerEvidence: experience.isNotEmpty,
      targetRoles: targetRoles,
      preferredRegions: preferredRegions,
      preferredEmploymentTypes: preferredEmploymentTypes,
      confirmedMissingSkills: canonicalSet(confirmedMissingSkills),
    );
  }
}

DateTime? _parseMonth(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final normalized = RegExp(r'^\d{4}-\d{2}$').hasMatch(trimmed) ? '$trimmed-01' : trimmed;
  return DateTime.tryParse(normalized);
}

/// jobCoach.ts 의 estimateCareerYears: 월 단위로 더해 소수 첫째 자리까지.
double _estimateCareerYears(List<ResumeExperienceItem> experience) {
  var months = 0;
  final now = DateTime.now();
  for (final item in experience) {
    final start = _parseMonth(item.startDate);
    final end = item.isCurrent ? now : _parseMonth(item.endDate);
    if (start == null || end == null || end.isBefore(start)) continue;
    final diff = (end.year - start.year) * 12 + end.month - start.month;
    months += diff < 0 ? 0 : diff;
  }
  return (months / 12 * 10).round() / 10;
}

// ── Hard Filter (jobCoach.ts hardFilter 와 같은 규칙) ───────────────────

class LocalFilterResult {
  const LocalFilterResult(this.status, this.passed, this.failed, this.unknown);
  final String status;
  final List<String> passed;
  final List<String> failed;
  final List<String> unknown;

  Map<String, dynamic> toMap() => {
        'status': status,
        'passed': passed,
        'failed': failed,
        'unknown': unknown,
      };
}

bool? _educationPasses(String resumeLevel, String requiredLevel) {
  if (requiredLevel == '학력무관') return true;
  if (requiredLevel == '미기재') return null;
  final required = _educationRank[requiredLevel];
  final resume = _educationRank[resumeLevel];
  if (required == null || resume == null) return null;
  return resume >= required;
}

LocalFilterResult hardFilter(CollectedJob job, LocalResumeProfile resume) {
  final passed = <String>[];
  final failed = <String>[];
  final unknown = <String>[];

  if (job.status != 'OPEN') {
    failed.add('공고 상태 ${job.status}');
  } else {
    passed.add('공고 진행 중');
  }

  if (job.careerType == 'EXPERIENCED') {
    final minYears = job.minCareerYears;
    if (minYears == null) {
      unknown.add('경력 연수 미기재');
    } else if (!resume.hasCareerEvidence) {
      unknown.add('이력서 경력 근거 미입력');
    } else if (resume.careerYears < minYears) {
      failed.add('최소 경력 $minYears년');
    } else {
      passed.add('경력 조건 충족');
    }
  } else if (job.careerType == 'UNKNOWN') {
    unknown.add('경력 조건 미기재');
  } else {
    passed.add('경력 조건 충족');
  }

  // 이력서에 학력을 아직 입력하지 않은 것과 요건을 못 채운 것은 다르다.
  if (job.education != '학력무관' && !resume.hasEducationEvidence) {
    unknown.add('이력서 학력 근거 미입력');
  } else {
    final result = _educationPasses(resume.educationLevel, job.education);
    if (result == true) {
      passed.add('학력 조건 충족');
    } else if (result == false) {
      failed.add('필수 학력 ${job.education}');
    } else {
      unknown.add('학력 조건 미기재');
    }
  }

  if (resume.preferredRegions.isEmpty) {
    unknown.add('희망 근무지역 미입력');
  } else if (resume.preferredRegions.any(job.region.contains)) {
    passed.add('희망 근무지역 일치');
  } else {
    failed.add('희망지역 불일치: ${job.region}');
  }

  final employment = job.employmentType;
  if (resume.preferredEmploymentTypes.isEmpty) {
    unknown.add('희망 고용형태 미입력');
  } else if (employment == null) {
    unknown.add('고용형태 미기재');
  } else if (resume.preferredEmploymentTypes.contains(employment)) {
    passed.add('희망 고용형태 일치');
  } else {
    failed.add('희망 고용형태 불일치: $employment');
  }

  final status = failed.isNotEmpty
      ? 'FAIL'
      : unknown.isNotEmpty
          ? 'CHECK_REQUIRED'
          : 'PASS';
  return LocalFilterResult(status, passed, failed, unknown);
}

// ── Ranking (jobCoach.ts rankJobs 와 같은 규칙) ─────────────────────────

/// 공고가 언급한 기술: 표준 키 → 표시용 원문. 필수/우대/기술스택을 한 목록으로.
(Map<String, String>, List<String>) declaredSkills(CollectedJob job) {
  final pool = <String, String>{};
  final sources = <String>[];
  final buckets = <(String, List<String>)>[
    ('required_skills', job.requiredSkills),
    ('preferred_skills', job.preferredSkills),
    ('tech_stack', job.techStack),
  ];
  for (final (source, values) in buckets) {
    if (values.isNotEmpty) sources.add(source);
    for (final value in values) {
      pool.putIfAbsent(canonicalSkill(value), () => value);
    }
  }
  return (pool, sources);
}

(double, List<String>) _skillScore(Set<String> resumeKeys, Map<String, String> pool) {
  if (pool.isEmpty) return (0, const []);
  final matched = [
    for (final entry in pool.entries)
      if (resumeKeys.contains(entry.key)) entry.value,
  ]..sort();
  final denominator = pool.length < _skillPoolFloor ? _skillPoolFloor : pool.length;
  return (matched.length / denominator, matched);
}

(double, List<String>) _roleScore(LocalResumeProfile resume, CollectedJob job) {
  final text = '${job.title} ${job.description}'.toLowerCase();
  final terms = resume.targetRoles
      .expand((role) => _roleTerms[role] ?? [role.toLowerCase()])
      .toList();
  final hits = matchedTerms(text, terms);
  final score = hits.length / _roleHitsForFullScore;
  return (score > 1 ? 1 : score, hits);
}

String gradeOf(double score) {
  if (score >= _gradeHigh) return '높음';
  return score >= _gradeMedium ? '보통' : '낮음';
}

List<Map<String, dynamic>> rankJobs(List<CollectedJob> jobs, LocalResumeProfile resume) {
  final ranked = <Map<String, dynamic>>[];
  for (final job in jobs) {
    final filter = hardFilter(job, resume);
    if (filter.status == 'FAIL') continue;
    final (role, roleTerms) = _roleScore(resume, job);
    final (pool, skillsSource) = declaredSkills(job);
    final (skills, matchedSkills) = _skillScore(resume.skills, pool);
    final (project, projectSkills) = _skillScore(resume.projectSkills, pool);
    final conditions = filter.status == 'PASS' ? 1.0 : 0.5;
    final score = ((role * _weightRole +
                skills * _weightSkills +
                project * _weightProject +
                conditions * _weightConditions) *
            1000)
        .round() /
        10;
    ranked.add({
      'jobId': job.jobId,
      'source': job.source,
      'sourceUrl': job.sourceUrl,
      'company': job.company,
      'title': job.title,
      'recommendationScore': score,
      'grade': gradeOf(score),
      'hardFilter': filter.toMap(),
      'scoreDetail': {
        'role': role,
        'skills': skills,
        'skillsSource': skillsSource,
        'skillsTotal': pool.length,
        'project': project,
        'conditions': conditions,
      },
      'evidence': {
        'roleTerms': roleTerms,
        'matchedSkills': matchedSkills,
        'projectSkills': projectSkills,
      },
    });
  }
  ranked.sort(
    (a, b) => (b['recommendationScore'] as double).compareTo(a['recommendationScore'] as double),
  );
  return ranked;
}

// ── Skill Gap (jobCoach.ts analyzeSkills 와 같은 규칙) ───────────────────

Map<String, dynamic> analyzeSkills(CollectedJob job, LocalResumeProfile resume) {
  final judgements = <Map<String, dynamic>>[];
  final resumeFeedback = <String>[];
  final learning = <Map<String, dynamic>>[];
  // REQUIRED/PREFERRED는 본문에서 가른 것, DECLARED는 기업이 고른 기술스택 태그.
  // 같은 기술이 여러 층에 있으면 더 구체적인 층 하나로만 판정한다.
  const tierLabel = {'REQUIRED': 'REQUIRED', 'PREFERRED': 'PREFERRED', 'DECLARED': '기술스택 태그'};
  final tiers = <(String, List<String>)>[
    ('REQUIRED', job.requiredSkills),
    ('PREFERRED', job.preferredSkills),
    ('DECLARED', job.techStack),
  ];
  final seen = <String>{};

  for (final (requirementType, skills) in tiers) {
    for (final skill in skills) {
      final key = canonicalSkill(skill);
      if (key.isEmpty || !seen.add(key)) continue;

      String judgement;
      var resumeEvidence = <String>[];
      String? confirmationQuestion;
      if (resume.skills.contains(key)) {
        judgement = 'EVIDENCED';
        resumeEvidence = ['기술스택: $skill'];
        if (resume.projectSkills.contains(key)) {
          resumeEvidence.add('프로젝트 기술: $skill');
        } else {
          resumeFeedback.add('$skill: 기술스택에는 있으나 프로젝트에서 사용한 기능·역할·결과 근거를 보강하세요.');
        }
      } else if (resume.confirmedMissingSkills.contains(key)) {
        judgement = 'CONFIRMED_MISSING';
        resumeEvidence = ['사용자 확인: $skill 실사용 경험 없음'];
        final catalog = _learningCatalog[key];
        if (catalog != null) learning.add({'skill': skill, ...catalog});
      } else {
        judgement = 'NOT_EVIDENCED';
        confirmationQuestion = '이력서에서는 $skill 경험을 확인하지 못했습니다. 실제 사용 경험이 있나요?';
      }
      judgements.add({
        'criterion': skill,
        'requirementType': requirementType,
        'judgement': judgement,
        'resumeEvidence': resumeEvidence,
        'jobEvidence': ['${tierLabel[requirementType]}: $skill'],
        'confirmationQuestion': confirmationQuestion,
        'confidence': 1,
        'method': 'deterministic_local_rule',
      });
    }
  }
  return {
    'judgements': judgements,
    'resumeFeedback': resumeFeedback,
    'learningRecommendations': learning,
  };
}

// ── 진입점: Functions 응답과 같은 모양 ─────────────────────────────────

/// `analyzeResumeAndMatch` Functions 응답과 같은 맵을 만든다.
/// `AiJobCoachResult.fromMap`이 그대로 읽는다.
Map<String, dynamic> runLocalJobCoach({
  required List<CollectedJob> jobs,
  required ResumeContent content,
  Iterable<String> confirmedMissingSkills = const [],
  List<String> targetRoles = const [],
  List<String> preferredRegions = const [],
  List<String> preferredEmploymentTypes = const [],
}) {
  final resume = LocalResumeProfile.fromContent(
    content,
    targetRoles: targetRoles,
    preferredRegions: preferredRegions,
    preferredEmploymentTypes: preferredEmploymentTypes,
    confirmedMissingSkills: confirmedMissingSkills,
  );
  final ranked = rankJobs(jobs, resume);
  final topId = ranked.isEmpty ? null : ranked.first['jobId'] as String;
  final selected = topId == null ? null : jobs.firstWhere((job) => job.jobId == topId);

  return {
    'testMode': true,
    'analysisId': 'local-${DateTime.now().millisecondsSinceEpoch}',
    'recommendationNotice':
        'IT 채용공고만 대상으로 하며, 추천 점수는 합격 확률이 아닌 정렬용 점수입니다. '
        '(로컬 계산 — 서버와 같은 규칙)',
    'recommendations': ranked,
    'selectedJob': selected == null
        ? null
        : {
            'jobId': selected.jobId,
            'company': selected.company,
            'title': selected.title,
            'requiredSkills': selected.requiredSkills,
            'preferredSkills': selected.preferredSkills,
            'techStack': selected.techStack,
          },
    'skillAnalysis': selected == null
        ? {'judgements': <Map<String, dynamic>>[], 'resumeFeedback': <String>[], 'learningRecommendations': <Map<String, dynamic>>[]}
        : analyzeSkills(selected, resume),
  };
}
