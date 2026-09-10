import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/onboarding_step.dart';
import '../domain/onboarding_target_registry.dart';

/// 딤 + 하이라이트 구멍 + 설명 카드
class OnboardingOverlay extends StatefulWidget {
  const OnboardingOverlay({
    super.key,
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.onNext,
    required this.onDismissForever,
    required this.onSkipMissing,
  });

  final OnboardingStep step;
  final int stepIndex;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onDismissForever;
  final VoidCallback onSkipMissing;

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay> {
  static const _holePadding = 10.0;
  static const _holeRadius = 12.0;
  static const _maxRetries = 12;

  Rect? _targetRect;
  var _retries = 0;
  var _resolving = false;
  var _ensuredVisible = false;

  @override
  void initState() {
    super.initState();
    _scheduleResolve();
  }

  @override
  void didUpdateWidget(covariant OnboardingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step.id != widget.step.id) {
      _targetRect = null;
      _retries = 0;
      _ensuredVisible = false;
      _scheduleResolve();
    }
  }

  void _scheduleResolve() {
    if (_resolving) return;
    _resolving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolving = false;
      if (!mounted) return;
      _resolveTarget();
    });
  }

  Future<void> _ensureTargetVisible() async {
    if (_ensuredVisible) return;
    final ctx = OnboardingTargetRegistry.keyOf(widget.step.targetId).currentContext;
    if (ctx == null) return;
    _ensuredVisible = true;
    try {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.45,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    } catch (_) {}
    // 스크롤 후 한 프레임 대기 후 rect 재측정
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  Future<void> _resolveTarget() async {
    await _ensureTargetVisible();
    if (!mounted) return;

    final rect = OnboardingTargetRegistry.rectOf(widget.step.targetId);
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final visible = Rect.fromLTRB(
      0,
      padding.top,
      size.width,
      size.height - padding.bottom,
    );

    if (rect != null &&
        rect.width > 0 &&
        rect.height > 0 &&
        rect.overlaps(visible)) {
      setState(() => _targetRect = rect);
      return;
    }

    // 아직 안 보이면 스크롤 플래그 리셋 후 재시도
    if (rect != null && !rect.overlaps(visible)) {
      _ensuredVisible = false;
    }

    _retries++;
    if (_retries >= _maxRetries) {
      if (widget.step.skippableIfMissing) {
        widget.onSkipMissing();
        return;
      }
      setState(() => _targetRect = null);
      return;
    }

    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      _scheduleResolve();
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final isLast = widget.stepIndex >= widget.totalSteps - 1;
    final hole = _targetRect?.inflate(_holePadding);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _SpotlightPainter(
                hole: hole,
                radius: _holeRadius,
              ),
            ),
          ),
          const Positioned.fill(
            child: AbsorbPointer(absorbing: true, child: SizedBox.expand()),
          ),
          if (hole != null)
            Positioned(
              left: hole.left,
              top: hole.top,
              width: hole.width,
              height: hole.height,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_holeRadius),
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
            ),
          _TooltipCard(
            step: widget.step,
            stepIndex: widget.stepIndex,
            totalSteps: widget.totalSteps,
            screenSize: size,
            safePadding: padding,
            targetRect: hole,
            isLast: isLast,
            onNext: widget.onNext,
            onDismissForever: widget.onDismissForever,
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.hole, required this.radius});

  final Rect? hole;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    if (hole == null) {
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(
        RRect.fromRectAndRadius(hole!, Radius.circular(radius)),
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.radius != radius;
}

class _TooltipCard extends StatelessWidget {
  const _TooltipCard({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.screenSize,
    required this.safePadding,
    required this.targetRect,
    required this.isLast,
    required this.onNext,
    required this.onDismissForever,
  });

  final OnboardingStep step;
  final int stepIndex;
  final int totalSteps;
  final Size screenSize;
  final EdgeInsets safePadding;
  final Rect? targetRect;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onDismissForever;

  static const _cardWidth = 320.0;
  static const _gap = 12.0;
  static const _margin = 16.0;
  static const _estimatedHeight = 168.0;

  Offset _resolvePosition(Rect? target) {
    final minLeft = _margin;
    final maxLeft = screenSize.width - _cardWidth - _margin;
    final minTop = math.max(safePadding.top + _margin, _margin);
    final maxTop = screenSize.height -
        safePadding.bottom -
        _estimatedHeight -
        _margin;

    if (target == null) {
      return Offset(
        (screenSize.width - _cardWidth) / 2,
        (screenSize.height - _estimatedHeight) / 2,
      );
    }

    // 좌측 레일 타깃(화면 왼쪽 1/3) → 오른쪽에 카드
    final preferRight = target.center.dx < screenSize.width * 0.38;
    // 하단 타깃 → 위쪽에 카드
    final preferAbove =
        target.bottom > screenSize.height - safePadding.bottom - 220;

    double left;
    double top;

    if (preferRight) {
      left = target.right + _gap;
      if (left + _cardWidth > screenSize.width - _margin) {
        left = target.left - _cardWidth - _gap;
      }
      top = target.center.dy - _estimatedHeight / 2;
      if (preferAbove) {
        top = target.top - _estimatedHeight - _gap;
      }
    } else if (preferAbove) {
      left = target.center.dx - _cardWidth / 2;
      top = target.top - _estimatedHeight - _gap;
    } else {
      left = target.center.dx - _cardWidth / 2;
      final below = target.bottom + _gap;
      final above = target.top - _estimatedHeight - _gap;
      if (below + _estimatedHeight <=
          screenSize.height - safePadding.bottom - _margin) {
        top = below;
      } else {
        top = above;
      }
    }

    return Offset(
      left.clamp(minLeft, math.max(minLeft, maxLeft)),
      top.clamp(minTop, math.max(minTop, maxTop)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = _resolvePosition(targetRect);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      width: _cardWidth,
      child: Material(
        color: AppColors.surface,
        elevation: 8,
        shadowColor: AppColors.shadow,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      step.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${stepIndex + 1} / $totalSteps',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                step.body,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton(
                    onPressed: onDismissForever,
                    child: const Text('다시 보지 않기'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: onNext,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                    ),
                    child: Text(isLast ? '완료' : '다음'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
