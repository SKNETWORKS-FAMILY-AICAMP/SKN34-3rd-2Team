import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/mileage_constants.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/models/mileage_models.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/lms_providers.dart';
import '../../../shared/providers/mileage_providers.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../auth/providers/auth_providers.dart';
import '../theme/mileage_theme.dart';
import 'widgets/mileage_widgets.dart';

/// 마일리지 메인 — 카드 + 내역/구매요청 탭
class MileageScreen extends ConsumerStatefulWidget {
  const MileageScreen({super.key});

  @override
  ConsumerState<MileageScreen> createState() => _MileageScreenState();
}

class _MileageScreenState extends ConsumerState<MileageScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  bool _usePresetMonth = true;

  @override
  void initState() {
    super.initState();
    _applyMonthPreset();
  }

  void _applyMonthPreset() {
    final now = DateTime.now();
    _endDate = DateTime(now.year, now.month, now.day);
    _startDate = DateTime(now.year, now.month - 1, now.day);
    _usePresetMonth = true;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
      _usePresetMonth = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final cohortName = ref.watch(effectiveCohortNameProvider);
    final cohortEnd = ref.watch(effectiveCohortEndDateProvider);
    final tabIndex = ref.watch(mileageMainTabProvider);

    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (user) {
        if (user == null) return const SizedBox.shrink();

        return MileagePageScroll(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MileagePageHeader(user: user, cohortName: cohortName),
              const SizedBox(height: MileageLayout.sectionGap),
              MileageCreditCard(
                balance: user.mileageBalance,
                holderName: user.displayName,
                validThru: cohortEnd?.add(const Duration(days: 14)),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MileageLayout.pagePaddingH,
                ),
                child: Text(
                  cohortEnd != null
                      ? '모든 마일리지는 종강일(${AppDateUtils.formatDisplay(cohortEnd)}) '
                          '기준 2주까지 사용 가능하며, 이후 자동 소멸됩니다.'
                      : '모든 마일리지는 종강일 기준 2주까지 사용 가능하며, 이후 자동 소멸됩니다.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: MileageLayout.sectionGap),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MileageLayout.pagePaddingH,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    style: mileagePrimaryButtonStyle(),
                    onPressed: () => context.push(RoutePaths.mileageShop),
                    icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                    label: const Text('마일리지 사용하기'),
                  ),
                ),
              ),
              const SizedBox(height: MileageLayout.sectionGap),
              MileageSegmentTabs(
                tabs: const ['마일리지 내역', '구매 요청'],
                selectedIndex: tabIndex,
                onSelected: (i) =>
                    ref.read(mileageMainTabProvider.notifier).select(i),
              ),
              const SizedBox(height: MileageLayout.sectionGap),
              if (tabIndex == 0)
                _HistoryTab(
                  startDate: _startDate,
                  endDate: _endDate,
                  usePresetMonth: _usePresetMonth,
                  onPickStart: () => _pickDate(isStart: true),
                  onPickEnd: () => _pickDate(isStart: false),
                  onPresetMonth: () => setState(_applyMonthPreset),
                  onPresetAll: () => setState(() {
                    _startDate = null;
                    _endDate = null;
                    _usePresetMonth = false;
                  }),
                  presetMonthSelected: _usePresetMonth,
                  presetAllSelected: !_usePresetMonth && _startDate == null,
                )
              else
                const _PurchaseRequestsTab(),
            ],
          ),
        );
      },
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({
    required this.startDate,
    required this.endDate,
    required this.usePresetMonth,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onPresetMonth,
    required this.onPresetAll,
    required this.presetMonthSelected,
    required this.presetAllSelected,
  });

  final DateTime? startDate;
  final DateTime? endDate;
  final bool usePresetMonth;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onPresetMonth;
  final VoidCallback onPresetAll;
  final bool presetMonthSelected;
  final bool presetAllSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(mileageTransactionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MileageDateFilterBar(
          startDate: startDate,
          endDate: endDate,
          onPickStart: onPickStart,
          onPickEnd: onPickEnd,
          onPresetMonth: onPresetMonth,
          onPresetAll: onPresetAll,
          presetMonthSelected: presetMonthSelected,
          presetAllSelected: presetAllSelected,
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        transactionsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorView(message: e.toString()),
          data: (list) {
            final filtered = list.where((tx) {
              if (startDate == null && endDate == null) return true;
              final created = tx.createdAt;
              if (created == null) return true;
              if (startDate != null && created.isBefore(startDate!)) {
                return false;
              }
              if (endDate != null) {
                final end = DateTime(
                  endDate!.year,
                  endDate!.month,
                  endDate!.day,
                  23,
                  59,
                  59,
                );
                if (created.isAfter(end)) return false;
              }
              return true;
            }).toList();

            if (filtered.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('거래 내역이 없습니다')),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(MileageLayout.pagePaddingH),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 20),
              itemBuilder: (_, i) {
                final tx = filtered[i];
                final isDebit = tx.amount < 0;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 88,
                      child: Text(
                        tx.createdAt != null
                            ? AppDateUtils.formatDisplay(tx.createdAt!)
                            : '-',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 96,
                      child: Text(
                        formatMileageSigned(tx.amount),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDebit
                              ? AppColors.error
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        tx.reason,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _PurchaseRequestsTab extends ConsumerStatefulWidget {
  const _PurchaseRequestsTab();

  @override
  ConsumerState<_PurchaseRequestsTab> createState() =>
      _PurchaseRequestsTabState();
}

class _PurchaseRequestsTabState extends ConsumerState<_PurchaseRequestsTab> {
  String _statusFilter = 'all';
  String _categoryFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(myPurchaseRequestsProvider);

    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (requests) {
        final pending = requests.where((r) => r.status == PurchaseRequestStatus.pending).length;
        final approved = requests.where((r) => r.status == PurchaseRequestStatus.approved).length;
        final other = requests.where((r) =>
            r.status == PurchaseRequestStatus.modifyRequested ||
            r.status == PurchaseRequestStatus.rejected ||
            r.status == PurchaseRequestStatus.cancelled).length;

        var filtered = requests;
        if (_statusFilter != 'all') {
          filtered = filtered.where((r) => r.status == _statusFilter).toList();
        }
        if (_categoryFilter != 'all') {
          filtered = filtered
              .where((r) => r.items.any((i) => i.category == _categoryFilter))
              .toList();
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: MileageLayout.pagePaddingH),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SummaryCard(label: '전체 요청', count: requests.length),
                  _SummaryCard(label: '대기', count: pending),
                  _SummaryCard(label: '승인', count: approved),
                  _SummaryCard(label: '수정/반려/취소', count: other),
                ],
              ),
              const SizedBox(height: 12),
              MileageFilterChipRow(
                label: '상태',
                selected: _statusFilter,
                onSelected: (v) => setState(() => _statusFilter = v),
                options: const [
                  ('all', '전체'),
                  ('pending', '대기'),
                  ('approved', '승인'),
                  ('modify_requested', '수정 요청'),
                  ('rejected', '반려'),
                  ('cancelled', '취소'),
                ],
              ),
              const SizedBox(height: 8),
              MileageFilterChipRow(
                label: '상품 타입',
                selected: _categoryFilter,
                onSelected: (v) => setState(() => _categoryFilter = v),
                options: const [
                  ('all', '전체'),
                  ('gifticon', '기프티콘'),
                  ('book', '도서'),
                  ('onlineCourse', '인터넷 강의'),
                ],
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('구매 요청이 없습니다')),
                )
              else
                ...filtered.map(
                  (req) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PurchaseRequestCard(request: req),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            '$count건',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _PurchaseRequestCard extends ConsumerWidget {
  const _PurchaseRequestCard({required this.request});

  final PurchaseRequestModel request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = request.primaryCategory ?? MileageCategories.gifticon;
    final canCancel = request.status == PurchaseRequestStatus.pending ||
        request.status == PurchaseRequestStatus.modifyRequested;
    final totalQty =
        request.items.fold(0, (total, item) => total + item.quantity);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusBadge(
                label: request.statusLabel,
                color: MileageColors.statusColor(request.status),
              ),
              const SizedBox(width: 6),
              MileageTagChip(
                label: MileageCategories.labelOf(category),
                color: MileageColors.categoryTagColor(category),
              ),
              const Spacer(),
              if (request.createdAt != null)
                Text(
                  '신청일 ${AppDateUtils.formatDetailDateTime(request.createdAt!)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            request.primaryProductName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 12),
          _DetailGrid(
            items: [
              ('신청 금액', formatMileageM(request.totalAmount)),
              ('수량', '$totalQty개'),
              ('처리 일시', request.processedAt != null
                  ? AppDateUtils.formatDetailDateTime(request.processedAt!)
                  : '-'),
              ('처리자', request.processedByName ?? '-'),
              ('구매 링크', request.managerPurchaseLink ?? '-'),
              ('매니저 메모', request.managerMemo ?? '-'),
            ],
          ),
          if (canCancel) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                style: mileageOutlinedButtonStyle(),
                onPressed: () => _cancel(context, ref),
                child: const Text('취소'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final cohortId = ref.read(effectiveCohortIdProvider);
    if (cohortId == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('구매 요청 취소'),
        content: const Text('이 구매 요청을 취소할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('아니오')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('취소하기')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(mileageFunctionsServiceProvider).cancelPurchaseRequest(
            cohortId: cohortId,
            requestId: request.id,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('구매 요청이 취소되었습니다.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('취소 실패: $e')),
        );
      }
    }
  }
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth > 500 ? 3 : 2;
        return GridView.count(
          crossAxisCount: crossCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 12,
          childAspectRatio: 2.8,
          children: items.map((item) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.$1,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  item.$2,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          }).toList(),
        );
      },
    );
  }
}
