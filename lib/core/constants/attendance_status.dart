import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 일별 출석 상태 (관리자 수동 입력 · 추후 자동화)
abstract final class AttendanceStatus {
  static const present = 'present';
  static const late = 'late';
  static const absent = 'absent';
  static const officialLeave = 'officialLeave';
  static const earlyLeave = 'earlyLeave';

  static const all = [
    present,
    late,
    absent,
    officialLeave,
    earlyLeave,
  ];

  static const labels = {
    present: '출석',
    late: '지각',
    absent: '결석',
    officialLeave: '공가',
    earlyLeave: '조퇴',
  };

  static const colors = {
    present: AppColors.success,
    late: AppColors.warning,
    absent: AppColors.error,
    officialLeave: AppColors.info,
    earlyLeave: Color(0xFF7C3AED),
  };

  static String labelOf(String? status) =>
      labels[status] ?? status ?? '-';

  static Color colorOf(String? status) =>
      colors[status] ?? AppColors.border;

  /// legacy checkIn → 출석
  static String? normalize(String? status, {String? legacyType}) {
    if (status != null && status.isNotEmpty) return status;
    if (legacyType == 'checkIn') return present;
    return null;
  }
}
