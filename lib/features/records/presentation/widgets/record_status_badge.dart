import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class RecordStatusBadge extends StatelessWidget {
  const RecordStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'approved' => ('승인', const Color(0xFFDCFCE7), AppColors.success),
      'rejected' => ('반려', const Color(0xFFFEE2E2), AppColors.error),
      _ => ('대기', const Color(0xFFFEF3C7), AppColors.warning),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
          height: 1.2,
        ),
      ),
    );
  }
}
