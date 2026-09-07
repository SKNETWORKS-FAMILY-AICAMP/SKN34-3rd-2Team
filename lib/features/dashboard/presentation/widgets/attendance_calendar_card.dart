import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../core/constants/attendance_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/providers/cohort_providers.dart';
import '../../../../shared/providers/lms_providers.dart';

/// 대시보드 출석 캘린더 — 상태 색상 (외출 포함)
class AttendanceCalendarCard extends ConsumerStatefulWidget {
  const AttendanceCalendarCard({
    super.key,
    required this.user,
    this.compact = false,
  });

  final UserModel user;
  final bool compact;

  @override
  ConsumerState<AttendanceCalendarCard> createState() =>
      _AttendanceCalendarCardState();
}

class _AttendanceCalendarCardState extends ConsumerState<AttendanceCalendarCard> {
  DateTime _focusedDay = DateTime.now();
  CalendarFormat _format = CalendarFormat.month;

  String get _targetUserId {
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) return widget.user.uid;
    final selected = ref.watch(adminAttendanceTargetUserIdProvider);
    if (selected != null) return selected;
    final students = ref.watch(cohortStudentsProvider).asData?.value;
    if (students != null && students.isNotEmpty) return students.first.uid;
    return widget.user.uid;
  }

  String get _targetDisplayName {
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) return widget.user.displayName;
    final students = ref.watch(cohortStudentsProvider).asData?.value ?? [];
    return students
            .where((s) => s.uid == _targetUserId)
            .map((s) => s.displayName)
            .firstOrNull ??
        widget.user.displayName;
  }

  Future<void> _onAdminSetStatus(DateTime day, String? current) async {
    final cohortId = ref.read(effectiveCohortIdProvider);
    if (cohortId == null) return;

    final picked = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppDateUtils.toDateKey(day)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...AttendanceStatus.all.map(
              (s) => ListTile(
                leading: CircleAvatar(
                  radius: 8,
                  backgroundColor: AttendanceStatus.colorOf(s),
                ),
                title: Text(AttendanceStatus.labelOf(s)),
                onTap: () => Navigator.pop(ctx, s),
              ),
            ),
            if (current != null)
              ListTile(
                leading: const Icon(Icons.clear, size: 18),
                title: const Text('기록 삭제'),
                onTap: () => Navigator.pop(ctx, '__clear__'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );

    if (picked == null || !mounted) return;

    try {
      if (picked == '__clear__') {
        await ref.read(lmsRepositoryProvider).clearAttendanceStatus(
              cohortId: cohortId,
              userId: _targetUserId,
              dateKey: AppDateUtils.toDateKey(day),
            );
      } else {
        await ref.read(lmsRepositoryProvider).upsertAttendanceStatus(
              cohortId: cohortId,
              userId: _targetUserId,
              userDisplayName: _targetDisplayName,
              dateKey: AppDateUtils.toDateKey(day),
              status: picked,
            );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('출석 상태가 저장되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final statusMapAsync = ref.watch(attendanceStatusMapProvider(_targetUserId));
    final statusMap = statusMapAsync.asData?.value ?? {};
    final monthLabel =
        '${_focusedDay.year}.${_focusedDay.month.toString().padLeft(2, '0')}';
    final compact = widget.compact;

    return Material(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 10 : 14,
          compact ? 10 : 14,
          compact ? 10 : 14,
          compact ? 8 : 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  '출석',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                if (isAdmin && !compact)
                  ref.watch(cohortStudentsProvider).when(
                        loading: () => const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (students) {
                          if (students.isEmpty) return const SizedBox.shrink();
                          return DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: students.any((s) => s.uid == _targetUserId)
                                  ? _targetUserId
                                  : students.first.uid,
                              isDense: true,
                              style: const TextStyle(fontSize: 11),
                              items: students
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s.uid,
                                      child: Text(
                                        s.displayName,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (uid) {
                                if (uid != null) {
                                  ref
                                      .read(adminAttendanceTargetUserIdProvider
                                          .notifier)
                                      .select(uid);
                                }
                              },
                            ),
                          );
                        },
                      ),
              ],
            ),
            if (isAdmin && compact) ...[
              const SizedBox(height: 6),
              ref.watch(cohortStudentsProvider).when(
                    loading: () => const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (students) {
                      if (students.isEmpty) return const SizedBox.shrink();
                      return DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: students.any((s) => s.uid == _targetUserId)
                              ? _targetUserId
                              : students.first.uid,
                          isExpanded: true,
                          isDense: true,
                          style: const TextStyle(fontSize: 11),
                          items: students
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s.uid,
                                  child: Text(
                                    s.displayName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (uid) {
                            if (uid != null) {
                              ref
                                  .read(
                                    adminAttendanceTargetUserIdProvider.notifier,
                                  )
                                  .select(uid);
                            }
                          },
                        ),
                      );
                    },
                  ),
            ],
            if (statusMapAsync.hasError) ...[
              const SizedBox(height: 8),
              Text(
                '출석 불러오기 실패: ${statusMapAsync.error}',
                style: const TextStyle(fontSize: 11, color: AppColors.error),
              ),
            ],
            SizedBox(height: compact ? 4 : 8),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => setState(() {
                    _focusedDay = DateTime(
                      _focusedDay.year,
                      _focusedDay.month - 1,
                    );
                  }),
                ),
                Expanded(
                  child: Text(
                    monthLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (!compact)
                  TextButton(
                    onPressed: () => setState(() {
                      _format = _format == CalendarFormat.month
                          ? CalendarFormat.twoWeeks
                          : CalendarFormat.month;
                    }),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _format == CalendarFormat.month ? 'Month' : '2 weeks',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => setState(() {
                    _focusedDay = DateTime(
                      _focusedDay.year,
                      _focusedDay.month + 1,
                    );
                  }),
                ),
              ],
            ),
            TableCalendar<void>(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: _format,
              availableCalendarFormats: const {
                CalendarFormat.month: 'Month',
                CalendarFormat.twoWeeks: '2 weeks',
              },
              onFormatChanged: (f) => setState(() => _format = f),
              headerVisible: false,
              daysOfWeekHeight: compact ? 18 : 24,
              rowHeight: compact ? 26 : 34,
              onPageChanged: (focused) => setState(() => _focusedDay = focused),
              onDaySelected: (selected, focused) {
                setState(() => _focusedDay = focused);
                if (isAdmin) {
                  final key = _dateKeyOf(selected);
                  _onAdminSetStatus(selected, statusMap[key]);
                } else {
                  final key = _dateKeyOf(selected);
                  final s = statusMap[key];
                  if (s != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${AttendanceStatus.labelOf(s)} ($key)',
                        ),
                      ),
                    );
                  }
                }
              },
              calendarStyle: CalendarStyle(
                outsideDaysVisible: !compact,
                defaultTextStyle: TextStyle(fontSize: compact ? 11 : 12),
                weekendTextStyle: TextStyle(fontSize: compact ? 11 : 12),
                outsideTextStyle: TextStyle(
                  fontSize: compact ? 11 : 12,
                  color: AppColors.textHint,
                ),
                todayDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.textPrimary, width: 1.5),
                ),
                todayTextStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                selectedDecoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                selectedTextStyle: const TextStyle(color: Colors.white),
              ),
              calendarBuilders: CalendarBuilders(
                // today/selected보다 우선 — 출석 색이 항상 보이게
                prioritizedBuilder: (context, day, focusedDay) {
                  return _statusDayCell(
                    day: day,
                    statusMap: statusMap,
                    compact: compact,
                  );
                },
              ),
            ),
            SizedBox(height: compact ? 4 : 6),
            _AttendanceStatusLegend(compact: compact),
          ],
        ),
      ),
    );
  }

  static String _dateKeyOf(DateTime day) =>
      AppDateUtils.toDateKey(DateTime(day.year, day.month, day.day));

  static Widget? _statusDayCell({
    required DateTime day,
    required Map<String, String> statusMap,
    required bool compact,
  }) {
    final key = _dateKeyOf(day);
    final status = statusMap[key];
    if (status == null) return null;

    final color = AttendanceStatus.colorOf(status);
    final isToday = isSameDay(day, DateTime.now());
    return Container(
      margin: EdgeInsets.all(compact ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(
          color: isToday ? AppColors.textPrimary : color,
          width: isToday ? 1.5 : 1.4,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '${day.day}',
        style: TextStyle(
          fontSize: compact ? 10 : 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _AttendanceStatusLegend extends StatelessWidget {
  const _AttendanceStatusLegend({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: compact ? 6 : 10,
      runSpacing: compact ? 4 : 4,
      children: AttendanceStatus.all.map((s) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 7 : 8,
              height: compact ? 7 : 8,
              decoration: BoxDecoration(
                color: AttendanceStatus.colorOf(s),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              AttendanceStatus.labelOf(s),
              style: TextStyle(
                fontSize: compact ? 9 : 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}
