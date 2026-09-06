import '../../../../shared/models/resume_content.dart';

/// 이력서를 추천 서버에 보낼 평문으로 바꾼다.
///
/// 서버는 모델이 돌려준 인용문이 이 평문 안에 **연속해서** 존재할 때만
/// 근거로 인정한다. 따라서 사용자가 입력한 문장은 다듬지 않고 그대로 넣고,
/// 라벨만 붙여 어떤 항목인지 알 수 있게 한다.
String buildResumeText(ResumeContent content) {
  final buffer = StringBuffer();

  void section(String title, Iterable<String> lines) {
    final body = lines.map((line) => line.trim()).where((l) => l.isNotEmpty);
    if (body.isEmpty) return;
    if (buffer.isNotEmpty) buffer.writeln();
    buffer.writeln('[$title]');
    for (final line in body) {
      buffer.writeln(line);
    }
  }

  section('핵심역량', [content.coreCompetencies.text]);

  section(
    '기술스택',
    content.techStack.where((e) => e.isFilled).map(
          (e) => e.level.trim().isEmpty
              ? e.name.trim()
              : '${e.name.trim()} (${e.level.trim()})',
        ),
  );

  section('프로젝트 경험', _projectLines(content));

  section(
    '경력사항',
    content.experience.where((e) => e.isFilled).expand(
          (e) => [
            '- ${e.company.trim()}'
                '${e.role.trim().isEmpty ? '' : ' / ${e.role.trim()}'}'
                '${_period(e.startDate, e.isCurrent ? '재직 중' : e.endDate)}',
            if (e.description.trim().isNotEmpty) '  ${e.description.trim()}',
          ],
        ),
  );

  section(
    '학력사항',
    content.education.where((e) => e.isFilled).map(
          (e) => '- ${e.school.trim()}'
              '${e.major.trim().isEmpty ? '' : ' ${e.major.trim()}'}'
              '${e.status.trim().isEmpty ? '' : ' (${e.status.trim()})'}',
        ),
  );

  section(
    '자격사항',
    content.certifications.where((e) => e.isFilled).map(
          (e) => '- ${e.name.trim()}'
              '${e.issuer.trim().isEmpty ? '' : ' / ${e.issuer.trim()}'}'
              '${e.acquiredDate.trim().isEmpty ? '' : ' (${e.acquiredDate.trim()})'}',
        ),
  );

  section(
    '수상내역',
    content.awards.where((e) => e.isFilled).expand(
          (e) => [
            '- ${e.name.trim()}'
                '${e.organization.trim().isEmpty ? '' : ' / ${e.organization.trim()}'}'
                '${e.date.trim().isEmpty ? '' : ' (${e.date.trim()})'}',
            if (e.description.trim().isNotEmpty) '  ${e.description.trim()}',
          ],
        ),
  );

  section(
    '교육경험',
    content.trainingExperience.where((e) => e.isFilled).expand(
          (e) => [
            '- ${e.course.trim()}'
                '${e.organization.trim().isEmpty ? '' : ' / ${e.organization.trim()}'}'
                '${_period(e.startDate, e.endDate)}',
            if (e.description.trim().isNotEmpty) '  ${e.description.trim()}',
          ],
        ),
  );

  section(
    '기타활동',
    content.otherActivities.where((e) => e.isFilled).expand(
          (e) => [
            '- ${e.name.trim()}${_period(e.startDate, e.endDate)}',
            if (e.description.trim().isNotEmpty) '  ${e.description.trim()}',
          ],
        ),
  );

  final intro = buildSelfIntroductionText(content);
  if (intro.isNotEmpty) {
    if (buffer.isNotEmpty) buffer.writeln();
    buffer.writeln('[자기소개서]');
    buffer.writeln(intro);
  }

  return buffer.toString().trim();
}

/// 자기소개서 항목만 모아 평문으로 만든다.
String buildSelfIntroductionText(ResumeContent content) {
  final buffer = StringBuffer();
  for (final key in ResumeSelfIntroLabels.keys) {
    final section = content.selfIntroduction.sectionByKey(key);
    if (!section.isFilled) continue;
    if (buffer.isNotEmpty) buffer.writeln();
    final label = ResumeSelfIntroLabels.labels[key] ?? key;
    final subtitle = section.subtitle.trim();
    buffer.writeln(subtitle.isEmpty ? '($label)' : '($label) $subtitle');
    buffer.writeln(section.body.trim());
  }
  return buffer.toString().trim();
}

Iterable<String> _projectLines(ResumeContent content) =>
    content.projects.where((e) => e.isFilled).expand(
          (p) => [
            '- ${p.name.trim()}${_period(p.startDate, p.endDate)}',
            if (p.role.trim().isNotEmpty) '  역할: ${p.role.trim()}',
            if (p.techStack.trim().isNotEmpty) '  기술: ${p.techStack.trim()}',
            if (p.description.trim().isNotEmpty) '  ${p.description.trim()}',
          ],
        );

String _period(String start, String end) {
  final s = start.trim();
  final e = end.trim();
  if (s.isEmpty && e.isEmpty) return '';
  return ' ($s ~ $e)';
}
