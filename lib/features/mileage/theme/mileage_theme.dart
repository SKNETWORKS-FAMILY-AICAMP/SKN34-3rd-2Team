import 'package:flutter/material.dart';

/// 마일리지 화면 전용 보라 accent
abstract final class MileageColors {
  static const primary = Color(0xFF6B21A8);
  static const primaryDark = Color(0xFF4C1D95);
  static const primaryLight = Color(0xFF9333EA);
  static const cardGradientStart = Color(0xFF5B21B6);
  static const cardGradientEnd = Color(0xFF312E81);
  static const chipBg = Color(0xFFF3E8FF);
  static const infoBanner = Color(0xFFEFF6FF);
  static const infoBannerBorder = Color(0xFFBFDBFE);

  static const gifticonTag = Color(0xFFEA580C);
  static const bookTag = Color(0xFF16A34A);
  static const courseTag = Color(0xFF7C3AED);

  static Color categoryTagColor(String category) => switch (category) {
        'gifticon' => gifticonTag,
        'book' => bookTag,
        'onlineCourse' => courseTag,
        _ => primary,
      };

  static Color statusColor(String status) => switch (status) {
        'approved' => const Color(0xFF16A34A),
        'pending' => const Color(0xFF2563EB),
        'modify_requested' => const Color(0xFFD97706),
        'rejected' => const Color(0xFFDC2626),
        'cancelled' => const Color(0xFF6B7280),
        _ => const Color(0xFF6B7280),
      };
}

/// 마일리지 화면 공통 레이아웃 상수
abstract final class MileageLayout {
  static const pagePaddingH = 20.0;
  static const sectionGap = 12.0;
  static const maxContentWidth = 720.0;
  static const cardHeight = 140.0;
  static const buttonHeight = 36.0;
}

ButtonStyle mileagePrimaryButtonStyle({double? minHeight}) {
  return FilledButton.styleFrom(
    backgroundColor: MileageColors.primary,
    foregroundColor: Colors.white,
    minimumSize: Size(0, minHeight ?? MileageLayout.buttonHeight),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

ButtonStyle mileageOutlinedButtonStyle({double? minHeight}) {
  return OutlinedButton.styleFrom(
    foregroundColor: MileageColors.primary,
    minimumSize: Size(0, minHeight ?? MileageLayout.buttonHeight),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

String formatMileageAmount(int n) =>
    n.abs().toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );

String formatMileageSigned(int n) {
  final prefix = n >= 0 ? '+ ' : '- ';
  return '$prefix${formatMileageAmount(n)} P';
}

String formatMileageM(int n) => '${formatMileageAmount(n)}M';
