import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/attendance_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/domain_models.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';

/// 관리자 — 기수별 당일 출석 전체 조회/수정
class AdminAttendanceScreen extends ConsumerStatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  ConsumerState<AdminAttendanceScreen> createState() =>
      _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends ConsumerState<AdminAttendanceScreen> {
  DateTime _day = DateTime.now();
  String _query = '';
  bool _seeding = false;
  bool _ensuringNotice = false;

  String get _dateKey => AppDateUtils.toDateKey(_day);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _seedDemo() async {
    final cohortId = ref.read(effectiveCohortIdProvider);
    final students = ref.read(cohortStudentsProvider).asData?.value ?? [];
    if (cohortId == null) return;
    setState(() => _seeding = true);
    try {
      final n = await ref.read(lmsRepositoryProvider).seedDemoAttendances(
            cohortId: cohortId,
            dateKey: _dateKey,
            students: students,
          ) as int;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('예시 입퇴실 $n건을 반영했습니다. (폼·수동 기록은 유지)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('채우기 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _ensureNotice() async {
    final cohortId = ref.read(effectiveCohortIdProvider);
    final user = ref.read(currentUserSyncProvider);
    if (cohortId == null || user == null) return;
    setState(() => _ensuringNotice = true);
    try {
      final created =
          await ref.read(lmsRepositoryProvider).ensureDailyAttendanceFormNotice(
                cohortId: cohortId,
                authorId: user.uid,
                authorName: user.displayName,
              ) as bool;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            created
                ? '매일 08:30 LMS 출결 폼 공지를 등록했습니다.'
                : '이미 등록된 매일 08:30 출결 공지가 있습니다.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('공지 등록 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _ensuringNotice = false);
    }
  }

  Future<void> _setStatus({
    required UserModel student,
    required String status,
  }) async {
    final cohortId = ref.read(effectiveCohortIdProvider);
    if (cohortId == null) return;
    try {
      await ref.read(lmsRepositoryProvider).upsertAttendanceStatus(
            cohortId: cohortId,
            userId: student.uid,
            userDisplayName: student.displayName,
            dateKey: _dateKey,
            status: status,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cohortName = ref.watch(effectiveCohortNameProvider);
    final studentsAsync = ref.watch(cohortStudentsProvider);
    final attendancesAsync = ref.watch(attendancesByDateProvider(_dateKey));

    return Scaffold(
      appBar: AppBar(
        title: const Text('출석관리'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(AttendanceForm.url),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('출결 폼'),
            ),
          ),
        ],
      ),
      body: studentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (students) {
          final byUser = <String, AttendanceModel>{};
          for (final a in attendancesAsync.asData?.value ?? const []) {
            byUser[a.userId] = a;
          }
          final q = _query.trim();
          final filtered = students.where((s) {
            if (q.isEmpty) return true;
            return s.displayName.contains(q);
          }).toList()
            ..sort((a, b) => a.displayName.compareTo(b.displayName));

          final counts = <String, int>{
            for (final s in AttendanceStatus.all) s: 0,
            '_none': 0,
          };
          for (final s in students) {
            final status = byUser[s.uid]?.dayStatus;
            if (status == null || !AttendanceStatus.all.contains(status)) {
              counts['_none'] = (counts['_none'] ?? 0) + 1;
            } else {
              counts[status] = (counts[status] ?? 0) + 1;
            }
          }

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    cohortName ?? '기수를 먼저 선택하세요',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '고용24 입퇴실은 예시 데이터입니다. 지각·조퇴·외출·결석·공가는 당일 구글폼 선택값이 반영됩니다.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(_dateKey),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _day = DateTime.now()),
                        child: const Text('오늘'),
                      ),
                      FilledButton.icon(
                        onPressed: _seeding || students.isEmpty ? null : _seedDemo,
                        icon: _seeding
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.schedule, size: 16),
                        label: const Text('예시 입퇴실 채우기'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _ensuringNotice ? null : _ensureNotice,
                        icon: _ensuringNotice
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.campaign_outlined, size: 16),
                        label: const Text('매일 08:30 공지 등록'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CountChip(
                        label: '전체 ${students.length}',
                        color: AppColors.textPrimary,
                      ),
                      ...AttendanceStatus.all.map(
                        (s) => _CountChip(
                          label:
                              '${AttendanceStatus.labelOf(s)} ${counts[s] ?? 0}',
                          color: AttendanceStatus.colorOf(s),
                        ),
                      ),
                      _CountChip(
                        label: '미기록 ${counts['_none'] ?? 0}',
                        color: AppColors.textHint,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: '이름 검색',
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 12),
                  if (attendancesAsync.isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (attendancesAsync.hasError)
                    ErrorView(message: attendancesAsync.error.toString())
                  else if (students.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(
                          '이 기수에 재원 학생이 없습니다.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          AppColors.surfaceVariant,
                        ),
                        columns: const [
                          DataColumn(label: Text('이름')),
                          DataColumn(label: Text('입실')),
                          DataColumn(label: Text('퇴실')),
                          DataColumn(label: Text('폼')),
                          DataColumn(label: Text('최종 상태')),
                          DataColumn(label: Text('출처')),
                        ],
                        rows: [
                          for (final student in filtered)
                            _row(
                              student: student,
                              attendance: byUser[student.uid],
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  DataRow _row({
    required UserModel student,
    required AttendanceModel? attendance,
  }) {
    final status = attendance?.dayStatus;
    final value =
        AttendanceStatus.all.contains(status) ? status : null;
    return DataRow(
      cells: [
        DataCell(Text(student.displayName)),
        DataCell(Text(attendance?.checkInTime ?? '-')),
        DataCell(Text(attendance?.checkOutTime ?? '-')),
        DataCell(Text(attendance?.formSummary ?? '-')),
        DataCell(
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              hint: const Text('미기록', style: TextStyle(fontSize: 13)),
              isDense: true,
              items: [
                for (final s in AttendanceStatus.all)
                  DropdownMenuItem(
                    value: s,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AttendanceStatus.colorOf(s),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          AttendanceStatus.labelOf(s),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: (s) {
                if (s != null) _setStatus(student: student, status: s);
              },
            ),
          ),
        ),
        DataCell(Text(attendance?.sourceLabel ?? '-')),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
