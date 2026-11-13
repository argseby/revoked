import 'package:flutter/services.dart';

import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';

/// How many digits an authenticator app shows.
const totpDigits = 6;

/// The code someone typed or pasted, as the server takes it: the digits
/// alone. Spaces and dashes (authenticator apps group the digits) are
/// dropped; anything else, or a count other than [totpDigits], is not a code
/// and gives null.
String? normalizeTotpCode(String input) {
  final digits = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    if (RegExp(r'[0-9]').hasMatch(ch)) {
      digits.write(ch);
    } else if (ch == ' ' || ch == '-' || ch == '\t') {
      continue;
    } else {
      return null;
    }
  }
  final code = digits.toString();
  return code.length == totpDigits ? code : null;
}

/// A secret grouped in fours, the way it is easier to read off a screen and
/// type into an authenticator app. The app ignores the spaces.
String groupTotpSecret(String secret) {
  final clean = secret.replaceAll(' ', '');
  final parts = <String>[];
  for (var i = 0; i < clean.length; i += 4) {
    parts.add(clean.substring(i, i + 4 > clean.length ? clean.length : i + 4));
  }
  return parts.join(' ');
}

/// Keeps a code field to digits, at most [totpDigits] of them, so pasting
/// "123 456" lands as the code it is.
class TotpCodeFormatter extends TextInputFormatter {
  const TotpCodeFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > totpDigits) digits = digits.substring(0, totpDigits);
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

/// Whether the signed-in account has an authenticator app, and whether this
/// server requires one.
class TwoFactorStatus {
  final bool enabled;
  final bool required;

  /// Required and not set up yet: the app asks for it before anything else.
  final bool setupRequired;
  final DateTime? enabledAt;

  const TwoFactorStatus({
    required this.enabled,
    required this.required,
    required this.setupRequired,
    this.enabledAt,
  });

  factory TwoFactorStatus.fromJson(Map<String, dynamic> json) {
    final at = json['enabledAt'];
    return TwoFactorStatus(
      enabled: json['enabled'] == true,
      required: json['required'] == true,
      setupRequired: json['setupRequired'] == true,
      enabledAt: at is String ? DateTime.tryParse(at) : null,
    );
  }
}

/// A secret being set up: shown once, as a QR code and as text, until a code
/// from the app confirms it.
class TotpSetup {
  final String secret;
  final String otpauthUri;

  const TotpSetup({required this.secret, required this.otpauthUri});

  factory TotpSetup.fromJson(Map<String, dynamic> json) => TotpSetup(
    secret: json['secret'] as String? ?? '',
    otpauthUri: json['otpauthUri'] as String? ?? '',
  );
}

/// The server's two-factor routes for the signed-in account.
class TwoFactorApi {
  final ApiClient _api;

  const TwoFactorApi(this._api);

  Future<TwoFactorStatus> status() async => TwoFactorStatus.fromJson(
    (await _api.get('/api/2fa')) as Map<String, dynamic>,
  );

  Future<TotpSetup> setup() async => TotpSetup.fromJson(
    (await _api.post('/api/2fa/totp/setup')) as Map<String, dynamic>,
  );

  /// Turning it on ends every other session, this one included: the answer
  /// carries a fresh token for this device, kept here so the app stays
  /// signed in.
  Future<TwoFactorStatus> confirm(String code) async {
    final data = (await _api.post(
      '/api/2fa/totp/confirm',
      body: {'code': code},
    )) as Map<String, dynamic>;
    final token = data['token'];
    final user = _api.userData;
    if (token is String && token.isNotEmpty && user != null) {
      await _api.saveAuthState(token, user);
    }
    return TwoFactorStatus.fromJson(data);
  }

  Future<TwoFactorStatus> disable(String code) async =>
      TwoFactorStatus.fromJson(
        (await _api.delete('/api/2fa/totp', body: {'code': code}))
            as Map<String, dynamic>,
      );
}

/// The challenge in a passkey sign-in the server answered with
/// `two_factor_required`, or null for any other failure.
String? twoFactorChallengeOf(Object error) {
  if (error is! ApiException || error.code != AppErrorCode.twoFactorRequired) {
    return null;
  }
  final challenge = error.data?['challenge'];
  return challenge is String && challenge.isNotEmpty ? challenge : null;
}

/// What to say about a code the server refused.
String describeTwoFactorError(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case AppErrorCode.twoFactorCodeInvalid:
        return 'This code is not the one the authenticator app shows right '
            'now.';
      case AppErrorCode.twoFactorChallengeInvalid:
        return 'This sign-in has expired. Signing in starts again with the '
            'passkey.';
      case AppErrorCode.twoFactorEnforced:
        return 'This server requires two-factor authentication.';
    }
  }
  return describeError(error);
}
