import '../../../../core/constants/app_constants.dart';
import '../../../../shared/models/resume_content.dart';
import '../models/resume_readiness.dart';
import 'cover_letter_rag_client.dart';

/// 분석 결과가 어디에서 왔는지.
enum ResumeAnalysisSource {
  /// 앱 안에서 규칙으로만 계산한 결과.
  local,

  /// cover_letter_rag 서버가 이력서 원문 근거를 대조해 돌려준 결과.
  rag,
}

/// 분석 소견 한 줄. [quote]가 있으면 이력서 원문에서 그대로 가져온 근거다.
class ResumeAnalysisItem {
  const ResumeAnalysisItem(this.text, {this.quote});

  final String text;
  final String? quote;
}

/// 분석 맥락으로 쓰인 공고. 추천 순위가 아니라 검색 관련도 순서다.
class ResumeAnalysisRelatedJob {
  const ResumeAnalysisRelatedJob({
    required this.company,
    required this.title,
    required this.summary,
  });

  final String company;
  final String title;
  final String summary;
}

/// 특정 공고와 비교하기 전에, 이력서 자체를 분석한 결과.
class ResumeAnalysis {
  const ResumeAnalysis({
    required this.strengths,
    required this.improvements,
    required this.nextSteps,
    this.source = ResumeAnalysisSource.local,
    this.confirmationQuestions = const [],
    this.relatedJobs = const [],
    this.warnings = const [],
    this.notice = '',
    this.fallbackReason,
  });

  final List<ResumeAnalysisItem> strengths;
  final List<ResumeAnalysisItem> improvements;
  final List<String> nextSteps;
  final ResumeAnalysisSource source;

  /// 이력서에 없다고 단정하는 대신 사용자에게 되묻는 질문.
  final List<String> confirmationQuestions;

  /// 서버가 시장 요구사항 참고용으로 검색한 공고.
  final List<ResumeAnalysisRelatedJob> relatedJobs;

  /// 서버가 근거 검증 중 제거한 항목 안내.
  final List<String> warnings;
  final String notice;

  /// 서버 분석에 실패해 규칙 기반 결과로 대체했을 때의 이유.
  final String? fallbackReason;

  bool get isFromRag => source == ResumeAnalysisSource.rag;

  ResumeAnalysis withFallbackReason(String reason) => ResumeAnalysis(
    strengths: strengths,
    improvements: improvements,
    nextSteps: nextSteps,
    source: source,
    confirmationQuestions: confirmationQuestions,
    relatedJobs: relatedJobs,
    warnings: warnings,
    notice: notice,
    fallbackReason: reason,
  );

  /// cover_letter_rag 첨삭 응답을 이력서 분석 형태로 옮긴다.
  ///
  /// - 충족·부분 충족 요구사항 → 강점 (서버가 원문 대조를 끝낸 인용문 포함)
  /// - 미충족 요구사항, 초안 보완점 → 보완 필요
  /// - 확인 필요 요구사항 → 확인 질문 (서버가 이미 질문 목록에 넣어 준다)
  /// - 다음 단계는 규칙 기반 결과를 그대로 쓴다. 서버는 문장을 대신 고친
  ///   `revised_draft`도 돌려주지만, 이 화면은 대필하지 않는다는 원칙을 지키기
  ///   위해 쓰지 않는다.
  factory ResumeAnalysis.fromRag({
    required ResumeAnalysis local,
    required List<RagJobSearchResult> jobs,
    required RagReviewResponse review,
  }) {
    final strengths = <ResumeAnalysisItem>[];
    final improvements = <ResumeAnalysisItem>[];

    for (final requirement in review.requirements) {
      final label = '${requirement.requirement} (${requirement.requirementType})';
      if (requirement.isMet) {
        if (requirement.resumeEvidence.isEmpty) continue;
        final first = requirement.resumeEvidence.first;
        final suffix = requirement.status == '부분 충족' ? ' — 부분 충족' : '';
        strengths.add(
          ResumeAnalysisItem(
            '$label: ${first.explanation}$suffix',
            quote: first.resumeQuote,
          ),
        );
      } else if (requirement.isNotMet) {
        final gap = (requirement.gap ?? '').trim();
        improvements.add(
          ResumeAnalysisItem(
            gap.isEmpty ? '$label: 이력서에서 근거를 찾지 못했습니다.' : '$label: $gap',
          ),
        );
      }
    }

    for (final improvement in review.improvements) {
      improvements.add(
        ResumeAnalysisItem(
          '${improvement.issue}: ${improvement.suggestion}',
          quote: improvement.groundedResumeQuote,
        ),
      );
    }

    // 서버가 짚지 못하는 구조적 공백(빈 필수 항목 등)은 규칙 기반 결과로 보강한다.
    final seen = improvements.map((e) => e.text).toSet();
    for (final item in local.improvements) {
      if (seen.add(item.text)) improvements.add(item);
    }

    return ResumeAnalysis(
      strengths: strengths,
      improvements: improvements,
      nextSteps: local.nextSteps,
      source: ResumeAnalysisSource.rag,
      confirmationQuestions: review.confirmationQuestions,
      relatedJobs: [
        for (final job in jobs)
          ResumeAnalysisRelatedJob(
            company: job.company,
            title: job.title,
            summary: job.summary,
          ),
      ],
      warnings: review.groundingWarnings,
      notice: review.notice,
    );
  }
}

/// 이력서를 규칙 기반으로 분석한다.
///
/// AI가 문장을 대신 고쳐 쓰지 않고, 어디를 어떻게 보완하면 좋은지만 알려준다.
/// 이력서에 적혀 있지 않다는 이유로 경험이 없다고 단정하지도 않는다.
ResumeAnalysis analyzeResume(ResumeContent content) {
  final readiness = ResumeReadiness.of(content);
  final strengths = <ResumeAnalysisItem>[];
  final improvements = <ResumeAnalysisItem>[];
  final nextSteps = <String>[];

  final techStack = content.techStack.where((item) => item.isFilled).toList();
  final projects = content.projects.where((item) => item.isFilled).toList();
  final experience = content.experience.where((item) => item.isFilled).toList();

  if (techStack.isNotEmpty) {
    final names = techStack.map((item) => item.name.trim()).take(6).join(', ');
    strengths.add(
      ResumeAnalysisItem('기술스택 ${techStack.length}건이 작성되어 있습니다: $names'),
    );
  }
  if (projects.isNotEmpty) {
    strengths.add(
      ResumeAnalysisItem('프로젝트 경험 ${projects.length}건이 작성되어 있습니다.'),
    );
  }
  if (experience.isNotEmpty) {
    strengths.add(
      ResumeAnalysisItem('경력 ${experience.length}건이 작성되어 있습니다.'),
    );
  }
  if (content.coreCompetencies.isFilled) {
    strengths.add(
      const ResumeAnalysisItem('핵심역량이 작성되어 있어 첫인상을 전달할 수 있습니다.'),
    );
  }

  // 기술스택에는 있지만 어떤 프로젝트에서 썼는지 드러나지 않는 기술을 찾는다.
  final projectTechText = projects
      .map((item) => '${item.techStack} ${item.description}')
      .join(' ')
      .toLowerCase();
  final unlinkedSkills = techStack
      .map((item) => item.name.trim())
      .where((name) => name.isNotEmpty)
      .where((name) => !projectTechText.contains(name.toLowerCase()))
      .toList();
  if (unlinkedSkills.isNotEmpty) {
    improvements.add(
      ResumeAnalysisItem(
        '${unlinkedSkills.take(5).join(', ')}: 기술스택에는 있으나 어떤 프로젝트에서 '
        '어떻게 사용했는지 드러나지 않습니다.',
      ),
    );
    nextSteps.add('프로젝트 설명에 사용 기술과 담당 기능을 연결해 적어보세요.');
  }

  for (final project in projects) {
    final label = project.name.trim().isEmpty ? '프로젝트' : project.name.trim();
    if (project.role.trim().isEmpty) {
      improvements.add(ResumeAnalysisItem('$label: 담당 역할이 비어 있습니다.'));
    }
    if (project.description.trim().length < 50) {
      improvements.add(
        ResumeAnalysisItem('$label: 설명이 짧아 문제 해결 과정과 성과가 드러나지 않습니다.'),
      );
    }
  }
  if (projects.isEmpty) {
    improvements.add(
      const ResumeAnalysisItem('프로젝트 경험이 없어 기술을 실제로 사용한 근거를 보여주기 어렵습니다.'),
    );
  }

  if (readiness.missingRequiredSections.isNotEmpty) {
    improvements.add(
      ResumeAnalysisItem(
        '맞춤 공고 추천에 필요한 항목이 비어 있습니다: '
        '${readiness.missingRequiredSectionLabels.join(', ')}',
      ),
    );
  }

  // 아직 작성하지 않은 선택 항목은 '부족'이 아니라 '추가하면 좋은 것'으로 안내한다.
  final optionalEmpty = AppConstants.resumeSections
      .where((key) => !requiredSectionsForRecommendation.contains(key))
      .where((key) => !readiness.filledSections.contains(key))
      .map((key) => AppConstants.resumeSectionLabels[key] ?? key)
      .toList();
  if (optionalEmpty.isNotEmpty) {
    nextSteps.add('선택 항목으로 ${optionalEmpty.join(', ')}을(를) 추가할 수 있습니다.');
  }

  if (improvements.isEmpty) {
    nextSteps.add('주요 항목이 모두 작성되어 있습니다. 맞춤 공고 추천을 실행해보세요.');
  }

  return ResumeAnalysis(
    strengths: strengths,
    improvements: improvements,
    nextSteps: nextSteps,
  );
}
