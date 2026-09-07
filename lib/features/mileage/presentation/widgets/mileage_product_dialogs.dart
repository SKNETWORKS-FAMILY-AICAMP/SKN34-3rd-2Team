import 'package:flutter/material.dart';

import '../../../../core/constants/mileage_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/mileage_models.dart';
import '../../theme/mileage_theme.dart';

/// 고정가 상품 — 수량 선택 후 장바구니
Future<void> showFixedProductDialog(
  BuildContext context, {
  required MileageProductModel product,
  required Future<void> Function(int quantity) onAdd,
}) async {
  var quantity = 1;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(product.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatMileageM(product.fixedPrice ?? 0),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: MileageColors.primary,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('수량'),
                const Spacer(),
                IconButton(
                  onPressed: quantity > 1
                      ? () => setState(() => quantity--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$quantity', style: const TextStyle(fontSize: 16)),
                IconButton(
                  onPressed: () => setState(() => quantity++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            style: mileagePrimaryButtonStyle(),
            onPressed: () async {
              Navigator.pop(ctx);
              await onAdd(quantity);
            },
            child: const Text('장바구니에 담기'),
          ),
        ],
      ),
    ),
  );
}

/// 인프런 / yes24 — 링크 + 가격 직접 입력
Future<void> showCustomProductDialog(
  BuildContext context, {
  required MileageProductModel product,
  required MileageCategoryUsageModel usage,
  required int mileageBalance,
  required Future<void> Function(String link, int price) onAdd,
}) async {
  final linkController = TextEditingController();
  final priceController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final linkHint = product.category == MileageCategories.onlineCourse
      ? 'https://www.inflearn.com/course/...'
      : 'https://www.yes24.com/...';

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              product.category == MileageCategories.onlineCourse
                  ? Icons.play_circle_outline
                  : Icons.menu_book_outlined,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(fontSize: 16),
                ),
                const Text(
                  '가격 직접 입력',
                  style: TextStyle(
                    color: MileageColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
      content: Form(
        key: formKey,
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MileageColors.infoBanner,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: MileageColors.infoBannerBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: AppColors.info),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${usage.categoryLabel} 잔여 한도: '
                        '${formatMileageM(usage.remaining)} / ${formatMileageM(usage.limit)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: linkController,
                decoration: InputDecoration(
                  labelText: product.category == MileageCategories.onlineCourse
                      ? '강의 링크'
                      : '도서 링크',
                  hintText: linkHint,
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return '링크를 입력해 주세요.';
                  if (!v.startsWith('http')) return '올바른 URL을 입력해 주세요.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '가격 (M)',
                  hintText: '예) 66000',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final price = int.tryParse(v?.trim() ?? '');
                  if (price == null || price <= 0) {
                    return '올바른 가격을 입력해 주세요.';
                  }
                  if (price > usage.remaining) {
                    return '카테고리 잔여 한도를 초과합니다.';
                  }
                  if (price > mileageBalance) {
                    return '마일리지 잔액이 부족합니다.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('취소'),
        ),
        FilledButton(
          style: mileagePrimaryButtonStyle(),
          onPressed: () async {
            if (!formKey.currentState!.validate()) return;
            final link = linkController.text.trim();
            final price = int.parse(priceController.text.trim());
            Navigator.pop(ctx);
            await onAdd(link, price);
          },
          child: const Text('장바구니에 담기'),
        ),
      ],
    ),
  );

  linkController.dispose();
  priceController.dispose();
}
