import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../data/curriculum_repository.dart';
import '../models/curriculum_day_model.dart';
import '../models/curriculum_meta_model.dart';
import '../models/curriculum_progress_model.dart';
import '../models/curriculum_week_model.dart';

final curriculumMetaProvider =
    StreamProvider.autoDispose<CurriculumMetaModel?>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value(null);
  return ref.watch(curriculumRepositoryProvider).watchMeta(cohortId);
});

final curriculumDaysProvider =
    StreamProvider.autoDispose<List<CurriculumDayModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value([]);
  return ref.watch(curriculumRepositoryProvider).watchDays(cohortId);
});

final publishedCurriculumDaysProvider =
    Provider.autoDispose<List<CurriculumDayModel>>((ref) {
  final days = ref.watch(curriculumDaysProvider).asData?.value ?? [];
  final meta = ref.watch(curriculumMetaProvider).asData?.value;
  if (meta == null || !meta.published) return [];
  return days.where((d) => d.published).toList();
});

final curriculumDayProvider = StreamProvider.autoDispose
    .family<CurriculumDayModel?, String>((ref, dayId) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value(null);
  return ref.watch(curriculumRepositoryProvider).watchDay(cohortId, dayId);
});

// ── 주차 (레거시, 유지) ──

final curriculumWeeksProvider =
    StreamProvider.autoDispose<List<CurriculumWeekModel>>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value([]);
  return ref.watch(curriculumRepositoryProvider).watchWeeks(cohortId);
});

final publishedCurriculumWeeksProvider =
    Provider.autoDispose<List<CurriculumWeekModel>>((ref) {
  final weeks = ref.watch(curriculumWeeksProvider).asData?.value ?? [];
  final meta = ref.watch(curriculumMetaProvider).asData?.value;
  if (meta == null || !meta.published) return [];
  return weeks.where((w) => w.published).toList();
});

final curriculumWeekProvider = StreamProvider.autoDispose
    .family<CurriculumWeekModel?, String>((ref, weekId) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  if (cohortId == null) return Stream.value(null);
  return ref.watch(curriculumRepositoryProvider).watchWeek(cohortId, weekId);
});

// ── 진행률 ──

final curriculumProgressProvider =
    StreamProvider.autoDispose<CurriculumProgressModel>((ref) {
  final cohortId = ref.watch(effectiveCohortIdProvider);
  final uid = ref.watch(currentUserProvider).asData?.value?.uid;
  if (cohortId == null || uid == null) {
    return Stream.value(const CurriculumProgressModel());
  }
  return ref.watch(curriculumRepositoryProvider).watchProgress(cohortId, uid);
});

/// 오늘 수업 (일수 기준)
final currentCurriculumDayProvider =
    Provider.autoDispose<CurriculumDayModel?>((ref) {
  final days = ref.watch(publishedCurriculumDaysProvider);
  if (days.isEmpty) return null;

  final today = DateTime.now();
  for (final day in days) {
    if (day.isOnDate(today)) return day;
  }

  final sorted = days.toList()
    ..sort((a, b) => a.classDate.compareTo(b.classDate));
  final todayDate = DateTime(today.year, today.month, today.day);
  for (final day in sorted) {
    final d = DateTime(day.classDate.year, day.classDate.month, day.classDate.day);
    if (!d.isBefore(todayDate)) return day;
  }
  return sorted.last;
});

/// 오늘 날짜 기준 현재 주차 (레거시)
final currentCurriculumWeekProvider =
    Provider.autoDispose<CurriculumWeekModel?>((ref) {
  final weeks = ref.watch(publishedCurriculumWeeksProvider);
  if (weeks.isEmpty) return null;

  final today = DateTime.now();
  for (final week in weeks) {
    if (week.containsDate(today)) return week;
  }

  final sorted = weeks.toList()
    ..sort((a, b) => a.weekNumber.compareTo(b.weekNumber));
  return sorted.last;
});

/// 진행률 (0.0 ~ 1.0) — 일수 우선
final curriculumProgressRatioProvider = Provider.autoDispose<double>((ref) {
  final days = ref.watch(publishedCurriculumDaysProvider);
  final weeks = ref.watch(publishedCurriculumWeeksProvider);
  final progress = ref.watch(curriculumProgressProvider).asData?.value;
  if (progress == null) return 0;

  if (days.isNotEmpty) {
    final done = days.where((d) => progress.isDayCompleted(d.id)).length;
    return done / days.length;
  }
  if (weeks.isEmpty) return 0;
  final done = weeks.where((w) => progress.isWeekCompleted(w.id)).length;
  return done / weeks.length;
});
