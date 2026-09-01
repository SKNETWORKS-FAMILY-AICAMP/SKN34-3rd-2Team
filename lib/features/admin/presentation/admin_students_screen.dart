import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../providers/student_admin_providers.dart';
import 'widgets/admin_page_layout.dart';

/// 관리자 — 등록 학생 목록
class AdminStudentsScreen extends ConsumerWidget {
  const AdminStudentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intakes = ref.watch(cohortStudentIntakesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('학생 관리'),
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
            if (list.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  adminPageWrapper(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 64),
                      child: Column(
                        children: [
                          Icon(
                            Icons.groups_outlined,
                            size: 48,
                            color: AppColors.textHint.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '등록된 학생이 없습니다',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () =>
                                context.push(RoutePaths.adminStudentsCreate),
                            icon: const Icon(Icons.person_add),
                            label: const Text('첫 학생 상담 등록'),
                          ),
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
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final s = list[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFE9D5FF),
                        child: Text(
                          s.displayName.isNotEmpty ? s.displayName[0] : '?',
                          style: const TextStyle(
                            color: Color(0xFF7C3AED),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        s.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
                      trailing: s.passwordChanged
                          ? const Chip(
                              label: Text('PW 변경됨', style: TextStyle(fontSize: 10)),
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
          },
        ),
      ),
    );
  }
}
