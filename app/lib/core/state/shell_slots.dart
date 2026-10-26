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

  /// [claim] for a list screen with detail pages above it. Opened straight
  /// at a detail (a deep link, a notification), the list beneath is built
  /// in the same frame and would claim after the detail, covering its title
  /// and back arrow. A screen that is not the front page files its claim
  /// underneath instead, ready for when the detail closes.
  void claimFrom(BuildContext context, WidgetBuilder builder) {
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    runInAction(() {
      _claims.remove(builder);
      if (onTop) {
        _claims.add(builder);
      } else {
        _claims.insert(0, builder);
      }
    });
  }

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

/// Marks the detail side of a list-and-detail split, such as Shared on a wide
/// window.
///
/// In a split the list keeps its own controls (its search) inside its pane,
/// and the top bar belongs to the detail beside it: the detail claims
/// [ShellSlots.title] as usual, and leaves out its back arrow, since the list
/// it would go back to is already on screen.
class ShellSplitPane extends InheritedWidget {
  const ShellSplitPane({super.key, required super.child});

  /// Whether [context] sits in a split's detail pane. Safe to ask outside a
  /// build — from a title builder, say — as it takes no dependency.
  static bool contains(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellSplitPane>() != null;

  @override
  bool updateShouldNotify(ShellSplitPane oldWidget) => false;
}
