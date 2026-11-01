import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/state/load_state.dart';

void main() {
  late DateTime now;
  late LoadState state;

  setUp(() {
    now = DateTime(2026, 11, 1);
    state = LoadState(now: () => now);
  });

  test('is due until it has loaded, then fresh for 30 seconds', () {
    expect(state.isDue, isTrue);
    expect(state.isFirstLoad, isTrue);

    state.succeed(state.begin());
    expect(state.isDue, isFalse);
    expect(state.hasLoaded, isTrue);
    expect(state.isFirstLoad, isFalse);

    now = now.add(const Duration(seconds: 29));
    expect(state.isDue, isFalse);
    now = now.add(const Duration(seconds: 1));
    expect(state.isDue, isTrue);
  });

  test('is not due while a load is on its way', () {
    state.begin();
    expect(state.isDue, isFalse);
  });

  test('a failed load is due again, and says why', () {
    state.fail(state.begin(), 'No connection');
    expect(state.isDue, isTrue);
    expect(state.error, 'No connection');
    expect(state.isFirstLoad, isFalse);

    state.begin();
    expect(state.error, isNull);
  });

  test('a failed refresh still counts as having loaded', () {
    state.succeed(state.begin());
    state.fail(state.begin(), 'No connection');
    expect(state.hasLoaded, isTrue);
  });

  test('invalidate makes it due without forgetting it has loaded', () {
    state.succeed(state.begin());
    state.invalidate();
    expect(state.isDue, isTrue);
    expect(state.hasLoaded, isTrue);
  });

  test('a write during a load leaves that load stale', () {
    final ticket = state.begin();
    state.invalidate();
    state.succeed(ticket);
    expect(state.isDue, isTrue, reason: 'it may be missing the write');
    expect(state.hasLoaded, isTrue);
  });

  test('only the newest load counts', () {
    final older = state.begin();
    final newer = state.begin();
    expect(state.isCurrent(older), isFalse);
    expect(state.isCurrent(newer), isTrue);

    state.fail(older, 'Too late');
    expect(state.error, isNull);
  });

  test('reset disowns a load still on its way', () {
    final ticket = state.begin();
    state.reset();
    expect(state.isCurrent(ticket), isFalse);

    state.succeed(ticket);
    expect(state.hasLoaded, isFalse);
    expect(state.isDue, isTrue);
  });
}
