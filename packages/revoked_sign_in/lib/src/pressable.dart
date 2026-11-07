import 'package:flutter/widgets.dart';

/// What a [Pressable] is doing, for drawing it.
@immutable
class PressState {
  const PressState({required this.focused, required this.hovered, required this.pressed});
  final bool focused;
  final bool hovered;
  final bool pressed;
}

/// A button without a look: focus, keyboard activation (Enter and Space),
/// hover, press, a pointer cursor and button semantics. Everything that is
/// pressed in this package goes through it, so they all behave the same.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onPressed,
    required this.builder,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.minTapSize = Size.zero,
  });

  final VoidCallback onPressed;
  final Widget Function(BuildContext context, PressState state) builder;

  /// Replaces the child's own text as the accessible name, e.g. for the
  /// icon-only button.
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;

  /// The area that reacts to touch, if larger than what is drawn. The
  /// drawing stays centred in it.
  final Size minTapSize;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed()),
    ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onPressed()),
  };

  @override
  Widget build(BuildContext context) {
    Widget drawn = widget.builder(context, PressState(focused: _focused, hovered: _hovered, pressed: _pressed));
    // Only the drawing is hidden behind the label, so the focus flags below
    // still reach screen readers.
    if (widget.semanticLabel != null) drawn = ExcludeSemantics(child: drawn);
    return Semantics(
      container: true,
      button: true,
      enabled: true,
      label: widget.semanticLabel,
      onTap: widget.onPressed,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        actions: _actions,
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (on) => setState(() => _focused = on),
        onShowHoverHighlight: (on) => setState(() => _hovered = on),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: widget.minTapSize.width, minHeight: widget.minTapSize.height),
            child: Center(widthFactor: 1, heightFactor: 1, child: drawn),
          ),
        ),
      ),
    );
  }
}

/// The focus ring of spec v1: a 2-pixel white band and a 2-pixel black ring
/// outside the shape. Every colour has at least 4.5:1 against black or
/// against white, so one of the two always shows. Drawn outside the box,
/// without taking up layout space.
class FocusRing extends StatelessWidget {
  const FocusRing({super.key, required this.visible, required this.radius, required this.child, this.highContrast = false});

  final bool visible;
  final double radius;
  final bool highContrast;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: visible ? _RingPainter(radius, highContrast) : null,
      child: child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.radius, this.highContrast);
  final double radius;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(box.inflate(1), stroke..color = const Color(0xFFFFFFFF));
    // With "increase contrast" the outer ring is thicker.
    stroke.strokeWidth = highContrast ? 3 : 2;
    canvas.drawRRect(box.inflate(highContrast ? 3.5 : 3), stroke..color = const Color(0xFF000000));
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.radius != radius || old.highContrast != highContrast;
}
