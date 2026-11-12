import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/local.dart';

/// One series in a chart: what it is called, and the colour that marks it.
/// The name is always shown in the legend, so colour is never the only cue.
class AppChartSeries {
  final String label;
  final Color color;

  const AppChartSeries(this.label, this.color);
}

/// One point along the time axis: its label and a value per series.
class AppChartPoint {
  final String label;
  final List<double> values;

  const AppChartPoint(this.label, this.values);
}

/// The app's only chart: values over time, as stacked bars or as lines, with
/// a legend, a light grid and the exact numbers of the point under the
/// pointer (or the last tap) shown above it.
class AppChart extends StatefulWidget {
  final List<AppChartSeries> series;
  final List<AppChartPoint> points;

  /// Stacked bars for counts; lines for measures such as response times.
  final bool lines;

  /// How a value reads on the axis and in the readout.
  final String Function(double value) format;

  final double height;

  const AppChart({
    super.key,
    required this.series,
    required this.points,
    this.lines = false,
    this.format = _plain,
    this.height = 140,
  });

  static String _plain(double v) => v.round().toString();

  @override
  State<AppChart> createState() => _AppChartState();
}

class _AppChartState extends State<AppChart> {
  final _selected = Local<int?>(null);

  int? _indexAt(double dx, double width) {
    final n = widget.points.length;
    if (n == 0) return null;
    final plot = width - _ChartPainter.gutter;
    final i = ((dx - _ChartPainter.gutter) / (plot / n)).floor();
    return i.clamp(0, n - 1);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Observer(
      builder: (_) {
        final i = _selected.value;
        final point = i == null || i >= widget.points.length
            ? null
            : widget.points[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xxs,
              children: [
                for (final (k, s) in widget.series.indexed)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: s.color,
                          borderRadius: AppRadius.allXs,
                        ),
                      ),
                      AppSpacing.gapXs,
                      Text(
                        point == null
                            ? s.label
                            : '${s.label} ${widget.format(point.values[k])}',
                      ).small.muted,
                    ],
                  ),
                if (point != null) Text(point.label).small,
              ],
            ),
            AppSpacing.gapSm,
            LayoutBuilder(
              builder: (context, box) => MouseRegion(
                onHover: (e) => _selected.value = _indexAt(
                  e.localPosition.dx,
                  box.maxWidth,
                ),
                onExit: (_) => _selected.value = null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (e) => _selected.value = _indexAt(
                    e.localPosition.dx,
                    box.maxWidth,
                  ),
                  child: CustomPaint(
                    size: Size(box.maxWidth, widget.height),
                    painter: _ChartPainter(
                      series: widget.series,
                      points: widget.points,
                      lines: widget.lines,
                      selected: i,
                      grid: scheme.outlineVariant,
                      text: scheme.onSurfaceVariant,
                      highlight: scheme.onSurface.withValues(alpha: 0.06),
                      format: widget.format,
                      labelStyle: DefaultTextStyle.of(context).style.copyWith(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<AppChartSeries> series;
  final List<AppChartPoint> points;
  final bool lines;
  final int? selected;
  final Color grid;
  final Color text;
  final Color highlight;
  final String Function(double) format;
  final TextStyle labelStyle;

  /// Bars alone, without grid or labels, for a chart the size of a word.
  final bool bare;

  _ChartPainter({
    required this.series,
    required this.points,
    required this.lines,
    required this.selected,
    required this.grid,
    required this.text,
    required this.highlight,
    required this.format,
    required this.labelStyle,
    this.bare = false,
  });

  static const _axisHeight = 16.0;

  double get _axis => bare ? 0 : _axisHeight;

  /// Room left of the plot for the value labels, so they never sit on a bar.
  static const gutter = 40.0;

  double get _left => bare ? 0 : gutter;

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    if (n == 0) return;
    final plotH = size.height - _axis;
    final left = _left;
    final slot = (size.width - left) / n;
    final top = points.fold<double>(0, (m, p) {
      final v = lines
          ? p.values.fold<double>(0, math.max)
          : p.values.fold<double>(0, (a, b) => a + b);
      return math.max(m, v);
    });
    final max = top <= 0 ? 1.0 : top;
    double y(double v) => plotH - plotH * (v / max);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.5;
    for (final t in bare ? const <double>[] : const [0.0, 0.5, 1.0]) {
      final gy = y(max * t);
      canvas.drawLine(Offset(left, gy), Offset(size.width, gy), gridPaint);
      if (t > 0) _label(canvas, format(max * t), Offset(0, gy - 6));
    }

    if (selected != null && selected! < n) {
      canvas.drawRect(
        Rect.fromLTWH(left + selected! * slot, 0, slot, plotH),
        Paint()..color = highlight,
      );
    }

    if (lines) {
      for (final (k, s) in series.indexed) {
        final path = Path();
        for (var i = 0; i < n; i++) {
          final p = Offset(left + i * slot + slot / 2, y(points[i].values[k]));
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round,
        );
      }
    } else {
      final gap = slot > 6 ? 2.0 : 0.5;
      for (var i = 0; i < n; i++) {
        var base = plotH;
        for (final (k, s) in series.indexed) {
          final v = points[i].values[k];
          if (v <= 0) continue;
          final h = plotH * (v / max);
          final rect = Rect.fromLTWH(
            left + i * slot + gap / 2,
            base - h,
            math.max(slot - gap, 1),
            math.max(h - (base < plotH ? 2 : 0), 1),
          );
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              rect,
              topLeft: const Radius.circular(2),
              topRight: const Radius.circular(2),
            ),
            Paint()..color = s.color,
          );
          base -= h;
        }
      }
    }

    if (bare) return;
    // A handful of time labels, never crowding each other.
    final every = math.max(1, (n / math.max(1, size.width ~/ 64)).ceil());
    for (var i = 0; i < n; i += every) {
      _label(canvas, points[i].label, Offset(left + i * slot, plotH + 3));
    }
  }

  void _label(Canvas canvas, String s, Offset at) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.points != points || old.selected != selected || old.lines != lines;
}

/// One number with what it counts, for the row of figures above a chart.
class AppStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  const AppStatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: AppRadius.allMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: scheme.onSurfaceVariant),
                AppSpacing.gapXs,
              ],
              Flexible(child: Text(label).small.muted),
            ],
          ),
          AppSpacing.gapXxs,
          Text(value).header,
        ],
      ),
    );
  }
}

/// A stacked bar chart the size of a word, beside a row in a list: the shape
/// of the last day at a glance. The row's own text carries the numbers.
class AppSparkBars extends StatelessWidget {
  final List<AppChartSeries> series;
  final List<AppChartPoint> points;
  final double width;
  final double height;

  const AppSparkBars({
    super.key,
    required this.series,
    required this.points,
    this.width = 72,
    this.height = 24,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(width, height),
        painter: _ChartPainter(
          series: series,
          points: points,
          lines: false,
          selected: null,
          grid: scheme.outlineVariant,
          text: scheme.onSurfaceVariant,
          highlight: scheme.onSurface,
          format: AppChart._plain,
          labelStyle: const TextStyle(),
          bare: true,
        ),
      ),
    );
  }
}
