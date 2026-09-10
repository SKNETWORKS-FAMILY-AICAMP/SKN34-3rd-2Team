import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 로그인 시네마틱 브랜드 스테이지 (다크 궤도)
class LoginBrandStage extends StatefulWidget {
  const LoginBrandStage({super.key});

  @override
  State<LoginBrandStage> createState() => _LoginBrandStageState();
}

class _LoginBrandStageState extends State<LoginBrandStage>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _orbit;
  Offset _pointer = Offset.zero;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (e) {
        final size = MediaQuery.sizeOf(context);
        setState(() {
          _pointer = Offset(
            (e.localPosition.dx / size.width - 0.5).clamp(-0.5, 0.5),
            (e.localPosition.dy / size.height - 0.5).clamp(-0.5, 0.5),
          );
        });
      },
      onExit: (_) => setState(() => _pointer = Offset.zero),
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulse, _orbit]),
        builder: (context, _) {
          return _DarkOrbitStage(
            pulse: Curves.easeInOut.transform(_pulse.value),
            orbit: _orbit.value,
            pointer: _pointer,
          );
        },
      ),
    );
  }
}

class _DarkOrbitStage extends StatelessWidget {
  const _DarkOrbitStage({
    required this.pulse,
    required this.orbit,
    required this.pointer,
  });

  final double pulse;
  final double orbit;
  final Offset pointer;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;
    final parallax = Offset(pointer.dx * 22, pointer.dy * 14);

    final cx = size.width * (wide ? 0.72 : 0.68) + parallax.dx;
    final cy = size.height * 0.48 + parallax.dy;
    final rx = size.width * (wide ? 0.16 : 0.2);
    final ry = size.height * 0.22;

    Offset onOrbit(double turn, {double radiusScale = 1}) {
      final a = orbit * math.pi * 2 + turn;
      return Offset(
        cx + math.cos(a) * rx * radiusScale,
        cy + math.sin(a) * ry * radiusScale + pulse * 4,
      );
    }

    final skPos = onOrbit(0.15, radiusScale: 1.05);
    final encorePos = onOrbit(math.pi * 0.95, radiusScale: 0.92);
    final hubW = wide ? 260.0 : 180.0;
    final hubH = wide ? 150.0 : 108.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        const _StageWash(),
        Positioned(
          left: cx - 160,
          top: cy - 160,
          child: IgnorePointer(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00C2D4).withValues(alpha: 0.18),
                    const Color(0xFF7B5CFF).withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: cx - rx,
          top: cy - ry,
          child: CustomPaint(
            size: Size(rx * 2, ry * 2),
            painter: _OrbitRingPainter(progress: orbit),
          ),
        ),
        _BrandPanel(
          left: cx - hubW / 2,
          top: cy - hubH / 2 + pulse * 6,
          width: hubW,
          height: hubH,
          rotation: -0.06 + pulse * 0.02,
          elevation: 28,
          glow: const Color(0xFF00C2D4),
          child: const _LogoFace(
            asset: 'assets/brand/playdata.jpg',
            padding: 20,
          ),
        ),
        _BrandPanel(
          left: skPos.dx - (wide ? 74 : 56),
          top: skPos.dy - (wide ? 74 : 56),
          width: wide ? 148 : 112,
          height: wide ? 148 : 112,
          rotation: 0.2 + orbit * 0.4,
          elevation: 16,
          glow: const Color(0xFFF15A22),
          child: const _LogoFace(
            asset: 'assets/brand/sk_networks.jpg',
            padding: 14,
          ),
        ),
        _BrandPanel(
          left: encorePos.dx - (wide ? 68 : 52),
          top: encorePos.dy - (wide ? 68 : 52),
          width: wide ? 136 : 104,
          height: wide ? 136 : 104,
          rotation: -0.12 - orbit * 0.3,
          elevation: 14,
          glow: const Color(0xFF2BBBAD),
          child: const _LogoFace(
            asset: 'assets/brand/encore.jpg',
            padding: 12,
          ),
        ),
        ...List.generate(6, (i) {
          final p = onOrbit(i * (math.pi * 2 / 6) + 0.4, radiusScale: 1.25);
          return Positioned(
            left: p.dx,
            top: p.dy,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i.isEven
                    ? const Color(0xFF00C2D4).withValues(alpha: 0.7)
                    : const Color(0xFF7B5CFF).withValues(alpha: 0.65),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00C2D4).withValues(alpha: 0.35),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _OrbitRingPainter extends CustomPainter {
  _OrbitRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.12);
    canvas.drawOval(rect.deflate(2), paint);

    final accent = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF00C2D4).withValues(alpha: 0.45);
    canvas.drawArc(
      rect.deflate(2),
      progress * math.pi * 2,
      1.1,
      false,
      accent,
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _StageWash extends StatelessWidget {
  const _StageWash();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF05070F),
            Color(0xFF0B1224),
            Color(0xFF12102A),
            Color(0xFF1A0F18),
          ],
          stops: [0.0, 0.35, 0.7, 1.0],
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.rotation,
    required this.child,
    this.elevation = 12,
    this.glow,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final double rotation;
  final Widget child;
  final double elevation;
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateZ(rotation)
          ..rotateY(-0.18)
          ..rotateX(0.12),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: elevation,
                offset: Offset(elevation * 0.2, elevation * 0.45),
              ),
              if (glow != null)
                BoxShadow(
                  color: glow!.withValues(alpha: 0.32),
                  blurRadius: 28,
                  spreadRadius: 1,
                ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

class _LogoFace extends StatelessWidget {
  const _LogoFace({required this.asset, this.padding = 16});

  final String asset;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Image.asset(
          asset,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
