import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/mileage_constants.dart';
import '../../../core/constants/record_types.dart';
import '../../../core/routing/route_paths.dart';
import '../../../shared/models/mileage_models.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/mileage_providers.dart';
import '../../mileage/theme/mileage_theme.dart';
import 'widgets/admin_page_layout.dart';

/// 관리자 — 마일리지 기수 설정 (한도 · 자동 적립)
class AdminMileageSettingsScreen extends ConsumerStatefulWidget {
  const AdminMileageSettingsScreen({super.key});

  @override
  ConsumerState<AdminMileageSettingsScreen> createState() =>
      _AdminMileageSettingsScreenState();
}

class _AdminMileageSettingsScreenState
    extends ConsumerState<AdminMileageSettingsScreen> {
  final _gifticonLimit = TextEditingController();
  final _bookLimit = TextEditingController();
  final _courseLimit = TextEditingController();
  final _certAccrual = TextEditingController();
  final _studyAccrual = TextEditingController();
  final _blogAccrual = TextEditingController();

  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _gifticonLimit.dispose();
    _bookLimit.dispose();
    _courseLimit.dispose();
    _certAccrual.dispose();
    _studyAccrual.dispose();
    _blogAccrual.dispose();
    super.dispose();
  }

  void _load(MileageSettingsModel settings) {
    if (_loaded) return;
    _loaded = true;
    _gifticonLimit.text =
        settings.limitFor(MileageCategories.gifticon).toString();
    _bookLimit.text = settings.limitFor(MileageCategories.book).toString();
    _courseLimit.text =
        settings.limitFor(MileageCategories.onlineCourse).toString();
    _certAccrual.text = settings.accrualFor(RecordTypes.certification).toString();
    _studyAccrual.text = settings.accrualFor(RecordTypes.study).toString();
    _blogAccrual.text = settings.accrualFor(RecordTypes.blog).toString();
  }

  int _parseInt(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim()) ?? fallback;

  Future<void> _save() async {
    final cohortId = ref.read(effectiveCohortIdProvider);
    final user = ref.read(currentUserSyncProvider);
    if (cohortId == null || user == null) return;

    setState(() => _saving = true);
    try {
      final settings = MileageSettingsModel(
        categoryLimits: {
          MileageCategories.gifticon: _parseInt(_gifticonLimit, 200000),
          MileageCategories.book: _parseInt(_bookLimit, 100000),
          MileageCategories.onlineCourse: _parseInt(_courseLimit, 200000),
        },
        accrualRules: {
          RecordTypes.certification: _parseInt(_certAccrual, 5000),
          RecordTypes.study: _parseInt(_studyAccrual, 3000),
          RecordTypes.blog: _parseInt(_blogAccrual, 2000),
        },
      );

      await ref.read(mileageRepositoryProvider).saveMileageSettings(
            cohortId,
            settings,
            updatedBy: user.uid,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('설정이 저장되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(mileageSettingsProvider);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (settings) {
        _load(settings);

        return adminPageWrapper(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => context.go(RoutePaths.adminMileage),
                      icon: const Icon(Icons.arrow_back, size: 20),
                    ),
                    const Text(
                      '기수 설정',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AdminFormSection(
                  title: '카테고리별 사용 한도 (기수 전체 동일)',
                  children: [
                    _LimitField(
                      label: '기프티콘 한도 (M)',
                      controller: _gifticonLimit,
                    ),
                    _LimitField(
                      label: '도서 한도 (M)',
                      controller: _bookLimit,
                    ),
                    _LimitField(
                      label: '인터넷 강의 한도 (M)',
                      controller: _courseLimit,
                    ),
                  ],
                ),
                AdminFormSection(
                  title: '기록실 승인 시 자동 적립 (M)',
                  children: [
                    _LimitField(
                      label: '자격증 (${RecordTypes.labels[RecordTypes.certification]})',
                      controller: _certAccrual,
                    ),
                    _LimitField(
                      label: '스터디 (${RecordTypes.labels[RecordTypes.study]})',
                      controller: _studyAccrual,
                    ),
                    _LimitField(
                      label: '블로그 (${RecordTypes.labels[RecordTypes.blog]})',
                      controller: _blogAccrual,
                    ),
                  ],
                ),
                FilledButton(
                  style: mileagePrimaryButtonStyle(minHeight: 40),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('설정 저장'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LimitField extends StatelessWidget {
  const _LimitField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
