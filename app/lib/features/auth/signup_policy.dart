import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/stores.dart';

/// Whether the server lets anyone make an account, read from its public info.
abstract final class SignupPolicy {
  static final Observable<bool?> _open = Observable(null);

  /// A server too old to say is assumed open: its page then gives the answer.
  static bool get open => _open.value ?? true;

  /// A failure leaves the assumption in place.
  static Future<void> load() async {
    bool? next;
    try {
      final info = await Stores.api.get('/api/server');
      final signups = info is Map<String, dynamic> ? info['signups'] : null;
      if (signups is Map<String, dynamic>) next = signups['open'] == true;
    } catch (_) {
      next = null;
    }
    runInAction(() => _open.value = next);
  }
}
