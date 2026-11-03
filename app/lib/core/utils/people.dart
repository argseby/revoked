import 'package:revoked_app/core/stores.dart';

/// The address a workspace member is known by, or null while the member list
/// has not loaded or no longer names them.
String? memberEmail(String userId) {
  if (userId.isEmpty) return null;
  if (userId == Stores.auth.userId) return Stores.auth.currentUser?.email;
  for (final m in Stores.invites.members) {
    if (m.userId == userId) return m.email;
  }
  return null;
}
