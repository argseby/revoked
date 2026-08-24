import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The app's single [FlutterSecureStorage] configuration.
///
/// Every secret the client keeps — session tokens, cached account records,
/// identity private keys — goes through here, because the options are not
/// merely a preference on macOS: the wrong ones make the keychain unusable.
///
/// macOS: the plugin defaults to the data-protection keychain, which is only
/// reachable by an app signed into a keychain access group — that means a
/// `keychain-access-groups` entitlement backed by a real Apple developer team.
/// A local `flutter run` builds an ad-hoc signature with no team, so every
/// read and write fails with `-34018` ("A required entitlement is not
/// present.") and the app can neither restore nor store a session. The legacy
/// file-based keychain has no such requirement and works for the sandboxed
/// app as-is, so dev builds stay functional without provisioning.
///
/// The option is macOS-only; iOS, Android, Linux and Windows are unaffected.
FlutterSecureStorage createSecureStorage() => const FlutterSecureStorage(
  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
);
