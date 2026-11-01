import 'package:mobx/mobx.dart';

part 'load_state.g.dart';

/// How a store's list stands: whether it has ever loaded, whether it is fresh
/// enough to show without asking again, and whether the last try failed.
class LoadState = _LoadState with _$LoadState;

abstract class _LoadState with Store {
  /// How long a list counts as current, so moving between screens doesn't
  /// refetch. A change made here doesn't wait for this: see [invalidate].
  static const freshFor = Duration(seconds: 30);

  final DateTime Function() _now;

  _LoadState({DateTime Function()? now}) : _now = now ?? DateTime.now;

  @observable
  bool hasLoaded = false;

  /// Why the last load failed, while nothing newer has replaced it.
  @observable
  String? error;

  DateTime? _loadedAt;
  int _latest = 0;
  int _staleBefore = 0;
  bool _inFlight = false;

  /// Nothing has arrived yet and nothing has gone wrong: there is no telling
  /// an empty list from one still on its way.
  @computed
  bool get isFirstLoad => !hasLoaded && error == null;

  bool get isDue {
    if (_inFlight) return false;
    final at = _loadedAt;
    return at == null || _now().difference(at) >= _LoadState.freshFor;
  }

  /// Starts a load and returns its ticket. Only the newest ticket may write to
  /// the store, so a slow answer can't overwrite a newer one, or put one
  /// account's rows back after [reset] emptied them for the next.
  @action
  int begin() {
    _inFlight = true;
    error = null;
    return ++_latest;
  }

  bool isCurrent(int ticket) => ticket == _latest;

  @action
  void succeed(int ticket) {
    if (!isCurrent(ticket)) return;
    _inFlight = false;
    hasLoaded = true;
    // A write that landed while this was on its way may be missing from it.
    _loadedAt = ticket >= _staleBefore ? _now() : null;
  }

  @action
  void fail(int ticket, String message) {
    if (!isCurrent(ticket)) return;
    _inFlight = false;
    error = message;
  }

  /// Makes the next visit fetch again. What's on screen stays until it does.
  void invalidate() {
    _loadedAt = null;
    _staleBefore = _latest + 1;
  }

  /// Forgets everything, and disowns any load still on its way.
  @action
  void reset() {
    _latest++;
    _inFlight = false;
    hasLoaded = false;
    error = null;
    _loadedAt = null;
  }
}
