import 'package:flutter/widgets.dart';
import 'package:mobx/mobx.dart';

/// One screen-owned control in the shell's top bar. A screen claims the slot
/// on entry and releases it on exit; releasing is guarded so a late dispose
/// cannot wipe the slot the next screen already claimed.
///
/// The slot holds a builder rather than a widget on purpose: the shell calls
/// it inside an `Observer`, so whatever the screen reads to build it — a
/// record count, an editing flag — keeps the bar in step with the store.
class ShellSlot {
  final Observable<WidgetBuilder?> _builder = Observable(null);

  WidgetBuilder? get builder => _builder.value;

  void claim(WidgetBuilder builder) =>
      runInAction(() => _builder.value = builder);

  void release(WidgetBuilder builder) => runInAction(() {
    if (_builder.value == builder) _builder.value = null;
  });
}

/// What the active screen puts in the shell's top bar.
class ShellSlots {
  ShellSlots._();

  /// The screen's name and count, on the left. The workspace switcher takes
  /// this space on Settings, which is the only tab that acts on it.
  static final ShellSlot title = ShellSlot();

  /// The screen's one transient action — Vault's "Done" while a section is
  /// being edited — sitting left of the filter.
  static final ShellSlot action = ShellSlot();

  static final ShellSlot filter = ShellSlot();
}
