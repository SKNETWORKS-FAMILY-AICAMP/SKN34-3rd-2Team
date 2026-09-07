import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/mileage_constants.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_widgets.dart';
import '../../../shared/providers/cohort_providers.dart';
import '../../../shared/providers/mileage_providers.dart';
import '../theme/mileage_theme.dart';

/// 마일리지 장바구니 → 구매 요청
class MileageCartScreen extends ConsumerStatefulWidget {
  const MileageCartScreen({super.key});

  @override
  ConsumerState<MileageCartScreen> createState() => _MileageCartScreenState();
}

class _MileageCartScreenState extends ConsumerState<MileageCartScreen> {
  bool _submitting = false;

  Future<void> _submit() async {
    final cohortId = ref.read(effectiveCohortIdProvider);
    final user = ref.read(currentUserSyncProvider);
    if (cohortId == null || user == null) return;

    setState(() => _submitting = true);
    try {
      await ref.read(mileageFunctionsServiceProvider).submitPurchaseRequest(
            cohortId: cohortId,
          );

      ref.read(mileageMainTabProvider.notifier).showRequests();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('구매 요청이 접수되었습니다.')),
      );
      context.go(RoutePaths.mileage);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('요청 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _removeItem(int index) async {
    final cohortId = ref.read(effectiveCohortIdProvider);
    final user = ref.read(currentUserSyncProvider);
    if (cohortId == null || user == null) return;

    final cart = ref.read(mileageCartProvider).value;
    if (cart == null) return;

    final items = [...cart.items]..removeAt(index);
    await ref.read(mileageRepositoryProvider).saveMileageCart(
          cohortId: cohortId,
          userId: user.uid,
          items: items,
        );
  }

  @override
  Widget build(BuildContext context) {
    final cartAsync = ref.watch(mileageCartProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('장바구니'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: cartAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (cart) {
          if (cart.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('장바구니가 비어 있습니다.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: mileagePrimaryButtonStyle(),
                    onPressed: () => context.pop(),
                    child: const Text('교환소로 돌아가기'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: cart.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final item = cart.items[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        item.productName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${MileageCategories.labelOf(item.category)} · '
                            '수량 ${item.quantity}',
                          ),
                          if (item.purchaseLink != null &&
                              item.purchaseLink!.isNotEmpty)
                            Text(
                              item.purchaseLink!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatMileageM(item.subtotal),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppColors.error),
                            onPressed: () => _removeItem(i),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '합계',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          formatMileageM(cart.totalAmount),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: MileageColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      style: mileagePrimaryButtonStyle(minHeight: 40),
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('구매 요청하기'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
