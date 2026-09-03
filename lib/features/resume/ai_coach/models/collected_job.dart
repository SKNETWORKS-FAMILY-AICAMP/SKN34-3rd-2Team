/// 수집 파이프라인이 내보낸 채용공고 한 건.
///
/// 실제 데이터는 `data/generated/collected_jobs.g.dart`에 자동 생성된다.
/// 원본은 job_matching_bot이며 Dart에서 직접 공고를 추가하지 않는다.
class CollectedJob {
  const CollectedJob({
    required this.jobId,
    required this.company,
    required this.title,
    required this.description,
    required this.requiredSkills,
    required this.preferredSkills,
    required this.techStack,
    required this.careerType,
    this.minCareerYears,
    required this.education,
    required this.region,
    required this.employmentType,
    required this.deadline,
    required this.source,
    required this.sourceUrl,
    this.status = 'OPEN',
  });

  final String jobId;
  final String company;
  final String title;
  final String description;
  final List<String> requiredSkills;
  final List<String> preferredSkills;

  /// 기업이 공고 등록 때 고른 기술 태그. 필수·우대 구분이 없다.
  final List<String> techStack;

  /// 신입·경력 조건. `ENTRY` / `EXPERIENCED` / `ANY` / `UNKNOWN`.
  final String careerType;

  /// 경력 공고의 최소 연차. 공고에 숫자가 없으면 null이며 단정하지 않는다.
  final int? minCareerYears;
  final String education;
  final String region;

  /// 정규직·계약직 등 고용형태. 공고에 없으면 null이며 단정하지 않는다.
  final String? employmentType;
  final String? deadline;
  final String source;
  final String sourceUrl;

  /// OPEN / EXPIRED. 수집 시점 기준이다.
  final String status;

  /// 신입이 지원할 수 있는 공고인지. 확인할 수 없으면 false가 아니라 null이다.
  bool? get isEntryFriendly {
    switch (careerType) {
      case 'ENTRY':
      case 'ANY':
        return true;
      case 'EXPERIENCED':
        return false;
      default:
        return null;
    }
  }

  String get careerLabel {
    switch (careerType) {
      case 'ENTRY':
        return '신입';
      case 'EXPERIENCED':
        return '경력';
      case 'ANY':
        return '경력무관';
      default:
        return '경력 조건 미기재';
    }
  }

  /// 검색 대상 텍스트. 제목·기업·기술·본문을 합쳐 소문자로 만든다.
  String get searchText => [
    title,
    company,
    region,
    careerLabel,
    ...requiredSkills,
    ...preferredSkills,
    ...techStack,
    description,
  ].join(' ').toLowerCase();
}
