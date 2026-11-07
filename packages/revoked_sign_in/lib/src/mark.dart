import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The Revoked mark: four bars. Fixed geometry, never redrawn per platform.
///
/// With [pulsing], the bars fade one after another, top to bottom: the
/// loading state. It stands still when the platform asks for less motion.
class RevokedMark extends StatefulWidget {
  const RevokedMark({super.key, required this.size, required this.color, this.pulsing = false});

  final double size;
  final Color color;
  final bool pulsing;

  @override
  State<RevokedMark> createState() => _RevokedMarkState();
}

class _RevokedMarkState extends State<RevokedMark> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(RevokedMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final move = widget.pulsing && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (move && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!move && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = widget.pulsing && !_pulse.isAnimating;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _MarkPainter(color: widget.color, pulse: widget.pulsing ? _pulse : null, still: still),
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.color, required this.pulse, required this.still}) : super(repaint: pulse);

  final Color color;
  final Animation<double>? pulse;
  final bool still;

  // x, y and width of each bar in a 300 × 300 box; every bar is 44 high.
  static const _bars = [(0.0, 0.0, 300.0), (40.0, 85.33, 220.0), (0.0, 170.67, 300.0), (80.0, 256.0, 140.0)];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 300;
    for (var i = 0; i < _bars.length; i++) {
      final (x, y, w) = _bars[i];
      var opacity = 1.0;
      if (still) {
        opacity = 0.55;
      } else if (pulse != null) {
        // 1 → 0.3 → 1 over 1.2 s, each bar 0.12 s after the one above.
        final t = (pulse!.value - i * 0.1) % 1.0;
        opacity = 1 - 0.7 * (0.5 - 0.5 * math.cos(2 * math.pi * t));
      }
      final paint = Paint()..color = color.withValues(alpha: color.a * opacity);
      canvas.drawRect(Rect.fromLTWH(x * scale, y * scale, w * scale, 44 * scale), paint);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color || old.still != still || old.pulse != pulse;
}
