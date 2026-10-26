import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/state/local.dart';

/// A 2 px ring in the accent colour while keyboard focus is inside [child].
///
/// Material's own focus feedback is a faint fill, easy to lose on a busy
/// screen; a ring says where the keyboard is at a glance. Shown only for
/// keyboard use (not after a tap), so it never flickers under a finger.
/// Buttons draw the same ring through their style; this is for rows, tiles
/// and anything else built on an `InkWell`.
class AppFocusRing extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;

  const AppFocusRing({
    super.key,
    required this.child,
    this.borderRadius = AppRadius.allMd,
  });

  @override
  State<AppFocusRing> createState() => _AppFocusRingState();
}

class _AppFocusRingState extends State<AppFocusRing> {
  final Local<bool> _focused = Local(false);
  final Local<bool> _keyboard = Local(_isKeyboard());

  static bool _isKeyboard() =>
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onMode);
    super.dispose();
  }

  void _onMode(FocusHighlightMode _) => _keyboard.value = _isKeyboard();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.accent;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        // Focus moves before the mode listener hears of the key that moved
        // it, so the mode is read again here.
        _keyboard.value = _isKeyboard();
        _focused.value = focused;
      },
      child: Observer(
        builder: (_) => DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: _focused.value && _keyboard.value
              ? BoxDecoration(
                  borderRadius: widget.borderRadius,
                  border: Border.all(color: accent, width: 2),
                )
              : const BoxDecoration(),
          child: widget.child,
        ),
      ),
    );
  }
}
