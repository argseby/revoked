import 'package:flutter/widgets.dart';
import 'package:mobx/mobx.dart';

/// One screen-owned control in the shell's top bar. A screen claims the slot
/// on entry and releases it on exit.
///
/// Claims stack: a detail page opened over its list (a record over the
/// vault) claims on top, and releasing it hands the slot back to the list
/// still mounted underneath — which never claims again, because it was never
/// rebuilt. Releasing removes only that screen's own claim, so a late dispose
/// cannot wipe the slot the next screen already claimed.
///
/// The slot holds a builder rather than a widget on purpose: the shell calls
/// it inside an `Observer`, so whatever the screen reads to build it — a
/// record count, an editing flag — keeps the bar in step with the store.
class ShellSlot {
  final ObservableList<WidgetBuilder> _claims = ObservableList();

  WidgetBuilder? get builder => _claims.isEmpty ? null : _claims.last;

  void claim(WidgetBuilder builder) => runInAction(() {
    _claims
      ..remove(builder)
      ..add(builder);
  });

  void release(WidgetBuilder builder) =>
      runInAction(() => _claims.remove(builder));
}

/// What the active screen puts in the shell's top bar.
class ShellSlots {
  ShellSlots._();

  /// The screen's name, search or count, on the left. On Settings the
  /// workspace switcher stands in while no page has claimed it.
  static final ShellSlot title = ShellSlot();

  /// The screen's one transient action — Vault's "Done" while a section is
  /// being edited.
  static final ShellSlot action = ShellSlot();
}
