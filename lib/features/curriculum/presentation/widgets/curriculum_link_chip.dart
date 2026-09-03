import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/cohort_providers.dart';
import '../../../../shared/providers/lms_providers.dart';
import '../../models/curriculum_link_model.dart';

class CurriculumLinkTile extends ConsumerWidget {
  const CurriculumLinkTile({
    super.key,
    required this.link,
    this.compact = false,
  });

  final CurriculumLinkModel link;
  final bool compact;

  (IconData, Color) _iconForType(CurriculumLinkType type) {
    return switch (type) {
      CurriculumLinkType.inflearnPackage => (Icons.menu_book, AppColors.info),
      CurriculumLinkType.formTask => (Icons.ballot_outlined, AppColors.warning),
      CurriculumLinkType.weeklyTask => (Icons.task_alt, AppColors.success),
      CurriculumLinkType.schedule => (Icons.calendar_today, AppColors.secondary),
      CurriculumLinkType.external => (Icons.open_in_new, AppColors.primary),
      CurriculumLinkType.recordType => (Icons.history, AppColors.secondary),
    };
  }

  String _resolveLabel(WidgetRef ref) {
    if (link.label.isNotEmpty) return link.label;
    final refId = link.refId;
    if (refId == null || refId.isEmpty) return link.type.label;

    switch (link.type) {
      case CurriculumLinkType.inflearnPackage:
        final isAdmin = ref.watch(isAdminProvider);
        final packages = isAdmin
            ? (ref.watch(inflearnPackagesProvider).asData?.value ?? [])
            : (ref.watch(publishedInflearnPackagesProvider).asData?.value ?? []);
        final pkg = packages.where((p) => p.id == refId).firstOrNull;
        return pkg?.title ?? '삭제된 항목';
      case CurriculumLinkType.formTask:
        final tasks = ref.watch(allFormTasksAdminProvider).asData?.value;
        if (tasks != null && tasks.isNotEmpty) {
          final task = tasks.where((t) => t.id == refId).firstOrNull;
          if (task != null) return task.title;
        }
        final withStatus =
            ref.watch(formTasksWithStatusProvider).asData?.value ?? [];
        final match = withStatus.where((t) => t.task.id == refId).firstOrNull;
        return match?.task.title ?? '삭제된 항목';
      default:
        return link.type.label;
    }
  }

  bool _isDeleted(WidgetRef ref) => _resolveLabel(ref) == '삭제된 항목';

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    if (_isDeleted(ref)) return;

    switch (link.type) {
      case CurriculumLinkType.inflearnPackage:
        context.go(RoutePaths.studyRoom);
      case CurriculumLinkType.formTask:
        context.go(RoutePaths.forms);
      case CurriculumLinkType.weeklyTask:
        context.go(RoutePaths.dashboard);
      case CurriculumLinkType.schedule:
        context.go(RoutePaths.dashboard);
      case CurriculumLinkType.recordType:
        context.go(RoutePaths.records);
      case CurriculumLinkType.external:
        final url = link.url;
        if (url == null || url.isEmpty) return;
        final uri = Uri.tryParse(url);
        if (uri == null) return;
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = _resolveLabel(ref);
    final deleted = label == '삭제된 항목';
    final (icon, color) = _iconForType(link.type);

    if (compact) {
      return ActionChip(
        avatar: Icon(icon, size: 16, color: deleted ? AppColors.textHint : color),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: deleted ? AppColors.textHint : AppColors.textPrimary,
          ),
        ),
        onPressed: deleted ? null : () => _onTap(context, ref),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: deleted ? AppColors.textHint : color, size: 20),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: deleted ? AppColors.textHint : AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          link.type.label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: deleted
            ? null
            : const Icon(Icons.chevron_right, color: AppColors.textHint),
        onTap: deleted ? null : () => _onTap(context, ref),
      ),
    );
  }
}
