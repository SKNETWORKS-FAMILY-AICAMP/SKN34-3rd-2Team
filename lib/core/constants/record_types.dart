/// 기록실 제출 유형
abstract final class RecordTypes {
  static const certification = 'certification';
  static const study = 'study';
  static const blog = 'blog';

  static const all = [certification, study, blog];

  static const labels = {
    certification: '자격증',
    study: '스터디',
    blog: '블로그',
  };

  static const descriptions = {
    certification:
        '자격증 인증 항목은 PCCE/PCCP/PCSQL 이 외에 자격증은 승인 되지 않으니 유의 해주세요.',
    study: '사전 담당 매니저와 협의된 스터디 활동이 아닐시 승인이 어려움이 있을 수 있습니다.',
    blog: '안내 되었던 블로그 양식에 맞춰 작성된 블로그 링크를 첨부 해주시기 바랍니다.',
  };

  static const certKinds = ['PCCE', 'PCCP', 'PCSQL'];
}

class BlogWeekOption {
  const BlogWeekOption({
    required this.weekNumber,
    required this.label,
    required this.start,
    required this.end,
  });

  final int weekNumber;
  final String label;
  final DateTime start;
  final DateTime end;

  String get key => 'week_$weekNumber';
}

List<BlogWeekOption> generateBlogWeeks({DateTime? campStart, int count = 12}) {
  final start = campStart ?? DateTime(DateTime.now().year, 6, 1);
  return List.generate(count, (i) {
    final weekStart = start.add(Duration(days: i * 7));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final n = i + 1;
    return BlogWeekOption(
      weekNumber: n,
      label:
          '$n주차 ${weekStart.month}/${weekStart.day}~${weekEnd.month}/${weekEnd.day}',
      start: weekStart,
      end: weekEnd,
    );
  });
}
