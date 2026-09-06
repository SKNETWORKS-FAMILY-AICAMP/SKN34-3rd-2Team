import '../../../../shared/models/resume_content.dart';

/// 추천 서버 요청에 넣는 이력서 조건. 학력·연차·전공·자격증을 이력서에서 뽑는다.
///
/// 서버의 하드 필터(`job_matching_bot/matching/hard_filter.py`)가 이 값으로 연차·학력·
/// 전공·자격증 조건을 판정한다. 기술·경험은 여기 없고 이력서 평문으로 보낸다.
class RecommendResumeProfile {
  const RecommendResumeProfile({
    required this.educationLevel,
    required this.careerYears,
    required this.majors,
    required this.certifications,
  });

  /// 앱 이력서에는 학위 필드가 없어 학력 항목이 있으면 '대졸'로 본다.
  final String educationLevel;
  final double careerYears;

  /// 학력사항의 전공과 자격사항 이름.
  final List<String> majors;
  final List<String> certifications;

  factory RecommendResumeProfile.fromContent(ResumeContent content) {
    final education = content.education.where((e) => e.isFilled).toList();
    final experience = content.experience.where((e) => e.isFilled).toList();
    return RecommendResumeProfile(
      educationLevel: education.isNotEmpty ? '대졸' : '미기재',
      careerYears: estimateCareerYears(experience),
      majors: [for (final e in education) if (e.major.trim().isNotEmpty) e.major.trim()],
      certifications: [
        for (final c in content.certifications)
          if (c.name.trim().isNotEmpty) c.name.trim(),
      ],
    );
  }
}

DateTime? _parseMonth(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final normalized = RegExp(r'^\d{4}-\d{2}$').hasMatch(trimmed) ? '$trimmed-01' : trimmed;
  return DateTime.tryParse(normalized);
}

/// 경력사항의 재직 기간을 월 단위로 더해 소수 첫째 자리까지. 재직 중은 오늘까지.
double estimateCareerYears(List<ResumeExperienceItem> experience) {
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
