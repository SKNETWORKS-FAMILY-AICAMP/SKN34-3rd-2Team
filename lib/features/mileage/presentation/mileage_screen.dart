import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../auth/providers/auth_providers.dart';
import '../../../shared/providers/lms_providers.dart';

/// 마일리지 — 잔액 + 거래 내역
class MileageScreen extends ConsumerWidget {
  const MileageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final transactions = ref.watch(mileageTransactionsProvider);

    return user.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (u) {
        if (u == null) return const SizedBox.shrink();
        return Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  const Text(
                    'MILEAGE',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_format(u.mileageBalance)} P',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '적립 내역',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            Expanded(
              child: transactions.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorView(message: e.toString()),
                data: (list) {
                  if (list.isEmpty) {
                    return const Center(child: Text('거래 내역이 없습니다'));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final tx = list[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            tx.amount >= 0 ? Icons.add_circle : Icons.remove_circle,
                            color: tx.amount >= 0 ? AppColors.success : AppColors.error,
                          ),
                          title: Text(tx.reason),
                          subtitle: Text(
                            tx.createdAt != null
                                ? AppDateUtils.formatDateTime(tx.createdAt!)
                                : '',
                          ),
                          trailing: Text(
                            '${tx.amount >= 0 ? '+' : ''}${_format(tx.amount)} P',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: tx.amount >= 0 ? AppColors.success : AppColors.error,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  String _format(int n) => n.abs().toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
}
