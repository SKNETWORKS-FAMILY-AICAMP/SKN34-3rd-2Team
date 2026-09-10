import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/providers/auth_providers.dart';
import '../domain/onboarding_step.dart';
import 'onboarding_controller.dart';
import 'onboarding_overlay.dart';

/// 역할 공통 온보딩 호스트 — 셸 위에 오버레이 + 스텝별 라우트 이동
class OnboardingHost extends ConsumerStatefulWidget {
  const OnboardingHost({
    super.key,
    required this.child,
    required this.tourId,
    required this.version,
    required this.steps,
    this.rootRoutes = const {},
  });

  final Widget child;
  final String tourId;
  final int version;
  final List<OnboardingStep> steps;

  /// exact match만 허용할 루트 경로 (`/`, `/admin`, `/instructor` 등)
  final Set<String> rootRoutes;

  @override
  ConsumerState<OnboardingHost> createState() => _OnboardingHostState();
}

class _OnboardingHostState extends ConsumerState<OnboardingHost> {
  String? _bootstrappedUid;
  String? _navigatingForStepId;

  void _tryBootstrap(String uid) {
    if (_bootstrappedUid == uid) return;
    _bootstrappedUid = uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(onboardingTourProvider.notifier).maybeStart(
            tourId: widget.tourId,
            version: widget.version,
            uid: uid,
            steps: widget.steps,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final tour = ref.watch(onboardingTourProvider);

    ref.listen(currentUserProvider, (prev, next) {
      final uid = next.value?.uid;
      if (uid == null || uid.isEmpty) return;
      _tryBootstrap(uid);
    });

    if (user != null && user.uid.isNotEmpty) {
      _tryBootstrap(user.uid);
    }

    ref.listen(onboardingTourProvider, (prev, next) {
      if (next == null || !next.active) return;
      if (next.tourId != widget.tourId) return;
      final step = next.currentStep;
      if (step?.route == null) return;
      _ensureRoute(step!.id, step.route!);
    });

    final activeTour = (tour != null &&
            tour.active &&
            tour.tourId == widget.tourId)
        ? tour
        : null;
    final activeStep = activeTour?.currentStep;

    if (activeStep?.route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureRoute(activeStep!.id, activeStep.route!);
      });
    }

    return Stack(
      children: [
        widget.child,
        if (activeTour != null && activeStep != null)
          Positioned.fill(
            child: OnboardingOverlay(
              key: ValueKey('${widget.tourId}_${activeStep.id}'),
              step: activeStep,
              stepIndex: activeTour.index,
              totalSteps: activeTour.total,
              onNext: () => _onNext(activeTour),
              onDismissForever: () => ref
                  .read(onboardingTourProvider.notifier)
                  .dismissForever(),
              onSkipMissing: () => _onSkipMissing(activeTour),
            ),
          ),
      ],
    );
  }

  bool _isAtRoute(String location, String route) {
    if (route == '/') return location == '/' || location.isEmpty;
    if (widget.rootRoutes.contains(route)) return location == route;
    return location == route || location.startsWith('$route/');
  }

  void _ensureRoute(String stepId, String route) {
    if (!mounted) return;
    final location = GoRouterState.of(context).matchedLocation;
    if (_isAtRoute(location, route)) return;
    if (_navigatingForStepId == stepId) return;
    _navigatingForStepId = stepId;
    context.go(route);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatingForStepId = null;
    });
  }

  Future<void> _onNext(OnboardingTourState tour) async {
    final notifier = ref.read(onboardingTourProvider.notifier);
    if (tour.isLast) {
      await notifier.dismissForever();
      return;
    }
    final nextIndex = tour.index + 1;
    final nextStep = tour.steps[nextIndex];
    if (nextStep.route != null) {
      _ensureRoute(nextStep.id, nextStep.route!);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }
    notifier.goToIndex(nextIndex);
  }

  Future<void> _onSkipMissing(OnboardingTourState tour) async {
    final notifier = ref.read(onboardingTourProvider.notifier);
    if (tour.isLast) {
      await notifier.dismissForever();
      return;
    }
    final nextIndex = tour.index + 1;
    final nextStep = tour.steps[nextIndex];
    if (nextStep.route != null) {
      _ensureRoute(nextStep.id, nextStep.route!);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }
    notifier.goToIndex(nextIndex);
  }
}
