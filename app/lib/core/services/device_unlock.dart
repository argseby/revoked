import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Asks the person in front of the device to prove it is them — fingerprint,
/// face or device PIN — before an action only they may take, such as
/// approving a sign-in at a service.
///
/// The session and the identity key say which device and account this is;
/// this says the owner is holding it.
abstract interface class DeviceUnlock {
  /// Whether the person confirmed. [reason] is shown in the system prompt.
  ///
  /// False means they dismissed the prompt. A device that cannot ask at all —
  /// no screen lock set up, locked out after too many attempts — throws a
  /// [DeviceUnlockException] that says what to do about it.
  Future<bool> confirm(String reason);
}

/// Why the device could not ask, in words for the person.
class DeviceUnlockException implements Exception {
  final String message;
  const DeviceUnlockException(this.message);

  @override
  String toString() => message;
}

/// The system's own prompt: Face ID or Touch ID on Apple devices, the
/// biometric prompt on Android, Windows Hello on Windows — each falling back
/// to the device PIN or password.
///
/// Linux has no such prompt. There the identity key on the device is the
/// only proof, and [confirm] answers yes without asking.
class SystemDeviceUnlock implements DeviceUnlock {
  final LocalAuthentication _auth;
  final bool _supported;

  SystemDeviceUnlock({LocalAuthentication? auth, TargetPlatform? platform})
    : _auth = auth ?? LocalAuthentication(),
      _supported = !kIsWeb && supports(platform ?? defaultTargetPlatform);

  /// Whether [platform] has a system prompt to ask with.
  static bool supports(TargetPlatform platform) => switch (platform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.linux || TargetPlatform.fuchsia => false,
  };

  @override
  Future<bool> confirm(String reason) async {
    if (!_supported) return true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // Switching apps mid-prompt — to a password manager, say — retries
        // instead of failing.
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (e) {
      switch (e.code) {
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
        case LocalAuthExceptionCode.timeout:
        case LocalAuthExceptionCode.authInProgress:
          return false;
        case LocalAuthExceptionCode.noCredentialsSet:
        case LocalAuthExceptionCode.noBiometricsEnrolled:
        case LocalAuthExceptionCode.noBiometricHardware:
          throw const DeviceUnlockException(
            'This device has no screen lock. Set up a PIN, password, '
            'fingerprint or face unlock in the system settings, then try '
            'again.',
          );
        case LocalAuthExceptionCode.temporaryLockout:
        case LocalAuthExceptionCode.biometricLockout:
          throw const DeviceUnlockException(
            'Too many attempts. Unlock the device with its PIN or password, '
            'then try again.',
          );
        default:
          throw const DeviceUnlockException(_couldNotAsk);
      }
    } catch (_) {
      // A plugin that is missing or failed: nothing was confirmed.
      throw const DeviceUnlockException(_couldNotAsk);
    }
  }

  static const _couldNotAsk =
      'This device could not ask for your fingerprint, face or PIN. Try again.';
}
