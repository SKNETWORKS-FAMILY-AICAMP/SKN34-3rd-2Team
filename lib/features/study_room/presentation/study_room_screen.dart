import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../auth/providers/auth_providers.dart';
import 'widgets/inflearn_package_card.dart';
import 'widgets/study_room_layout.dart';

/// 학습실 — 배정된 인프런 강의 패키지 (학생)
class StudyRoomScreen extends ConsumerStatefulWidget {
  const StudyRoomScreen({super.key});

  @override
  ConsumerState<StudyRoomScreen> createState() => _StudyRoomScreenState();
}

class _StudyRoomScreenState extends ConsumerState<StudyRoomScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final cohortName = ref.watch(effectiveCohortNameProvider);
    final packages = ref.watch(publishedInflearnPackagesProvider);

    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (user) {
        if (user == null) return const SizedBox.shrink();

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(publishedInflearnPackagesProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: studyRoomContentWrapper(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StudyRoomPageHeader(
                    user: user,
                    cohortName: cohortName,
                    subtitle: '배정된 인프런 강의를 확인하고 학습하세요.',
                  ),
                  const SizedBox(height: 20),
                  StudyRoomSearchBar(
                    controller: _searchController,
                    hintText: '교과목·강의명 검색',
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                  const SizedBox(height: 20),
                  packages.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => ErrorView(message: e.toString()),
                    data: (list) {
                      final filtered = list.where((p) {
                        if (_query.isEmpty) return true;
                        final q = _query.toLowerCase();
                        if (p.title.toLowerCase().contains(q)) return true;
                        if (p.subject.toLowerCase().contains(q)) return true;
                        if (p.summary?.toLowerCase().contains(q) ?? false) {
                          return true;
                        }
                        for (final unit in p.units) {
                          if (unit.name.toLowerCase().contains(q)) return true;
                          for (final c in unit.courses) {
                            if (c.title.toLowerCase().contains(q)) return true;
                          }
                        }
                        for (final c in p.courses) {
                          if (c.title.toLowerCase().contains(q)) return true;
                        }
                        return false;
                      }).toList();

                      if (filtered.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.menu_book_outlined,
                                  size: 48,
                                  color: AppColors.textHint,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  '배정된 인프런 강의가 없습니다',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  '강의 배정 후 이곳에 표시됩니다.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textHint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return Column(
                        children: [
                          for (final p in filtered) ...[
                            InflearnPackageCard(package: p),
                            const SizedBox(height: 16),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
