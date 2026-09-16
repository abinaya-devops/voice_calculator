import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app logo: a microphone with voice ripple rings, framed by four
/// calculation glyphs (+ − × ÷). Drawn entirely with canvas shapes so it
/// stays crisp at any size — used for launcher icons and the About dialog.
///
/// Palette: cornflower blue gradient background, ice-blue rings,
/// white microphone. All elements are symmetric about the vertical axis.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 64,
    this.withBackground = true,
  });

  final double size;
  final bool withBackground;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: AppLogoPainter(
          withBackground: withBackground,
          rounded: true,
        ),
      ),
    );
  }
}

/// Public painter so tooling (launcher icon generation) can render the
/// logo at any resolution, with a rounded or full-square background.
class AppLogoPainter extends CustomPainter {
  AppLogoPainter({
    required this.withBackground,
    required this.rounded,
  });

  final bool withBackground;

  /// When true the background is a rounded square (in-app), otherwise a
  /// full square (launcher icons get masked by the OS).
  final bool rounded;

  // -- Palette ---------------------------------------------------------------
  static const Color _bgTop = Color(0xFF5B8DEF); // cornflower
  static const Color _bgBottom = Color(0xFF2B5EA7); // deep cornflower
  static const Color _ice = Color(0xFFBFE3F7); // ice blue
  static const Color _micGrid = Color(0xFF6FA3DC); // soft blue grid

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.scale(s / 512);

    if (withBackground) {
      _paintBackground(canvas);
    }

    _paintGlyphs(canvas);
    _paintRings(canvas);
    _paintMicrophone(canvas);
  }

  void _paintBackground(Canvas canvas) {
    const bgRect = Rect.fromLTWH(0, 0, 512, 512);
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_bgTop, _bgBottom],
      ).createShader(bgRect);

    if (rounded) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(110)),
        bgPaint,
      );
    } else {
      canvas.drawRect(bgRect, bgPaint);
    }

    // Subtle top highlight — barely there, keeps the surface lively.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 512, 256),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x24FFFFFF), Color(0x00FFFFFF)],
        ).createShader(bgRect),
    );
  }

  // -- Corner glyphs: + − × ÷ -------------------------------------------------
  //
  // Symmetric layout: every glyph center sits exactly `m` from its corner,
  // all arms have the same length `r`, same stroke width.
  void _paintGlyphs(Canvas canvas) {
    const m = 104.0; // margin from each edge to glyph center
    const r = 30.0; // glyph arm radius

    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round;

    _plus(canvas, const Offset(m, m), r, p);
    _minus(canvas, const Offset(512 - m, m), r, p);
    _times(canvas, const Offset(m, 512 - m), r, p);
    _divide(canvas, const Offset(512 - m, 512 - m), r, p);
  }

  void _plus(Canvas c, Offset o, double r, Paint p) {
    c.drawLine(Offset(o.dx - r, o.dy), Offset(o.dx + r, o.dy), p);
    c.drawLine(Offset(o.dx, o.dy - r), Offset(o.dx, o.dy + r), p);
  }

  void _minus(Canvas c, Offset o, double r, Paint p) {
    c.drawLine(Offset(o.dx - r, o.dy), Offset(o.dx + r, o.dy), p);
  }

  void _times(Canvas c, Offset o, double r, Paint p) {
    final d = r * 0.7071; // 45° arms, same visual width as + arms
    c.drawLine(Offset(o.dx - d, o.dy - d), Offset(o.dx + d, o.dy + d), p);
    c.drawLine(Offset(o.dx - d, o.dy + d), Offset(o.dx + d, o.dy - d), p);
  }

  void _divide(Canvas c, Offset o, double r, Paint p) {
    c.drawLine(Offset(o.dx - r, o.dy), Offset(o.dx + r, o.dy), p);
    final dot = Paint()..color = p.color;
    c.drawCircle(Offset(o.dx, o.dy - r * 0.62), 6, dot);
    c.drawCircle(Offset(o.dx, o.dy + r * 0.62), 6, dot);
  }

  // -- Voice ripple rings (ice blue, concentric) ------------------------------
  void _paintRings(Canvas canvas) {
    // Optically centered on the microphone body (slightly above true center
    // because the mic stem+base extend below).
    const center = Offset(256, 248);

    canvas.drawCircle(
      center,
      118,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..color = _ice.withValues(alpha: 0.40),
    );
    canvas.drawCircle(
      center,
      146,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = _ice.withValues(alpha: 0.18),
    );
  }

  // -- Microphone: capsule + cradle + stem + base, all centered on x=256 ------
  void _paintMicrophone(Canvas canvas) {
    const cx = 256.0;
    const capsuleTop = 160.0;
    const capsuleBottom = 324.0;
    const capsuleW = 100.0;
    const capsuleR = 50.0;

    // Capsule (white, rounded).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - capsuleW / 2, capsuleTop, capsuleW,
            capsuleBottom - capsuleTop),
        const Radius.circular(capsuleR),
      ),
      Paint()..color = Colors.white,
    );

    // Grid lines inside the capsule.
    final grid = Paint()
      ..color = _micGrid.withValues(alpha: 0.55)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    for (final y in [216.0, 242.0, 268.0]) {
      canvas.drawLine(Offset(cx - 32, y), Offset(cx + 32, y), grid);
    }

    // Cradle: lower half-circle around the capsule.
    const arcRadius = 86.0;
    const arcCenterY = 242.0;
    final cradle = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: const Offset(cx, arcCenterY),
        width: arcRadius * 2,
        height: arcRadius * 2,
      ),
      0,
      math.pi,
      false,
      cradle,
    );

    // Stem: from arc bottom down to the base.
    const stemTop = arcCenterY + arcRadius; // 328
    const baseY = 366.0;
    canvas.drawLine(Offset(cx, stemTop), Offset(cx, baseY - 6), cradle);

    // Base: horizontal bar, symmetric about cx.
    canvas.drawLine(Offset(cx - 40, baseY), Offset(cx + 40, baseY), cradle);
  }

  @override
  bool shouldRepaint(covariant AppLogoPainter oldDelegate) =>
      oldDelegate.withBackground != withBackground ||
      oldDelegate.rounded != rounded;
}
