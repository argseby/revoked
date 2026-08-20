import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// App-wide Ctrl+V.
///
/// When nothing editable has focus, pasting is a statement of intent — "open
/// this link" — so it triggers [onTrigger] instead of vanishing. While any
/// text field has focus the action reports itself disabled, which makes the
/// shortcut system pass the event on to the field's own paste; this widget
/// must never be the reason paste stops working in an input.
class PasteLinkShortcut extends StatelessWidget {
  final Future<void> Function() onTrigger;
  final Widget child;

  const PasteLinkShortcut({
    super.key,
    required this.onTrigger,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyV, control: true):
            _PasteLinkIntent(),
      },
      child: Actions(
        actions: {_PasteLinkIntent: _PasteLinkAction(onTrigger)},
        child: child,
      ),
    );
  }
}

class _PasteLinkIntent extends Intent {
  const _PasteLinkIntent();
}

class _PasteLinkAction extends Action<_PasteLinkIntent> {
  _PasteLinkAction(this.onTrigger);

  final Future<void> Function() onTrigger;

  @override
  bool get isActionEnabled {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return true;
    // An editable owns its paste. Disabled (not "handled and ignored") is
    // what lets the event keep bubbling to the field's own shortcut.
    return focused.findAncestorStateOfType<EditableTextState>() == null;
  }

  @override
  Object? invoke(_PasteLinkIntent intent) {
    onTrigger();
    return null;
  }
}
