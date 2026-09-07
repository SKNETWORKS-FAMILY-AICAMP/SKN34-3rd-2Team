import '../../ai_coach/data/generated/collected_jobs.g.dart';

/// 기술스택 태그 후보.
///
/// 부트캠프 수료생이 자주 적는 기술을 손으로 고른 기본 목록에, 수집한 채용공고가
/// 실제로 요구하는 기술을 합친다. 공고 쪽 이름이 들어가야 태그를 고르는 것만으로
/// 키워드 매칭에 잡히는 표기를 쓰게 된다.
abstract final class SkillCatalog {
  static const baseSkills = <String>[
    // 언어
    'Python', 'Java', 'JavaScript', 'TypeScript', 'Dart', 'Kotlin', 'Swift',
    'C', 'C++', 'C#', 'Go', 'Rust', 'R', 'SQL', 'HTML/CSS',
    // 백엔드 · 프레임워크
    'Spring Boot', 'FastAPI', 'Django', 'Flask', 'Node.js', 'Express', 'NestJS',
    'REST API', 'GraphQL', 'JPA',
    // 프론트엔드 · 모바일
    'React', 'Next.js', 'Vue', 'Flutter', 'React Native', 'Android', 'iOS',
    'Tailwind CSS',
    // 데이터 · AI
    'NumPy', 'Pandas', 'Matplotlib', 'Scikit-learn', 'PyTorch', 'TensorFlow',
    'Keras', 'OpenCV', 'Hugging Face', 'LangChain', 'LLM', 'RAG',
    'Deep Learning', 'Machine Learning', 'Data Analysis', 'NLP',
    'Streamlit', 'Airflow', 'Spark', 'Hadoop', 'Kafka', 'Tableau', 'Power BI',
    'Excel',
    // 데이터베이스
    'MySQL', 'PostgreSQL', 'Oracle', 'MongoDB', 'Redis', 'Elasticsearch',
    'Neo4j', 'Firebase', 'Firestore',
    // 인프라 · 협업
    'Linux', 'Docker', 'Kubernetes', 'AWS', 'GCP', 'Azure', 'Git', 'GitHub',
    'GitHub Actions', 'Jenkins', 'Nginx', 'Figma', 'Jira', 'Notion',
  ];

  /// 기본 목록 + 수집 공고의 필수·우대·태그 기술. 표기가 같으면 하나만 남긴다.
  static final List<String> all = _build();

  static List<String> _build() {
    final byKey = <String, String>{};
    void add(String name) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) return;
      byKey.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
    }

    baseSkills.forEach(add);
    for (final job in collectedJobs) {
      job.requiredSkills.forEach(add);
      job.preferredSkills.forEach(add);
      job.techStack.forEach(add);
    }
    final names = byKey.values.toList();
    // 기본 목록은 손으로 정한 순서를 지키고, 공고에서 온 것은 그 뒤에 이름순으로 둔다.
    final baseKeys = baseSkills.map((s) => s.toLowerCase()).toSet();
    final fromJobs = names.where((n) => !baseKeys.contains(n.toLowerCase())).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [
      ...baseSkills.map((s) => byKey[s.toLowerCase()] ?? s),
      ...fromJobs,
    ];
  }

  /// 검색어로 후보를 거른다. 비어 있으면 전체.
  static List<String> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    final starts = <String>[];
    final contains = <String>[];
    for (final name in all) {
      final lower = name.toLowerCase();
      if (lower.startsWith(q)) {
        starts.add(name);
      } else if (lower.contains(q)) {
        contains.add(name);
      }
    }
    return [...starts, ...contains];
  }

  /// 대소문자·공백 차이를 무시하고 같은 기술로 본다.
  static bool sameSkill(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  /// 후보 목록에 있는 표기가 있으면 그것으로 맞춰 준다. 없으면 입력 그대로.
  static String canonical(String name) {
    final trimmed = name.trim();
    for (final candidate in all) {
      if (sameSkill(candidate, trimmed)) return candidate;
    }
    return trimmed;
  }
}
