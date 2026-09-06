import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/student_intake_model.dart';
import '../providers/student_admin_providers.dart';
import 'widgets/admin_page_layout.dart';

/// 관리자 — 등록 학생 목록 (재원 / 퇴소 탭)
class AdminStudentsScreen extends ConsumerStatefulWidget {
  const AdminStudentsScreen({super.key});

  @override
  ConsumerState<AdminStudentsScreen> createState() =>
      _AdminStudentsScreenState();
}

class _AdminStudentsScreenState extends ConsumerState<AdminStudentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final intakes = ref.watch(cohortStudentIntakesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('학생 관리'),
        bottom: TabBar(
          controller: _tabController,
          tabs: intakes.maybeWhen(
            data: (list) {
              final active = list.where((s) => s.isActive).length;
              final inactive = list.length - active;
              return [
                Tab(text: '재원 ($active)'),
                Tab(text: '퇴소 ($inactive)'),
              ];
            },
            orElse: () => const [
              Tab(text: '재원'),
              Tab(text: '퇴소'),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: () => context.push(RoutePaths.adminStudentsCreate),
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('상담 등록'),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(cohortStudentIntakesProvider),
        child: intakes.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(message: e.toString()),
          data: (list) {
            final activeList =
                list.where((s) => s.isActive).toList(growable: false);
            final inactiveList =
                list.where((s) => !s.isActive).toList(growable: false);

            return TabBarView(
              controller: _tabController,
              children: [
                _StudentList(
                  students: activeList,
                  emptyMessage: '등록된 학생이 없습니다',
                  showCreateButton: true,
                ),
                _StudentList(
                  students: inactiveList,
                  emptyMessage: '퇴소 처리된 학생이 없습니다',
                  showCreateButton: false,
                  isInactive: true,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StudentList extends StatelessWidget {
  const _StudentList({
    required this.students,
    required this.emptyMessage,
    required this.showCreateButton,
    this.isInactive = false,
  });

  final List<StudentIntakeModel> students;
  final String emptyMessage;
  final bool showCreateButton;
  final bool isInactive;

  @override
  Widget build(BuildContext context) {
    if (students.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          adminPageWrapper(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 64),
              child: Column(
                children: [
                  Icon(
                    isInactive
                        ? Icons.person_off_outlined
                        : Icons.groups_outlined,
                    size: 48,
                    color: AppColors.textHint.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    emptyMessage,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  if (showCreateButton) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.push(RoutePaths.adminStudentsCreate),
                      icon: const Icon(Icons.person_add),
                      label: const Text('첫 학생 상담 등록'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: students.length,
          itemBuilder: (_, i) {
            final s = students[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              color: isInactive ? const Color(0xFFF8F9FA) : null,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isInactive
                      ? const Color(0xFFE5E7EB)
                      : AppColors.primaryLight,
                  child: Text(
                    s.displayName.isNotEmpty ? s.displayName[0] : '?',
                    style: TextStyle(
                      color: isInactive
                          ? AppColors.textSecondary
                          : AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  s.displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isInactive ? AppColors.textSecondary : null,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.email,
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (s.createdAt != null)
                      Text(
                        '등록: ${AppDateUtils.formatDisplay(s.createdAt!)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
                trailing: isInactive
                    ? const Chip(
                        label: Text('퇴소', style: TextStyle(fontSize: 10)),
                        visualDensity: VisualDensity.compact,
                      )
                    : s.passwordChanged
                        ? const Chip(
                            label:
                                Text('PW 변경됨', style: TextStyle(fontSize: 10)),
                            visualDensity: VisualDensity.compact,
                          )
                        : const Icon(Icons.chevron_right),
                onTap: () =>
                    context.push(RoutePaths.adminStudentDetailPath(s.uid)),
              ),
            );
          },
        ),
      ),
    );
  }
}
