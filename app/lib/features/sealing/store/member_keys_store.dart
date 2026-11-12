import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/services/secure_storage.dart';

part 'member_keys_store.g.dart';

/// What this device makes of another member's device list.
enum MemberKeyState {
  /// They have not turned on end-to-end encryption.
  notSetUp,

  /// Their list contains something that does not check out. Nothing is ever
  /// handed to it.
  broken,

  /// First seen now or earlier, and consistent since; nobody has compared
  /// fingerprints. Trusting it trusts the server's word that these are theirs.
  trusted,

  /// The person compared fingerprints with them and confirmed they match.
  verified,

  /// Not the list this device saw before: it starts somewhere else, lost
  /// entries, or took another turn. They may have started over, or the server
  /// is showing a list of its own. Untrusted until the person decides.
  changed,
}

/// One member as this device sees them.
class MemberKeys {
  final String user;
  final String email;
  final bool isSelf;

  /// The server's word on whether they may read the vault.
  final bool canRead;

  /// The server's word on whether they may hand the key to others.
  final bool canGrant;

  /// The server's word on whether any of their devices holds the current key.
  final bool holdsKey;
  final MemberKeyState state;

  /// Six groups of five digits, or null when they have no list. For a changed
  /// member, the fingerprint of the list served now.
  final String? fingerprint;

  /// The fingerprint this device remembered, when the list changed.
  final String? previousFingerprint;

  /// The checked list, for whatever later hands them a key.
  final VerifiedChain chain;

  const MemberKeys({
    required this.user,
    required this.email,
    required this.isSelf,
    required this.canRead,
    required this.state,
    required this.fingerprint,
    required this.chain,
    this.canGrant = false,
    this.holdsKey = false,
    this.previousFingerprint,
  });

  /// Whether a key may be handed to this list at all, verified or not.
  bool get usable =>
      state == MemberKeyState.trusted || state == MemberKeyState.verified;

  /// Whether they wait for the key: they may read, their list checks out, and
  /// none of their devices holds it.
  bool get waiting => canRead && !holdsKey && !isSelf;

  MemberKeys withState(MemberKeyState next) => MemberKeys(
    user: user,
    email: email,
    isSelf: isSelf,
    canRead: canRead,
    canGrant: canGrant,
    holdsKey: holdsKey,
    state: next,
    fingerprint: fingerprint,
    previousFingerprint: next == MemberKeyState.changed
        ? previousFingerprint
        : null,
    chain: chain,
  );
}

/// Where a person's list started and had got to when this device last looked,
/// and whether their fingerprint was compared. Kept per person, not per
/// workspace: their keys are the same everywhere.
class _MemberPin {
  String root;
  int headSeq;
  String headHash;
  bool verified;

  _MemberPin({
    required this.root,
    required this.headSeq,
    required this.headHash,
    this.verified = false,
  });

  Map<String, dynamic> toJson() => {
    'root': root,
    'headSeq': headSeq,
    'headHash': headHash,
    'verified': verified,
  };

  factory _MemberPin.fromJson(Map<String, dynamic> json) => _MemberPin(
    root: json['root'] as String? ?? '',
    headSeq: (json['headSeq'] as num?)?.toInt() ?? 0,
    headHash: json['headHash'] as String? ?? '',
    verified: json['verified'] == true,
  );
}

class MemberKeysStore = _MemberKeysStore with _$MemberKeysStore;

/// Checks other members' device lists and remembers them (design/e2ee-sharing.md
/// §2.3): the first list seen for a person is pinned, and anything that does
/// not grow from it afterwards is a change the person has to look at. Hands
/// out nothing itself; a grant later reads [members] to know whom it may trust.
abstract class _MemberKeysStore with Store {
  final ApiClient _api;
  final String Function() _currentUser;
  final Uint8List? Function() _ownRoot;
  final FlutterSecureStorage _storage;

  _MemberKeysStore(
    this._api, {
    required this._currentUser,
    required this._ownRoot,
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? createSecureStorage();

  final ObservableList<MemberKeys> members = ObservableList<MemberKeys>();

  @observable
  String? workspace;

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  Map<String, _MemberPin> _pins = {};
  String? _pinsReadFor;
  Future<void>? _pinWrites;

  String get _storageKey =>
      'sealed_members_${_api.originAuthority}_${_currentUser()}';

  /// Members whose list changed since this device last saw it.
  @computed
  List<MemberKeys> get changed => [
    for (final m in members)
      if (m.state == MemberKeyState.changed) m,
  ];

  MemberKeys? byUser(String user) {
    for (final m in members) {
      if (m.user == user) return m;
    }
    return null;
  }

  /// What [membersOf] answered last, per workspace, and when.
  final Map<String, (DateTime, List<MemberKeys>)> _fetched = {};

  /// How long [membersOf] answers from what it fetched last.
  static const _fresh = Duration(seconds: 30);

  @action
  Future<void> load(String workspaceId) async {
    isLoading = true;
    errorMessage = null;
    try {
      final next = await _fetch(workspaceId);
      runInAction(() {
        workspace = workspaceId;
        members
          ..clear()
          ..addAll(next);
      });
    } catch (e) {
      errorMessage = describeError(e);
    } finally {
      isLoading = false;
    }
  }

  /// Every member of [workspaceId], checked against what this device pinned,
  /// for whatever needs to hand them a key or check one they handed over.
  /// Fetched again once what it has is more than a few seconds old, or with
  /// [fresh].
  Future<List<MemberKeys>> membersOf(
    String workspaceId, {
    bool fresh = false,
  }) async {
    final cached = _fetched[workspaceId];
    if (!fresh &&
        cached != null &&
        DateTime.now().difference(cached.$1) < _fresh) {
      return cached.$2;
    }
    return _fetch(workspaceId);
  }

  Future<List<MemberKeys>> _fetch(String workspaceId) async {
    await _readPins();
    final data =
        await _api.get('/api/sealed/workspaces/$workspaceId/members')
            as Map<String, dynamic>;
    final next = <MemberKeys>[];
    for (final raw in (data['members'] as List<dynamic>? ?? const [])) {
      next.add(_check(raw as Map<String, dynamic>));
    }
    next.sort((a, b) {
      if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
      return a.email.compareTo(b.email);
    });
    await _savePins();
    _fetched[workspaceId] = (DateTime.now(), next);
    return next;
  }

  /// Puts one member's new state everywhere this store shows them.
  void _update(String user, MemberKeys Function(MemberKeys) change) {
    runInAction(() {
      for (var i = 0; i < members.length; i++) {
        if (members[i].user == user) members[i] = change(members[i]);
      }
    });
    for (final entry in _fetched.entries.toList()) {
      _fetched[entry.key] = (
        entry.value.$1,
        [for (final m in entry.value.$2) m.user == user ? change(m) : m],
      );
    }
  }

  /// The person compared fingerprints with [user] and they matched.
  @action
  Future<void> markVerified(String user) async {
    final member = byUser(user);
    final pin = _pins[user];
    if (member == null || pin == null || !member.usable) return;
    pin.verified = true;
    await _savePins();
    _update(user, (m) => m.withState(MemberKeyState.verified));
  }

  /// Takes back a verification, for a comparison that was made in error.
  @action
  Future<void> clearVerified(String user) async {
    final member = byUser(user);
    final pin = _pins[user];
    if (member == null || pin == null) return;
    pin.verified = false;
    await _savePins();
    _update(
      user,
      (m) => m.state == MemberKeyState.verified
          ? m.withState(MemberKeyState.trusted)
          : m,
    );
  }

  /// The person accepts [user]'s changed list as theirs, for example after
  /// they started over. It is pinned afresh and is not verified.
  @action
  Future<void> acceptChange(String user) async {
    final member = byUser(user);
    if (member == null ||
        member.state != MemberKeyState.changed ||
        member.chain.broken ||
        member.chain.entries.isEmpty) {
      return;
    }
    _pins[user] = _pinFor(member.chain);
    await _savePins();
    _update(user, (m) => m.withState(MemberKeyState.trusted));
  }

  @action
  void forgetSession() {
    members.clear();
    workspace = null;
    errorMessage = null;
    _pins = {};
    _pinsReadFor = null;
    _fetched.clear();
  }

  MemberKeys _check(Map<String, dynamic> row) {
    final user = row['user'] as String? ?? '';
    final isSelf = row['isSelf'] == true || user == _currentUser();
    final served = <DeviceChainEntry>[];
    var unreadable = false;
    for (final e in (row['devices'] as List<dynamic>? ?? const [])) {
      try {
        served.add(DeviceChainEntry.fromJson(e as Map<String, dynamic>));
      } on FormatException {
        unreadable = true;
        break;
      } on TypeError {
        unreadable = true;
        break;
      }
    }
    final verified = VerifiedChain.verify(user, served);
    final chain = unreadable && !verified.broken
        ? VerifiedChain(verified.entries, broken: true)
        : verified;

    MemberKeys result(
      MemberKeyState state, {
      String? fingerprint,
      String? previous,
    }) => MemberKeys(
      user: user,
      email: row['email'] as String? ?? '',
      isSelf: isSelf,
      canRead: row['canRead'] == true,
      canGrant: row['canGrant'] == true,
      holdsKey: row['holdsKey'] == true,
      state: state,
      fingerprint: fingerprint,
      previousFingerprint: previous,
      chain: chain,
    );

    if (served.isEmpty && !unreadable) {
      // A pinned person with no list any more started over, or is hidden.
      final pin = isSelf ? null : _pins[user];
      return pin == null
          ? result(MemberKeyState.notSetUp)
          : result(
              MemberKeyState.changed,
              previous: _fingerprintOf(user, pin.root),
            );
    }
    if (chain.entries.isEmpty) return result(MemberKeyState.broken);

    final root = chain.entries.first.hash;
    final fingerprint = SealedFormats.memberFingerprint(user, root);

    if (isSelf) {
      // This device's own list is checked and pinned elsewhere. What matters
      // here is that others are shown the same start.
      final own = _ownRoot();
      if (own == null) {
        return result(
          chain.broken ? MemberKeyState.broken : MemberKeyState.trusted,
          fingerprint: fingerprint,
        );
      }
      if (!_same(own, root)) {
        return result(
          MemberKeyState.changed,
          fingerprint: fingerprint,
          previous: SealedFormats.memberFingerprint(user, own),
        );
      }
      return result(
        chain.broken ? MemberKeyState.broken : MemberKeyState.verified,
        fingerprint: fingerprint,
      );
    }

    final pin = _pins[user];
    if (pin == null) {
      if (chain.broken) {
        return result(MemberKeyState.broken, fingerprint: fingerprint);
      }
      _pins[user] = _pinFor(chain);
      return result(MemberKeyState.trusted, fingerprint: fingerprint);
    }

    final previous = _fingerprintOf(user, pin.root);
    if (SealedFormats.encode(root) != pin.root) {
      return result(
        MemberKeyState.changed,
        fingerprint: fingerprint,
        previous: previous,
      );
    }
    // The same start must lead through where this device last saw it: fewer
    // entries is a rollback, another entry at that point a fork.
    final seen = chain.bySeq(pin.headSeq);
    if (chain.headSeq < pin.headSeq ||
        seen == null ||
        SealedFormats.encode(seen.hash) != pin.headHash) {
      return result(
        MemberKeyState.changed,
        fingerprint: fingerprint,
        previous: previous,
      );
    }
    if (chain.broken) {
      return result(MemberKeyState.broken, fingerprint: fingerprint);
    }
    pin
      ..headSeq = chain.headSeq
      ..headHash = SealedFormats.encode(chain.headHash);
    return result(
      pin.verified ? MemberKeyState.verified : MemberKeyState.trusted,
      fingerprint: fingerprint,
    );
  }

  static _MemberPin _pinFor(VerifiedChain chain) => _MemberPin(
    root: SealedFormats.encode(chain.entries.first.hash),
    headSeq: chain.headSeq,
    headHash: SealedFormats.encode(chain.headHash),
  );

  static String? _fingerprintOf(String user, String root) {
    try {
      return SealedFormats.memberFingerprint(user, SealedFormats.decode(root));
    } on FormatException {
      return null;
    }
  }

  Future<void> _readPins() async {
    final key = _storageKey;
    if (_pinsReadFor == key) return;
    final raw = await _storage.read(key: key);
    _pins = raw == null
        ? {}
        : (jsonDecode(raw) as Map<String, dynamic>).map(
            (k, v) =>
                MapEntry(k, _MemberPin.fromJson(v as Map<String, dynamic>)),
          );
    _pinsReadFor = key;
  }

  /// One write at a time, so an older snapshot can't land after a newer one.
  Future<void> _savePins() {
    final key = _storageKey;
    final snapshot = jsonEncode(_pins.map((k, v) => MapEntry(k, v.toJson())));
    Future<void> write() => _storage.write(key: key, value: snapshot);
    final previous = _pinWrites;
    final done = previous == null ? write() : previous.then((_) => write());
    _pinWrites = done;
    return done;
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
