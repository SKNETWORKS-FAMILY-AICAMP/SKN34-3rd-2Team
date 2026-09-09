import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../shared/models/resume_model.dart';
import '../../../../shared/providers/cohort_providers.dart';
import '../../../../shared/providers/lms_providers.dart';

/// 툴바의 종. 읽지 않은 피드백 수를 배지로 달고, 누르면 아래로 말풍선이 내려온다.
///
/// 말풍선은 **고르는 곳**이다. 누가 어느 항목에 남겼는지만 적고 내용은 보여 주지 않는다.
/// 내용은 항목을 눌러 뜨는 팝업에서 읽는다. 두 곳이 같은 글을 되풀이하지 않게 갈랐다.
///
/// 읽음은 **전문을 연 항목만** 넘어간다. 종을 열거나 배너를 닫는 것으로는 줄지 않는다.
/// 목록만 훑고 지나간 것을 읽었다고 세면, 정작 읽어야 할 말이 숫자와 함께 사라진다.
class FeedbackBell extends ConsumerStatefulWidget {
  const FeedbackBell({
    super.key,
    required this.resume,
    required this.onGoToSection,
  });

  final ResumeModel resume;

  /// 상세에서 "해당 항목으로 이동"을 눌렀을 때. 이력서를 그 섹션으로 굴린다.
  final ValueChanged<String> onGoToSection;

  @override
  ConsumerState<FeedbackBell> createState() => _FeedbackBellState();
}

class _FeedbackBellState extends ConsumerState<FeedbackBell> {
  final _link = LayerLink();
  OverlayEntry? _popover;

  @override
  void dispose() {
    _popover?.remove();
    super.dispose();
  }

  bool get _open => _popover != null;

  void _close() {
    _popover?.remove();
    _popover = null;
    if (mounted) setState(() {});
  }

  void _toggle(List<ResumeFeedbackModel> items) {
    if (_open) {
      _close();
      return;
    }
    final entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // 바깥을 누르면 닫힌다. 화면 전체를 덮되 어둡게 하지는 않는다.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: const SizedBox.shrink(),
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomCenter,
            followerAnchor: Alignment.topCenter,
            // 종 한가운데에서 꼬리가 나오되, 말풍선은 왼쪽으로 눕는다.
            offset: const Offset(_FeedbackPopover.followerDx, 6),
            showWhenUnlinked: false,
            child: _FeedbackPopover(
              items: items,
              readIds: widget.resume.readFeedbackIds.toSet(),
              onPick: (item) {
                _close();
                _openDetail(item);
              },
              onClose: _close,
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(entry);
    setState(() => _popover = entry);
  }

  Future<void> _openDetail(ResumeFeedbackModel item) async {
    // 전문을 연 순간이 읽음이다.
    final cohortId = ref.read(effectiveCohortIdProvider);
    if (cohortId != null && !ref.read(isAdminProvider)) {
      ref.read(lmsRepositoryProvider).markResumeFeedbackRead(
            cohortId: cohortId,
            resumeId: widget.resume.id,
            feedbackId: item.id,
          );
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => FeedbackDetailDialog(
        item: item,
        onGoToSection: widget.onGoToSection,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feedback = ref.watch(resumeFeedbackProvider(widget.resume.id));
    final items = feedback.maybeWhen(data: (l) => l, orElse: () => const <ResumeFeedbackModel>[]);
    final unread = widget.resume.unreadFeedbackCount;

    return CompositedTransformTarget(
      link: _link,
      child: IconButton(
        tooltip: _open ? '피드백 닫기' : '피드백 열기',
        isSelected: _open,
        onPressed: items.isEmpty && unread == 0 ? null : () => _toggle(items),
        icon: _BellIcon(unread: unread, active: _open || unread > 0),
      ),
    );
  }
}

class _BellIcon extends StatelessWidget {
  const _BellIcon({required this.unread, required this.active});

  final int unread;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(active ? Icons.notifications : Icons.notifications_none, size: 20),
        if (unread > 0)
          Positioned(
            top: -3,
            right: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16),
              height: 16,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Center(
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 종에서 내려오는 목록. 제목 줄만 있고 내용은 없다.
class _FeedbackPopover extends StatelessWidget {
  const _FeedbackPopover({
    required this.items,
    required this.readIds,
    required this.onPick,
    required this.onClose,
  });

  static const double width = 314;

  /// 꼬리 한가운데가 말풍선 왼쪽 끝에서 얼마나 떨어져 있나.
  /// 종은 툴바 오른쪽에 있으므로 말풍선은 왼쪽으로 눕고, 꼬리는 오른쪽 가까이에 온다.
  static const double tailFromLeft = width - 30;

  /// 말풍선을 종 기준으로 얼마나 옮길지. `followerAnchor` 가 말풍선 **한가운데**라
  /// 꼬리를 종에 맞추려면 그 차이만큼 밀어야 한다. 이 둘을 따로 적었다가 꼬리가
  /// 156px 왼쪽으로 어긋난 적이 있다. 한 값에서 뽑아 두 번 다시 어긋나지 않게 한다.
  static const double followerDx = width / 2 - tailFromLeft;

  final List<ResumeFeedbackModel> items;
  final Set<String> readIds;
  final ValueChanged<ResumeFeedbackModel> onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    // Align 으로 감싸면 자식이 화면 크기로 늘어나고, 그러면 followerAnchor 가
    // 말풍선이 아니라 화면 한가운데를 가리켜 위치가 통째로 어긋난다. 자식은 제 크기여야 한다.
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: width,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 꼬리. 종 한가운데에 온다.
              Padding(
                padding: const EdgeInsets.only(left: tailFromLeft - 6),
                child: CustomPaint(size: const Size(12, 7), painter: _TailPainter()),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(13, 14, 13, 16),
                        child: Text(
                          '아직 피드백이 없습니다.',
                          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, color: Color(0xFFF1F3F7)),
                          itemBuilder: (_, i) => _Row(
                            item: items[i],
                            unread: !readIds.contains(items[i].id),
                            onTap: () => onPick(items[i]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final unread = items.where((e) => !readIds.contains(e.id)).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 8, 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5))),
      ),
      child: Row(
        children: [
          const Text('피드백', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(width: 7),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$unread',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: onClose,
            icon: const Icon(Icons.close, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}

/// 한 줄. 누가 남겼는지와 어느 항목에 대한 것인지만.
class _Row extends StatelessWidget {
  const _Row({required this.item, required this.unread, required this.onTap});

  final ResumeFeedbackModel item;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = sectionLabelOf(item.sectionKey);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 11, 11),
        decoration: BoxDecoration(
          color: unread ? const Color(0xFFFBFCFF) : null,
          border: Border(
            left: BorderSide(
              color: unread ? AppColors.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  item.authorName,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                ),
                const Spacer(),
                if (item.createdAt != null)
                  Text(
                    AppDateUtils.formatDisplay(item.createdAt!),
                    style: const TextStyle(fontSize: 10.5, color: AppColors.textHint),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const TextSpan(
                          text: '에 대한 피드백',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.chevron_right, size: 16, color: AppColors.textHint),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 전문. 여기까지 와야 읽음이다.
class FeedbackDetailDialog extends StatelessWidget {
  const FeedbackDetailDialog({
    super.key,
    required this.item,
    required this.onGoToSection,
  });

  final ResumeFeedbackModel item;
  final ValueChanged<String> onGoToSection;

  @override
  Widget build(BuildContext context) {
    final label = sectionLabelOf(item.sectionKey);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$label에 대한 피드백',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: AppColors.textHint),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            item.createdAt == null
                ? item.authorName
                : '${item.authorName} · ${AppDateUtils.formatDateTime(item.createdAt!)}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Text(
            item.content,
            style: const TextStyle(fontSize: 13.5, height: 1.7, color: Color(0xFF374151)),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            onGoToSection(item.sectionKey);
          },
          child: const Text('해당 항목으로 이동'),
        ),
      ],
    );
  }
}

/// 종 한가운데 X 를 주면 말풍선 왼쪽 끝이 놓일 자리.
@visibleForTesting
double popoverLeftFor(double bellCenterX) =>
    bellCenterX + _FeedbackPopover.followerDx - _FeedbackPopover.width / 2;

/// 그때 꼬리 한가운데가 놓일 자리. **종 한가운데와 같아야 한다.**
@visibleForTesting
double tailCenterFor(double bellCenterX) =>
    popoverLeftFor(bellCenterX) + _FeedbackPopover.tailFromLeft;

/// 섹션 키를 사람이 읽는 이름으로. 모르는 키는 그대로 보여 준다.
String sectionLabelOf(String key) =>
    AppConstants.resumeSectionLabels[key] ?? (key.isEmpty ? '이력서' : key);

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height)
        ..lineTo(size.width / 2, 0)
        ..lineTo(size.width, size.height),
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
