import 'package:mobx/mobx.dart';

/// One piece of widget-local state that no store should own — a disclosure
/// triangle, a password reveal, a column sort.
///
/// Reading [value] inside an `Observer` subscribes to it, so assigning a new
/// value rebuilds without `setState`. Hold it as a `final` field on a `State`
/// so it survives rebuilds; anything a screen or a feature cares about belongs
/// in a store instead.
class Local<T> {
  Local(T initial) : _observable = Observable(initial);

  final Observable<T> _observable;

  T get value => _observable.value;

  set value(T next) => runInAction(() => _observable.value = next);
}
