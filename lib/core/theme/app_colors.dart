import 'package:flutter/material.dart';

/// 깔끔한 화이트 기반 컬러 팔레트
abstract final class AppColors {
  static const primary = Color(0xFF1A1A1A);
  static const primaryDark = Color(0xFF000000);
  static const primaryLight = Color(0xFFF3F4F6);
  static const secondary = Color(0xFF6B7280);

  static const background = Colors.white;
  static const surface = Colors.white;
  static const surfaceVariant = Color(0xFFF9FAFB);

  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const textHint = Color(0xFF9CA3AF);

  static const border = Color(0xFFE5E7EB);
  static const divider = Color(0xFFF3F4F6);

  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
  static const error = Color(0xFFDC2626);
  static const info = Color(0xFF2563EB);
}
