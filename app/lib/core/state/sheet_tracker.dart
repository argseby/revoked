import 'package:mobx/mobx.dart';

/// How many modal sheets are on screen. The shell's floating button reads it
/// to get out of the way — a FAB hovering over a half-height sheet's actions
/// is the overlap this exists to prevent.
class SheetTracker {
  SheetTracker._();

  static final Observable<int> _open = Observable(0);

  static bool get anyOpen => _open.value > 0;

  static void opened() => runInAction(() => _open.value++);

  static void closed() =>
      runInAction(() => _open.value = _open.value > 0 ? _open.value - 1 : 0);
}
