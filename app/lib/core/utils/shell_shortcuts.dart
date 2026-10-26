import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:revoked_app/core/utils/paste_link_shortcut.dart';

/// The shell's keys, app-wide like [PasteLinkShortcut]: `/` searches or
/// opens a link, `N` opens the New picker, and Ctrl+1…4 (Cmd on macOS) go to
/// the four destinations.
///
/// Each one stands aside while a text field has focus, so typing "n" or "/"
/// into a field is never taken, and while [enabled] says no — outside the
/// shell, or with a dialog or sheet already open.
class ShellShortcuts extends StatelessWidget {
  final bool Function() enabled;
  final VoidCallback onSearch;
  final VoidCallback onNew;
  final ValueChanged<int> onDestination;
  final Widget child;

  const ShellShortcuts({
    super.key,
    required this.enabled,
    required this.onSearch,
    required this.onNew,
    required this.onDestination,
    required this.child,
  });

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
  ];

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        const CharacterActivator('/'): const _ShellIntent.search(),
        const CharacterActivator('n'): const _ShellIntent.create(),
        for (var i = 0; i < _digits.length; i++) ...{
          SingleActivator(_digits[i], control: true): _ShellIntent.go(i),
          SingleActivator(_digits[i], meta: true): _ShellIntent.go(i),
        },
      },
      child: Actions(
        actions: {
          _ShellIntent: _ShellAction(
            enabled: enabled,
            onSearch: onSearch,
            onNew: onNew,
            onDestination: onDestination,
          ),
        },
        child: child,
      ),
    );
  }
}

class _ShellIntent extends Intent {
  /// The destination for [go]; -1 for search, -2 for New.
  final int target;

  const _ShellIntent.search() : target = -1;
  const _ShellIntent.create() : target = -2;
  const _ShellIntent.go(this.target);
}

class _ShellAction extends Action<_ShellIntent> {
  _ShellAction({
    required this.enabled,
    required this.onSearch,
    required this.onNew,
    required this.onDestination,
  });

  final bool Function() enabled;
  final VoidCallback onSearch;
  final VoidCallback onNew;
  final ValueChanged<int> onDestination;

  // Disabled rather than handled-and-ignored, so a key the shell does not
  // want reaches whatever else would take it.
  @override
  bool get isActionEnabled => !textFieldHasFocus() && enabled();

  @override
  Object? invoke(_ShellIntent intent) {
    switch (intent.target) {
      case -1:
        onSearch();
      case -2:
        onNew();
      default:
        onDestination(intent.target);
    }
    return null;
  }
}
