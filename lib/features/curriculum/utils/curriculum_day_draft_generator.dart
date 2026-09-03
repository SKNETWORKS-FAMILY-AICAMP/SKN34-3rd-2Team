import '../models/curriculum_day_model.dart';

/// 기간 내 평일(주말 제외) 기준 일수 초안 생성
List<CurriculumDayModel> generateCurriculumDayDrafts({
  required DateTime startDate,
  required DateTime endDate,
  String defaultSubject = '',
  bool skipWeekends = true,
}) {
  final days = <CurriculumDayModel>[];
  var current = DateTime(startDate.year, startDate.month, startDate.day);
  final end = DateTime(endDate.year, endDate.month, endDate.day);
  var dayNumber = 1;

  while (!current.isAfter(end)) {
    if (skipWeekends &&
        (current.weekday == DateTime.saturday ||
            current.weekday == DateTime.sunday)) {
      current = current.add(const Duration(days: 1));
      continue;
    }

    days.add(
      CurriculumDayModel(
        id: 'draft-$dayNumber',
        dayNumber: dayNumber,
        classDate: current,
        subject: defaultSubject,
        content: '',
        published: false,
        order: dayNumber,
      ),
    );
    dayNumber++;
    current = current.add(const Duration(days: 1));
  }

  return days;
}
