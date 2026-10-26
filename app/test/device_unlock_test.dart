import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

import 'package:revoked_app/core/services/device_unlock.dart';

class _Auth implements LocalAuthentication {
  final Future<bool> Function() answer;
  final reasons = <String>[];
  _Auth(this.answer);

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) {
    reasons.add(localizedReason);
    return answer();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The person proves it is them with the system's own prompt before an
/// approval. A dismissed prompt approves nothing, and a device that cannot
/// ask is told so; only Linux, which has no prompt, relies on the device key
/// alone.
void main() {
  SystemDeviceUnlock on(TargetPlatform platform, _Auth auth) =>
      SystemDeviceUnlock(auth: auth, platform: platform);

  Never fail(LocalAuthExceptionCode code) =>
      throw LocalAuthException(code: code);

  test('the system prompt decides, with the reason shown', () async {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      final yes = _Auth(() async => true);
      expect(await on(platform, yes).confirm('Sign in to a.example'), isTrue);
      expect(yes.reasons, ['Sign in to a.example'], reason: '$platform');
      expect(
        await on(platform, _Auth(() async => false)).confirm('x'),
        isFalse,
      );
    }
  });

  test('Linux has no prompt and relies on the device key alone', () async {
    final auth = _Auth(() async => false);
    expect(await on(TargetPlatform.linux, auth).confirm('x'), isTrue);
    expect(auth.reasons, isEmpty);
  });

  test('dismissing the prompt confirms nothing', () async {
    for (final code in [
      LocalAuthExceptionCode.userCanceled,
      LocalAuthExceptionCode.systemCanceled,
      LocalAuthExceptionCode.timeout,
    ]) {
      final unlock = on(TargetPlatform.android, _Auth(() async => fail(code)));
      expect(await unlock.confirm('x'), isFalse, reason: '$code');
    }
  });

  test('a device that cannot ask says why, and confirms nothing', () async {
    for (final code in [
      LocalAuthExceptionCode.noCredentialsSet,
      LocalAuthExceptionCode.biometricLockout,
      LocalAuthExceptionCode.uiUnavailable,
    ]) {
      final unlock = on(TargetPlatform.iOS, _Auth(() async => fail(code)));
      await expectLater(
        unlock.confirm('x'),
        throwsA(isA<DeviceUnlockException>()),
        reason: '$code',
      );
    }
    final broken = on(
      TargetPlatform.windows,
      _Auth(() async => throw MissingPluginException()),
    );
    await expectLater(
      broken.confirm('x'),
      throwsA(isA<DeviceUnlockException>()),
    );
  });
}
