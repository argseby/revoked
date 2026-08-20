import 'package:flutter/widgets.dart';
import 'package:mobx/mobx.dart';

/// A [TextEditingController] whose text is a MobX observable.
///
/// A plain controller notifies its own listeners and nothing else, so a store
/// that owns one can expose `controller.text` to a view and the view will
/// never rebuild when the user types — every `canSave` getter reading it stays
/// frozen at its initial value. Reading [text] or [value] inside an `Observer`
/// subscribes to it; every store controller is one of these.
class ObservableTextController extends TextEditingController {
  ObservableTextController({super.text});

  final Observable<int> _revision = Observable(0);

  @override
  TextEditingValue get value {
    _revision.value;
    return super.value;
  }

  @override
  set value(TextEditingValue newValue) {
    final changed = newValue.text != super.value.text;
    super.value = newValue;
    // Selection and composing changes move the caret without changing what
    // was typed; rebuilding the sheet for those would fight the caret.
    if (changed) runInAction(() => _revision.value++);
  }
}
