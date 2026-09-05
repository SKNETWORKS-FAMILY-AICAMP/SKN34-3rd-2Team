import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../shared/models/notice_model.dart';
import 'board_ui.dart';

String noticeTimeAgo(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inDays > 6) return AppDateUtils.formatDateTime(dt);
  if (diff.inDays > 0) return '${diff.inDays}일 전';
  if (diff.inHours > 0) return '${diff.inHours}시간 전';
  if (diff.inMinutes > 0) return '${diff.inMinutes}분 전';
  return '방금';
}

/// 한 줄 컴팩트 공지 행 — [아이콘] [제목] [공지 · N분 전] [>]
class StudentNoticeRow extends StatelessWidget {
  const StudentNoticeRow({
    super.key,
    required this.notice,
    this.onTap,
  });

  final NoticeModel notice;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isFavorite = notice.isFavorite;
    final isDiscord = notice.isFromDiscord;

    final (icon, iconColor) = switch ((isFavorite, isDiscord)) {
      (true, _) => (Icons.star_rounded, BoardUi.favorite),
      (_, true) => (Icons.discord, BoardUi.discordChipText),
      _ => (Icons.campaign_outlined, AppColors.textSecondary),
    };

    final meta = [
      notice.displayLabel,
      if (notice.createdAt != null) noticeTimeAgo(notice.createdAt),
    ].where((s) => s.isNotEmpty).join(' · ');

    return Material(
      color: isFavorite ? const Color(0xFFFFFBEB) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  notice.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                meta,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textHint,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 컴팩트 공지 목록 (구분선 포함)
class StudentNoticeRowList extends StatelessWidget {
  const StudentNoticeRowList({
    super.key,
    required this.notices,
    required this.onTap,
    this.maxVisibleRows,
  });

  final List<NoticeModel> notices;
  final ValueChanged<NoticeModel> onTap;
  /// 지정 시 이 개수만큼만 박스 높이를 고정하고 내부 스크롤
  final int? maxVisibleRows;

  static const _rowHeight = 42.0;
  static const _dividerHeight = 1.0;

  double? get _maxHeight {
    if (maxVisibleRows == null || notices.length <= maxVisibleRows!) {
      return null;
    }
    final rows = maxVisibleRows!;
    return rows * _rowHeight + (rows - 1) * _dividerHeight;
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      for (var i = 0; i < notices.length; i++) ...[
        if (i > 0) const Divider(height: _dividerHeight, thickness: 1),
        SizedBox(
          height: _rowHeight,
          child: StudentNoticeRow(
            notice: notices[i],
            onTap: () => onTap(notices[i]),
          ),
        ),
      ],
    ];

    final listBody = _maxHeight != null
        ? SizedBox(
            height: _maxHeight,
            child: ListView(
              padding: EdgeInsets.zero,
              physics: const ClampingScrollPhysics(),
              children: children,
            ),
          )
        : Column(mainAxisSize: MainAxisSize.min, children: children);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: listBody,
    );
  }
}

/// 대시보드·목록용 컴팩트 공지 타일
class StudentNoticeTile extends StatelessWidget {
  const StudentNoticeTile({
    super.key,
    required this.notice,
    this.onTap,
    this.showChevron = true,
  });

  final NoticeModel notice;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final isFavorite = notice.isFavorite;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: isFavorite ? const Color(0xFFFFFBEB) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isFavorite ? BoardUi.favoriteBorder : AppColors.border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isFavorite ? 0.04 : 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NoticeIconBadge(notice: notice),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              notice.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (isFavorite) ...[
                            const SizedBox(width: 8),
                            const BoardMetaChip(
                              label: '중요',
                              variant: BoardMetaChipVariant.favorite,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        notice.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          BoardMetaChip(
                            label: notice.displayLabel,
                            variant: notice.isFromDiscord
                                ? BoardMetaChipVariant.discord
                                : BoardMetaChipVariant.neutral,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            noticeTimeAgo(notice.createdAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (showChevron) ...[
                  const SizedBox(width: 4),
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeIconBadge extends StatelessWidget {
  const _NoticeIconBadge({required this.notice});

  final NoticeModel notice;

  @override
  Widget build(BuildContext context) {
    final isFavorite = notice.isFavorite;
    final isDiscord = notice.isFromDiscord;

    final (bg, fg, icon) = switch ((isFavorite, isDiscord)) {
      (true, _) => (
          BoardUi.favoriteBadgeBg,
          BoardUi.favorite,
          Icons.star_rounded,
        ),
      (_, true) => (
          BoardUi.discordChipBg,
          BoardUi.discordChipText,
          Icons.discord,
        ),
      _ => (
          AppColors.primaryLight,
          AppColors.textSecondary,
          Icons.campaign_outlined,
        ),
    };

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: fg),
    );
  }
}

/// 공지 카드 — 학생·관리자 공용 (Figma 스타일)
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.notice,
    this.onTap,
    this.trailing,
    this.compact = false,
  });

  final NoticeModel notice;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (trailing == null) {
      return Padding(
        padding: EdgeInsets.only(bottom: compact ? 8 : 10),
        child: StudentNoticeTile(
          notice: notice,
          onTap: onTap,
          showChevron: false,
        ),
      );
    }

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 10 : 12),
      decoration: BoardUi.cardDecoration(
        isFavorite: notice.isFavorite,
        isDiscord: notice.isFromDiscord,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NoticeIconBadge(notice: notice),
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notice.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: compact ? 14 : 15,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (notice.isFavorite)
                            const BoardMetaChip(
                              label: '중요',
                              variant: BoardMetaChipVariant.favorite,
                            ),
                        ],
                      ),
                      SizedBox(height: compact ? 4 : 6),
                      Text(
                        notice.content,
                        maxLines: compact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 12 : 13,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 10),
                      Row(
                        children: [
                          BoardMetaChip(
                            label: notice.displayLabel,
                            variant: notice.isFromDiscord
                                ? BoardMetaChipVariant.discord
                                : BoardMetaChipVariant.neutral,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _metaLine(notice),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _metaLine(NoticeModel notice) {
    final parts = <String>[
      if (notice.authorName.isNotEmpty) notice.authorName,
      if (notice.createdAt != null) noticeTimeAgo(notice.createdAt),
    ];
    return parts.join(' · ');
  }
}

/// 공지 상세 보기
class NoticeDetailSheet extends StatelessWidget {
  const NoticeDetailSheet({super.key, required this.notice});

  final NoticeModel notice;

  static Future<void> show(BuildContext context, NoticeModel notice) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => NoticeDetailSheet(notice: notice),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NoticeIconBadge(notice: notice),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notice.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (notice.isFavorite)
                              const BoardMetaChip(
                                label: '중요 공지',
                                variant: BoardMetaChipVariant.favorite,
                              ),
                            BoardMetaChip(
                              label: notice.displayLabel,
                              variant: notice.isFromDiscord
                                  ? BoardMetaChipVariant.discord
                                  : BoardMetaChipVariant.neutral,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${notice.authorName}'
                '${notice.createdAt != null ? ' · ${AppDateUtils.formatDateTime(notice.createdAt!)}' : ''}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 20),
              Text(
                notice.content,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.8,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
