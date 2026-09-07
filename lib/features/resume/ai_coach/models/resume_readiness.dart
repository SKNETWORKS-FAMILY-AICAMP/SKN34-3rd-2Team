import '../../../../core/constants/app_constants.dart';
import '../../../../shared/models/resume_content.dart';

/// AI 코치 기능별로 이력서에 요구하는 조건이 다르다.
///
/// - 맞춤 공고 추천: 필수 항목이 **하나라도 비어 있으면** 실행하지 않는다.
///   조건이 빠진 채로 추천하면 근거 없는 순위가 나오기 때문이다.
/// - 이력서 분석: 분석할 내용이 하나라도 있으면 실행한다.
/// - 채용공고 찾기: 이력서와 무관하게 언제나 실행한다.
enum AiCoachFeature { resumeAnalysis, jobRecommendation, jobSearch }

/// 맞춤 공고 추천 전에 반드시 채워야 하는 섹션.
///
/// 경력사항·자격사항·수상내역·교육경험·기타활동은 제외했다. 이 서비스의 주
/// 사용자인 부트캠프 수료 예정자는 경력이나 수상 이력이 없는 경우가 많아,
/// 이를 필수로 두면 아무도 추천을 받을 수 없다. 대신 매칭에 실제로 쓰이는
/// 항목만 필수로 둔다.
const requiredSectionsForRecommendation = <String>[
  'basicInfo', // 기본정보
  'coreCompetencies', // 핵심역량/강점
  'education', // 학력 — Hard Filter의 학력 조건에 사용
  'techStack', // 기술스택 — 필수기술 매칭의 핵심
  'projects', // 프로젝트 경험 — 프로젝트 근거 매칭
  'selfIntroduction', // 자기소개서
];

/// 이력서 분석에 최소한 필요한 섹션. 이 중 하나라도 있으면 분석할 수 있다.
const analyzableSections = <String>[
  'coreCompetencies',
  'experience',
  'techStack',
  'projects',
];

/// 이력서가 각 기능을 실행할 준비가 되었는지 판정한 결과.
class ResumeReadiness {
  const ResumeReadiness({
    required this.filledSections,
    required this.missingRequiredSections,
  });

  /// 실제로 내용이 채워진 섹션 키.
  final Set<String> filledSections;

  /// 맞춤 공고 추천에 필요하지만 아직 비어 있는 섹션 키.
  final List<String> missingRequiredSections;

  factory ResumeReadiness.of(ResumeContent content) {
    final sections = content.computeSections();
    final filled = sections.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toSet();
    return ResumeReadiness(
      filledSections: filled,
      missingRequiredSections: requiredSectionsForRecommendation
          .where((key) => !filled.contains(key))
          .toList(),
    );
  }

  /// 필수 항목이 모두 채워져 맞춤 공고를 추천할 수 있는 상태.
  bool get canRecommendJobs => missingRequiredSections.isEmpty;

  /// 분석할 내용이 하나라도 있는 상태.
  bool get canAnalyzeResume =>
      analyzableSections.any(filledSections.contains);

  /// 채용공고 찾기는 이력서 상태와 무관하다.
  bool get canSearchJobs => true;

  bool canRun(AiCoachFeature feature) {
    switch (feature) {
      case AiCoachFeature.jobRecommendation:
        return canRecommendJobs;
      case AiCoachFeature.resumeAnalysis:
        return canAnalyzeResume;
      case AiCoachFeature.jobSearch:
        return canSearchJobs;
    }
  }

  /// 실행할 수 없을 때 사용자에게 보여줄 이유. 실행 가능하면 null.
  String? blockedReason(AiCoachFeature feature) {
    if (canRun(feature)) return null;
    switch (feature) {
      case AiCoachFeature.jobRecommendation:
        return '맞춤 공고를 추천하려면 다음 항목을 먼저 작성해주세요: '
            '${missingRequiredSectionLabels.join(', ')}';
      case AiCoachFeature.resumeAnalysis:
        return '분석할 내용이 아직 없습니다. 핵심역량, 경력, 기술스택, '
            '프로젝트 중 하나 이상을 작성해주세요.';
      case AiCoachFeature.jobSearch:
        return null;
    }
  }

  /// 비어 있는 필수 항목의 한글 라벨.
  List<String> get missingRequiredSectionLabels => missingRequiredSections
      .map((key) => AppConstants.resumeSectionLabels[key] ?? key)
      .toList();

  /// 필수 항목 중 몇 개를 채웠는지.
  int get completedRequiredCount =>
      requiredSectionsForRecommendation.length - missingRequiredSections.length;

  int get totalRequiredCount => requiredSectionsForRecommendation.length;
}
