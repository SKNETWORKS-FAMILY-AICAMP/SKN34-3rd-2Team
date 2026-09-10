import 'package:flutter/material.dart';

/// 코스모스 블루 톤 기반 라이트 UI 팔레트
abstract final class AppColors {
  static const primary = Color(0xFF0055FF);
  static const primaryDark = Color(0xFF0044CC);
  static const primaryLight = Color(0xFFE8F0FF);
  static const secondary = Color(0xFF6B7280);

  static const background = Color(0xFFF8F9FB);
  static const surface = Colors.white;
  static const surfaceVariant = Color(0xFFF3F5F9);

  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const textHint = Color(0xFF9CA3AF);

  static const border = Color(0xFFE5E7EB);
  static const divider = Color(0xFFF3F4F6);

  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFDC2626);
  static const info = Color(0xFF0055FF);

  /// 사이드바 / 네비 액센트 (레거시·마일리지 카드 등)
  static const sidebar = Color(0xFF0B2A6F);
  static const sidebarIconInactive = Color(0xFF94A3B8);

  /// 로그인·셸 다크 크롬 (시네마틱)
  static const cinematicBg = Color(0xFF05070F);
  static const cinematicSurface = Color(0xFF0B1224);
  static const cinematicBorder = Color(0xFF1E2538);
  static const cinematicAccent = Color(0xFF00C2D4);
  static const cinematicAccentAlt = Color(0xFF7B5CFF);
  static const cinematicMuted = Color(0xFF94A3B8);

  /// 상태 뱃지
  static const badgeOpen = Color(0xFF0055FF);
  static const badgeLate = Color(0xFFF59E0B);
  static const badgeClosed = Color(0xFF4B5563);

  /// 로그인 카드 그림자용
  static const shadow = Color(0x1A0F172A);
}
