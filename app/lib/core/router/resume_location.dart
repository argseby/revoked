import 'dart:async';
import 'dart:convert';

import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where a link was headed when it met a missing account or workspace.
///
/// A tool's proposal opens the app at `/p`, and someone new has to sign up and
/// set up a workspace before it can be answered. The router used to send them
/// to the vault afterwards, so the proposal was dropped on the way and they had
/// to go back to the tool and start over. This holds it until setup is done.
///
/// Kept on disk as well: signing up happens in the browser, and the system may
/// close the app while the person fetches the code from their mail.
abstract final class ResumeLocation {
  static const _key = 'resume_location';

  /// Long enough for a sign-up with a mailed code, short enough that a link
  /// abandoned today does not open itself next week.
  static const ttl = Duration(minutes: 30);

  /// Observable, so a screen already showing when a link is held - the
  /// login screen, when the app was open before the link was clicked - says
  /// so without waiting for a rebuild.
  static final _held = Observable<({String location, DateTime at})?>(null);

  /// The kinds of link worth carrying through setup: each asks the person to
  /// decide something, and each is lost if they have to find it again.
  static bool isResumable(String location) {
    final path = Uri.tryParse(location)?.path ?? '';
    return path == '/p' ||
        path == '/connect' ||
        path == '/present' ||
        path.startsWith('/i/') ||
        path.startsWith('/a/');
  }

  /// Reads what an earlier run held. Called once at startup.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final location = data['location'] as String?;
      final at = DateTime.fromMillisecondsSinceEpoch(data['at'] as int? ?? 0);
      if (location == null || !isResumable(location)) return;
      runInAction(() => _held.value = (location: location, at: at));
    } catch (_) {
      // Unreadable is the same as nothing held.
    }
  }

  /// Holds [location] if it is a kind worth resuming; anything else is left
  /// alone, so a later plain navigation cannot replace a held proposal.
  static void hold(String location) {
    if (!isResumable(location)) return;
    runInAction(() => _held.value = (location: location, at: DateTime.now()));
    unawaited(_write());
  }

  /// What is held and still fresh, without giving it up. Safe to read while
  /// building: a stale link is ignored here and dropped by [take].
  static String? peek() {
    final held = _held.value;
    if (held == null || DateTime.now().difference(held.at) > ttl) return null;
    return held.location;
  }

  /// What is held, given up: a link resumes once.
  static String? take() {
    final location = peek();
    if (_held.value != null) clear();
    return location;
  }

  static void clear() {
    runInAction(() => _held.value = null);
    unawaited(_write());
  }

  /// One line for the screens in between, saying what comes after them.
  static String? describe() {
    final path = Uri.tryParse(peek() ?? '')?.path;
    if (path == null || path.isEmpty) return null;
    if (path == '/p') {
      return 'Afterwards, you continue with the link proposal you opened.';
    }
    if (path == '/connect') {
      return 'Afterwards, you continue connecting the tool you came from.';
    }
    if (path == '/present') {
      return 'Afterwards, you continue with the attestation a service asked '
          'to see.';
    }
    if (path.startsWith('/a/')) {
      return 'Afterwards, you continue with the attestation you were offered.';
    }
    return 'Afterwards, you continue with the invite you opened.';
  }

  static Future<void> _write() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final held = _held.value;
      if (held == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(
          _key,
          jsonEncode({
            'location': held.location,
            'at': held.at.millisecondsSinceEpoch,
          }),
        );
      }
    } catch (_) {
      // Without storage it is held for this run only.
    }
  }
}
