import 'package:flutter/widgets.dart';
import 'package:mobx/mobx.dart';

/// The screen-owned control the shell's top bar renders beside the bell —
/// today the active screen's filter button. A screen registers on entry and
/// unregisters on exit; clearing is guarded so a late dispose cannot wipe the
/// slot the next screen already claimed.
class ShellSlots {
  ShellSlots._();

  static final Observable<WidgetBuilder?> _filter = Observable(null);

  static WidgetBuilder? get filter => _filter.value;

  static void setFilter(WidgetBuilder builder) =>
      runInAction(() => _filter.value = builder);

  static void clearFilter(WidgetBuilder builder) => runInAction(() {
    if (_filter.value == builder) _filter.value = null;
  });
}
