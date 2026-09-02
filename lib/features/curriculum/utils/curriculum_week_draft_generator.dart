import '../models/curriculum_week_model.dart';

/// 총 주차 수·기간 기준 주차 초안 생성
List<CurriculumWeekModel> generateCurriculumWeekDrafts({
  required int totalWeeks,
  DateTime? startDate,
  DateTime? endDate,
  bool published = false,
}) {
  if (totalWeeks <= 0) return [];

  final weeks = <CurriculumWeekModel>[];
  for (var i = 1; i <= totalWeeks; i++) {
    DateTime? weekStart;
    DateTime? weekEnd;

    if (startDate != null && endDate != null) {
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(endDate.year, endDate.month, endDate.day);
      final totalDays = end.difference(start).inDays + 1;
      final daysPerWeek = (totalDays / totalWeeks).ceil().clamp(1, totalDays);

      weekStart = start.add(Duration(days: (i - 1) * daysPerWeek));
      weekEnd = weekStart.add(Duration(days: daysPerWeek - 1));
      if (weekEnd.isAfter(end)) weekEnd = end;
    }

    weeks.add(
      CurriculumWeekModel(
        id: 'draft-$i',
        weekNumber: i,
        title: '$i주차',
        summary: '',
        startDate: weekStart,
        endDate: weekEnd,
        published: published,
        order: i,
      ),
    );
  }
  return weeks;
}
