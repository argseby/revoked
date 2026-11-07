import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';

import 'client.dart';
import 'mark.dart';
import 'pressable.dart';
import 'strings.dart';
import 'style.dart';

/// Why a sign-in ended without signing anyone in.
enum RevokedSignInProblem {
  /// The person declined in the app.
  declined,

  /// The sign-in ran out of time or was already collected.
  expired,

  /// `start` failed, or `wait` answered with an error other than a decline.
  failed,
}

/// What the panel shows.
sealed class PanelState {
  const PanelState();
}

class PanelWaiting extends PanelState {
  const PanelWaiting(this.start);
  final RevokedSignInStart start;
}

class PanelEnded extends PanelState {
  const PanelEnded(this.problem, {this.restarting = false});
  final RevokedSignInProblem problem;
  final bool restarting;
}

/// The panel's content. Three kinds of text only: the title, body text
/// (instructions, buttons and status alike) and the check code.
class RevokedSignInPanel extends StatelessWidget {
  const RevokedSignInPanel({
    super.key,
    required this.state,
    required this.strings,
    required this.title,
    required this.phone,
    required this.textStyle,
    required this.onOpenHere,
    required this.onStartAgain,
    required this.onClose,
  });

  final ValueNotifier<PanelState> state;
  final RevokedStrings strings;
  final String title;

  /// A phone most likely holds the app, so opening it leads; on a computer
  /// the code leads and opening it here is the quiet alternative.
  final bool phone;

  /// The app's text style, so the panel uses the app's font.
  final TextStyle textStyle;
  final ValueChanged<Uri> onOpenHere;
  final VoidCallback onStartAgain;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = RevokedPanelColors.of(MediaQuery.platformBrightnessOf(context));
    final highContrast = MediaQuery.highContrastOf(context);
    final body = textStyle.copyWith(
      fontSize: 14,
      height: 1.45,
      fontWeight: FontWeight.w400,
      color: colors.foreground,
      decoration: TextDecoration.none,
    );

    return DefaultTextStyle(
      style: body,
      textAlign: TextAlign.center,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Semantics(
                scopesRoute: true,
                namesRoute: true,
                explicitChildNodes: true,
                label: title,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.background,
                    border: Border.all(color: highContrast ? colors.foreground : colors.line),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ValueListenableBuilder<PanelState>(
                    valueListenable: state,
                    builder: (context, value, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
                          child: _Head(title: title, close: strings.close, colors: colors, onClose: onClose),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                          child: switch (value) {
                            PanelWaiting(:final start) => _waiting(start, colors, body),
                            PanelEnded() => _ended(value, colors),
                          },
                        ),
                        if (value is PanelWaiting) _Footer(text: strings.waiting, colors: colors),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _waiting(RevokedSignInStart start, RevokedPanelColors colors, TextStyle body) {
    final open = _PanelButton(
      key: const ValueKey('revoked-open'),
      label: phone ? strings.openPhone : strings.open,
      solid: phone,
      colors: colors,
      autofocus: true,
      onPressed: () => onOpenHere(start.appLink),
    );
    final check = _CheckLine(template: strings.check, code: start.checkCode, style: body);
    final scan = Text(phone ? strings.scanElsewhere : strings.scan);
    final qr = Center(child: _QrCode(data: start.appLink.toString(), label: strings.qr));
    final children = phone ? [open, check, scan, qr] : [scan, qr, check, open];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: children,
    );
  }

  Widget _ended(PanelEnded ended, RevokedPanelColors colors) {
    final message = switch (ended.problem) {
      RevokedSignInProblem.expired => strings.expired,
      RevokedSignInProblem.declined => strings.declined,
      RevokedSignInProblem.failed => strings.failed,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        Semantics(liveRegion: true, child: Text(message)),
        _PanelButton(
          key: const ValueKey('revoked-again'),
          label: ended.restarting ? strings.opening : strings.startAgain,
          solid: true,
          colors: colors,
          autofocus: true,
          onPressed: ended.restarting ? () {} : onStartAgain,
        ),
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.title, required this.close, required this.colors, required this.onClose});

  final String title;
  final String close;
  final RevokedPanelColors colors;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.copyWith(fontSize: 17, fontWeight: FontWeight.w600, height: 1.3);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Row(
              spacing: 8,
              children: [
                RevokedMark(size: 16, color: colors.foreground),
                Flexible(child: Text(title, style: style, textAlign: TextAlign.start)),
              ],
            ),
          ),
        ),
        Pressable(
          key: const ValueKey('revoked-close'),
          semanticLabel: close,
          onPressed: onClose,
          minTapSize: const Size(44, 44),
          builder: (context, s) => FocusRing(
            visible: s.focused,
            radius: 8,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: s.hovered || s.pressed ? const Color(0x247F7F7F) : const Color(0x00000000),
                borderRadius: BorderRadius.circular(8),
                border: MediaQuery.highContrastOf(context) ? Border.all(color: colors.foreground) : null,
              ),
              child: CustomPaint(size: const Size.square(14), painter: _CrossPainter(colors.foreground)),
            ),
          ),
        ),
      ],
    );
  }
}

class _CrossPainter extends CustomPainter {
  _CrossPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final s = size.width;
    canvas.drawLine(Offset(s * .14, s * .14), Offset(s * .86, s * .86), paint);
    canvas.drawLine(Offset(s * .86, s * .14), Offset(s * .14, s * .86), paint);
  }

  @override
  bool shouldRepaint(_CrossPainter old) => old.color != color;
}

/// "Approve only if the app shows 0D2-99B." The code is read out one
/// character at a time; the sentence around it stays as written.
class _CheckLine extends StatelessWidget {
  const _CheckLine({required this.template, required this.code, required this.style});

  final String template;
  final String code;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final parts = template.split('{code}');
    final before = parts.first;
    final after = parts.length > 1 ? parts[1] : '';
    final mono = style.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'SF Mono', 'Consolas', 'Roboto Mono', 'Courier New'],
      fontWeight: FontWeight.w700,
      letterSpacing: 0.84,
      fontFeatures: const [FontFeature.slashedZero()],
    );
    return Text.rich(
      TextSpan(children: [TextSpan(text: before), TextSpan(text: code, style: mono), TextSpan(text: after)]),
      semanticsLabel: '$before${spellCheckCode(code)}$after',
    );
  }
}

class _QrCode extends StatelessWidget {
  const _QrCode({required this.data, required this.label});

  final String data;
  final String label;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.L));
    return Semantics(
      image: true,
      label: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 208),
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(8)),
            child: CustomPaint(painter: _QrPainter(image)),
          ),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);
  final QrImage image;

  static const _quiet = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    final cell = size.width / (count + _quiet * 2);
    final path = Path();
    for (var y = 0; y < count; y++) {
      for (var x = 0; x < count; x++) {
        if (image.isDark(y, x)) {
          // Slightly larger than a cell, so no hairline gaps show between them.
          path.addRect(Rect.fromLTWH((x + _quiet) * cell, (y + _quiet) * cell, cell + 0.4, cell + 0.4));
        }
      }
    }
    canvas.drawPath(path, Paint()..color = const Color(0xFF000000));
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}

class _Footer extends StatelessWidget {
  const _Footer({required this.text, required this.colors});

  final String text;
  final RevokedPanelColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.line))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Semantics(
          liveRegion: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 10,
            children: [
              RevokedMark(size: 14, color: colors.foreground, pulsing: true),
              Flexible(child: Text(text)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    super.key,
    required this.label,
    required this.solid,
    required this.colors,
    required this.onPressed,
    this.autofocus = false,
  });

  final String label;
  final bool solid;
  final RevokedPanelColors colors;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    return Pressable(
      autofocus: autofocus,
      onPressed: onPressed,
      builder: (context, s) {
        final tint = s.pressed ? 0.2 : (s.hovered ? 0.1 : 0.0);
        final background = solid
            ? Color.lerp(colors.solid, colors.background, tint)!
            : Color.lerp(colors.background, colors.foreground, tint / 2)!;
        return FocusRing(
          visible: s.focused,
          radius: 10,
          highContrast: highContrast,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              border: Border.all(color: solid ? colors.solid : (highContrast ? colors.foreground : colors.line)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w600, color: solid ? colors.onSolid : colors.foreground),
            ),
          ),
        );
      },
    );
  }
}
