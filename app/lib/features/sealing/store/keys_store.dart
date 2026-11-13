import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/crypto/sealing.dart';
import 'package:revoked_app/core/models/passkey.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/services/secure_storage.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/features/sealing/store/member_keys_store.dart';

part 'keys_store.g.dart';

/// Where this device stands with end-to-end encryption.
enum SealingStatus {
  /// Not asked the server yet, or could not reach it.
  unknown,

  /// This server doesn't offer it.
  unavailable,

  /// Nothing set up on this account yet.
  notSetUp,

  /// This device holds its keys and can read and write.
  ready,

  /// The account uses it, but this device isn't on its list.
  needsThisDevice,

  /// A list names this device, but it has no way yet to know the list is the
  /// real one. It trusts nothing until a device it can see confirms it.
  needsConfirmation,

  /// The device list doesn't match what this device knows. Nothing is written
  /// or handed to anyone until the person decides what to do.
  untrusted,
}

/// A workspace's keys as far as this device could open and check them.
class _WorkspaceKeys {
  final Map<int, Uint8List> keys;
  final int currentEpoch;

  /// New values may be encrypted under the current key: this device holds it,
  /// a device still on the list handed it over after the last removal, and no
  /// new one is due.
  final bool writable;

  /// This device holds the current key, and should replace it.
  final bool mustRotate;

  /// How far the list had got when the current key was first handed over. Passed
  /// on unchanged with the key: giving it a fresh number would make a key from
  /// before a removal look as though it came after.
  final int chainSeq;

  const _WorkspaceKeys({
    required this.keys,
    required this.currentEpoch,
    required this.chainSeq,
    required this.writable,
    required this.mustRotate,
  });
}

class _DeviceKeys {
  final SealingKeyPair hpke;
  final SealingKeyPair signing;

  const _DeviceKeys(this.hpke, this.signing);

  factory _DeviceKeys.generate() =>
      _DeviceKeys(Sealing.generateKeyPair(), Sealing.generateKeyPair());

  Map<String, String> toJson() => {
    'hpkePrivate': SealedFormats.encode(hpke.privateKey),
    'hpkePublic': SealedFormats.encode(hpke.publicKey),
    'signingPrivate': SealedFormats.encode(signing.privateKey),
    'signingPublic': SealedFormats.encode(signing.publicKey),
  };

  factory _DeviceKeys.fromJson(Map<String, dynamic> json) => _DeviceKeys(
    SealingKeyPair(
      privateKey: SealedFormats.decode(json['hpkePrivate'] as String),
      publicKey: SealedFormats.decode(json['hpkePublic'] as String),
    ),
    SealingKeyPair(
      privateKey: SealedFormats.decode(json['signingPrivate'] as String),
      publicKey: SealedFormats.decode(json['signingPublic'] as String),
    ),
  );
}

/// What a device remembers, so a server cannot quietly roll it back: where its
/// device list starts and has got to, the newest key per workspace, and the
/// newest version and key per record.
class _Pins {
  String firstHash;
  int headSeq;
  String headHash;

  /// Setup signed a first entry that may not have reached the server yet, so an
  /// empty list doesn't mean someone wiped it.
  bool setupPending;
  final Map<String, int> epochs;

  /// A hash of each workspace key, by `workspace:epoch`, as first opened from a
  /// device on the list. Nobody can later offer a different key for that epoch.
  final Map<String, String> epochKeys;
  final Map<String, int> versions;
  final Map<String, int> recordEpochs;

  /// The newest entry the person has looked at. Anything later that this device
  /// didn't make itself came from elsewhere, and they should get to look at it.
  int reviewedSeq;

  /// Entries this device made. Making one must not silently approve whatever
  /// else had appeared on the list before it.
  final List<int> ownSeqs;

  /// Records whose owner confirmed stopping encryption, and the version seen.
  final Map<String, int> acceptedPlain;

  _Pins({
    this.firstHash = '',
    this.headSeq = 0,
    this.headHash = '',
    this.setupPending = false,
    this.reviewedSeq = 0,
    List<int>? ownSeqs,
    Map<String, String>? epochKeys,
    Map<String, int>? epochs,
    Map<String, int>? versions,
    Map<String, int>? recordEpochs,
    Map<String, int>? acceptedPlain,
  }) : ownSeqs = ownSeqs ?? [],
       epochKeys = epochKeys ?? {},
       epochs = epochs ?? {},
       versions = versions ?? {},
       recordEpochs = recordEpochs ?? {},
       acceptedPlain = acceptedPlain ?? {};

  bool get isEmpty => firstHash.isEmpty;

  /// What survives rejoining: what this device has seen of its records. A server
  /// that forces a rejoin must not also get to roll those back or downgrade them.
  _Pins keepingRecordHistory() => _Pins(
    versions: versions,
    recordEpochs: recordEpochs,
    acceptedPlain: acceptedPlain,
  );

  Map<String, dynamic> toJson() => {
    'firstHash': firstHash,
    'headSeq': headSeq,
    'headHash': headHash,
    'setupPending': setupPending,
    'reviewedSeq': reviewedSeq,
    'ownSeqs': ownSeqs,
    'epochKeys': epochKeys,
    'epochs': epochs,
    'versions': versions,
    'recordEpochs': recordEpochs,
    'acceptedPlain': acceptedPlain,
  };

  static Map<String, int> _ints(Object? raw) =>
      (raw as Map<String, dynamic>? ?? const {}).map(
        (k, v) => MapEntry(k, (v as num).toInt()),
      );

  factory _Pins.fromJson(Map<String, dynamic> json) => _Pins(
    firstHash: json['firstHash'] as String? ?? '',
    headSeq: (json['headSeq'] as num?)?.toInt() ?? 0,
    headHash: json['headHash'] as String? ?? '',
    setupPending: json['setupPending'] == true,
    reviewedSeq: (json['reviewedSeq'] as num?)?.toInt() ?? 0,
    ownSeqs: [
      for (final seq in (json['ownSeqs'] as List<dynamic>? ?? const []))
        (seq as num).toInt(),
    ],
    epochKeys: (json['epochKeys'] as Map<String, dynamic>? ?? const {}).map(
      (k, v) => MapEntry(k, v as String),
    ),
    epochs: _ints(json['epochs']),
    versions: _ints(json['versions']),
    recordEpochs: _ints(json['recordEpochs']),
    acceptedPlain: _ints(json['acceptedPlain']),
  );
}

/// What a sealed value holds. The value alone isn't enough: the server could swap
/// the labels of two rows, or flip hidden to shown.
class SealedContent {
  final String value;
  final String label;
  final String type;
  final String format;

  /// For an encrypted file: its name, type, size and the key its blob opens
  /// with (design/e2ee-sharing.md §7.2). [value] is then empty.
  final SealedFileInfo? file;

  const SealedContent({
    required this.value,
    required this.label,
    required this.type,
    required this.format,
    this.file,
  });

  String encode() => jsonEncode({
    'v': value,
    'l': label,
    't': type,
    'f': format,
    if (file != null) 'x': file!.toJson(),
  });

  factory SealedContent.decode(String text) {
    final content = tryDecode(text);
    if (content == null) {
      throw const FormatException('This is not a sealed value.');
    }
    return content;
  }

  /// The same for text this device did not write, such as what a link's
  /// address opened: null for anything that is not a value with its label,
  /// type and format, or a file with a complete descriptor.
  static SealedContent? tryDecode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    final value = json['v'], label = json['l'];
    final type = json['t'], format = json['f'];
    if (value is! String ||
        label is! String ||
        type is! String ||
        format is! String) {
      return null;
    }
    SealedFileInfo? file;
    if (json.containsKey('x') || type == 'file') {
      file = SealedFileInfo.tryParse(json['x']);
      if (file == null || type != 'file' || value.isNotEmpty) return null;
    }
    return SealedContent(
      value: value,
      label: label,
      type: type,
      format: format,
      file: file,
    );
  }
}

/// The part of an encrypted file's sealed value that describes its blob.
class SealedFileInfo {
  final String name;
  final String mime;
  final int size;
  final Uint8List fileKey;

  const SealedFileInfo({
    required this.name,
    required this.mime,
    required this.size,
    required this.fileKey,
  });

  Map<String, dynamic> toJson() => {
    'n': name,
    'm': mime,
    's': size,
    'k': SealedFormats.linkKeyText(fileKey),
  };

  static SealedFileInfo? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = json['n'], mime = json['m'];
    final size = json['s'], key = json['k'];
    if (name is! String ||
        name.isEmpty ||
        mime is! String ||
        size is! int ||
        size < 0 ||
        size > SealedFile.maxLength ||
        key is! String) {
      return null;
    }
    final fileKey = SealedFormats.parseLinkKey(key);
    if (fileKey == null) return null;
    return SealedFileInfo(name: name, mime: mime, size: size, fileKey: fileKey);
  }
}

/// What goes on the wire for one sealed value.
class SealedPayload {
  final String sealedValue;
  final int keyEpoch;
  final String keyWrap;

  /// The key this value was just encrypted under. It stays on this device and
  /// is not part of [toJson]: the caller needs it once, to renew what the
  /// record's links hold for the new version.
  final Uint8List? valueKey;

  const SealedPayload({
    required this.sealedValue,
    required this.keyEpoch,
    required this.keyWrap,
    this.valueKey,
  });

  Map<String, dynamic> toJson() => {
    'sealedValue': sealedValue,
    'keyEpoch': keyEpoch,
    'keyWrap': keyWrap,
  };
}

/// Holds this device's encryption keys and does all the sealing. E2EE.md is the
/// design; the server sees only what this store has already encrypted.
// ignore: library_private_types_in_public_api
/// An identity's sealedKeyScope when its key is under the account key.
const identityKeyScopeAccount = 'account';

class KeysStore extends _KeysStore with _$KeysStore {
  KeysStore(
    super.api, {
    required super.currentUser,
    super.storage,
    super.membersOf,
  });

  /// What someone must type, and the server must receive, to delete what nobody
  /// can read any more.
  static const startOverPhrase = 'delete my encrypted records';

  /// A fingerprint a person can compare between two screens. Only needed when a
  /// code travelled through something they don't fully trust.
  static String fingerprint(Uint8List hpkeKey, Uint8List signingKey) {
    final digest = Sealing.sha256(
      Sealing.context('revoked-device-fingerprint-v1', [hpkeKey, signingKey]),
    );
    final groups = <String>[];
    for (var i = 0; i < 10; i += 2) {
      groups.add(
        digest[i].toRadixString(16).padLeft(2, '0') +
            digest[i + 1].toRadixString(16).padLeft(2, '0'),
      );
    }
    return groups.join(' ').toUpperCase();
  }
}

abstract class _KeysStore with Store {
  final ApiClient _api;
  final String Function() _currentUser;
  final FlutterSecureStorage _storage;

  _KeysStore(
    this._api, {
    required this._currentUser,
    FlutterSecureStorage? storage,
    this._membersOf,
  }) : _storage = storage ?? createSecureStorage();

  /// Other members' checked lists, for keys they hand this person and keys this
  /// person hands them. Without it, nothing crosses between people.
  final Future<List<MemberKeys>> Function(String workspace, {bool fresh})?
  _membersOf;

  /// Per workspace, the granters whose copies this device may open: members
  /// whose fingerprint the person compared. Anyone else's grant waits.
  Map<String, Map<String, VerifiedChain>> _granters = const {};

  /// Members who handed this person a key that waits for their fingerprint to
  /// be compared, by workspace.
  final ObservableMap<String, Set<String>> pendingGrants =
      ObservableMap<String, Set<String>>();

  @observable
  SealingStatus status = SealingStatus.unknown;

  @observable
  bool isLoading = false;

  @observable
  bool isSaving = false;

  @observable
  String? errorMessage;

  /// The checked device list.
  @observable
  VerifiedChain chain = VerifiedChain.empty;

  /// This device's position on the list, once it is on it.
  @observable
  int? thisDeviceSeq;

  /// The list as served contains something that doesn't check out.
  @observable
  bool chainBroken = false;

  /// Workspaces where this device may encrypt.
  final ObservableSet<String> writableWorkspaces = ObservableSet<String>();

  /// Workspaces where someone holds a key and this device doesn't.
  final ObservableSet<String> lockedWorkspaces = ObservableSet<String>();

  /// Shown once, while setting up or replacing the recovery key.
  @observable
  String? recoveryCode;

  /// What this device shows so one already trusted can add it.
  @observable
  String? deviceInvite;

  /// What a trusted device shows after adding another, for that one to enter.
  @observable
  String? deviceConfirmation;

  /// Changes on the list this device didn't make and this person hasn't looked
  /// at: additions and removals. Might be theirs, from another device. Might be a
  /// thief's, so they get to see them.
  final ObservableList<DeviceChainEntry> unreviewedEntries =
      ObservableList<DeviceChainEntry>();

  /// This device trusted the list, and the list has since taken it off.
  @observable
  bool removedFromList = false;

  /// The passkey this session signed in with, and the secret it derived, when
  /// the authenticator gave one. Memory only: it is never written anywhere, and
  /// it goes with the session.
  @observable
  PasskeySignIn? passkeySignIn;

  /// Why the passkey could not be connected or used, when it could not.
  @observable
  String? passkeyError;

  bool _passkeyBusy = false;

  final ObservableTextController recoveryConfirm = ObservableTextController();
  final ObservableTextController recoveryInput = ObservableTextController();
  final ObservableTextController deviceCodeInput = ObservableTextController();
  final ObservableTextController confirmationInput = ObservableTextController();
  final ObservableTextController startOverConfirm = ObservableTextController();

  Uint8List? _pendingRecoverySecret;
  bool _replacingRecovery = false;
  _DeviceKeys? _device;
  _Pins _pins = _Pins();
  final Map<String, _WorkspaceKeys> _workspaces = {};
  Map<String, dynamic> _lastState = const {};
  bool _serverSupports = false;
  String _serverSupportsFor = '';
  String _loadedFor = '';
  bool _stale = false;
  Future<void>? _loading;
  Future<void>? _pinWrites;

  /// Bumped when the session ends, so a load still in flight cannot put keys
  /// back in memory afterwards.
  int _generation = 0;

  String get _scope => '${_api.originAuthority}_${_currentUser()}';
  String get _deviceStorageKey => 'sealed_device_$_scope';
  String get _pinsStorageKey => 'sealed_pins_$_scope';

  @computed
  bool get isAvailable =>
      status != SealingStatus.unavailable && status != SealingStatus.unknown;

  @computed
  bool get startOverConfirmed =>
      startOverConfirm.text.trim().toLowerCase() == KeysStore.startOverPhrase;

  @computed
  bool get recoveryConfirmMatches {
    final code = recoveryCode;
    if (code == null) return false;
    final groups = code.split('-');
    final expected = groups.sublist(groups.length - 2).join();
    return _normalizeCode(recoveryConfirm.text) == expected;
  }

  /// A list without a recovery key: removing the device that added it takes it
  /// off too, so the person needs a new one.
  @computed
  bool get needsNewRecoveryKey =>
      status == SealingStatus.ready &&
      !chainBroken &&
      chain.liveRecovery == null;

  static String _normalizeCode(String text) => text
      .toUpperCase()
      .replaceAll(RegExp(r'[\s-]'), '')
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1');

  bool canSeal(String workspace) => writableWorkspaces.contains(workspace);

  /// Where this person's account key sits among the workspace keys: the same
  /// formats, pins and rotation, under a name no workspace can have.
  String get _accountScope => SealedFormats.accountScope(_currentUser());

  /// The key rows as served: every workspace's, then this person's own.
  List<Map<String, dynamic>> _keyRows(Map<String, dynamic> state) => [
    for (final raw in (state['workspaces'] as List<dynamic>? ?? const []))
      raw as Map<String, dynamic>,
    if (state['account'] case final Map<String, dynamic> account)
      if (account['workspace'] == _accountScope) account,
  ];

  /// The passkey this session signed in with, when it derived a secret and the
  /// session is still this person's.
  PasskeySignIn? get _heldPasskey {
    final p = passkeySignIn;
    return p != null && p.user == _currentUser() && p.secret != null ? p : null;
  }

  /// The credential this session signed in with, when it holds a secret.
  @computed
  String? get thisPasskeyCredentialId => _heldPasskey?.credentialId;

  /// A passkey signed in here, but gave nothing a key could derive from.
  @computed
  bool get passkeyWithoutSecret {
    final p = passkeySignIn;
    return p != null && p.user == _currentUser() && p.asked && p.secret == null;
  }

  /// Whether the passkey this session signed in with could be made a key
  /// holder from here: this device is trusted and the list doesn't name it.
  @computed
  bool get canConnectPasskey {
    final p = _heldPasskey;
    return p != null &&
        p.credentialId.isNotEmpty &&
        status == SealingStatus.ready &&
        !chainBroken &&
        chain.livePasskey(p.credentialId) == null;
  }

  /// Where this person's own checked list starts, once this device trusts it:
  /// what their fingerprint is made from.
  Uint8List? get rootHash =>
      status == SealingStatus.ready && !chainBroken && chain.entries.isNotEmpty
      ? chain.entries.first.hash
      : null;

  /// This person's fingerprint, for others to compare with what they see.
  @computed
  String? get ownFingerprint {
    final root = rootHash;
    return root == null
        ? null
        : SealedFormats.memberFingerprint(_currentUser(), root);
  }

  /// Whether a workspace's key is in someone else's hands only.
  bool isLockedFor(String workspace) => lockedWorkspaces.contains(workspace);

  /// Refuses anything that signs or hands out keys unless this device trusts
  /// the list it would be acting on.
  bool get _trusted =>
      status == SealingStatus.ready &&
      !chainBroken &&
      _device != null &&
      thisDeviceSeq != null;

  /// Loads once per signed-in person; a later call awaits the same load.
  Future<void> ensureLoaded() {
    final scope = _scope;
    if (_loadedFor == scope && status != SealingStatus.unknown && !_stale) {
      return Future.value();
    }
    return _loading ??= load().whenComplete(() => _loading = null);
  }

  /// Makes the next [ensureLoaded] read the server again. Another device may
  /// have changed the list or started a key while this one was away.
  void markStale() => _stale = true;

  /// Keys stay in memory only for a session; signing out drops them. The device
  /// keys on disk stay, the way identity keys do, so signing back in doesn't
  /// make this a new device.
  @action
  void forgetSession() {
    _generation++;
    _workspaces.clear();
    writableWorkspaces.clear();
    lockedWorkspaces.clear();
    _device = null;
    _pins = _Pins();
    _lastState = const {};
    _loadedFor = '';
    chain = VerifiedChain.empty;
    thisDeviceSeq = null;
    chainBroken = false;
    recoveryCode = null;
    deviceInvite = null;
    deviceConfirmation = null;
    unreviewedEntries.clear();
    removedFromList = false;
    _pendingRecoverySecret = null;
    passkeySignIn = null;
    passkeyError = null;
    status = SealingStatus.unknown;
  }

  /// Takes what the sign-in page brought back. Acted on by the next load, or
  /// now if this person is already loaded: a device that can read nothing joins
  /// through the passkey, a trusted one lets the passkey hold its keys.
  @action
  Future<void> offerPasskeySignIn(PasskeySignIn signIn) {
    passkeySignIn = signIn;
    passkeyError = null;
    if (_loadedFor == _scope && status != SealingStatus.unknown) {
      return load();
    }
    return Future.value();
  }

  /// Only "yes" is remembered. One bad answer, or a server mid-upgrade, must not
  /// stay wrong for the rest of the session.
  Future<bool> _supported() async {
    final origin = _api.originAuthority;
    if (_serverSupports && _serverSupportsFor == origin) return true;
    final info = await _api.get('/api/server');
    final sealing = info is Map ? info['sealing'] : null;
    _serverSupports = sealing is Map && sealing['records'] == true;
    _serverSupportsFor = origin;
    return _serverSupports;
  }

  @action
  Future<void> load() async {
    errorMessage = null;
    _stale = false;
    if (_currentUser().isEmpty) {
      status = SealingStatus.unknown;
      return;
    }
    final generation = _generation;
    isLoading = true;
    try {
      // Before asking the server anything: what this device remembers must not
      // depend on the server agreeing to be asked.
      await _readLocal();
      if (!await _supported()) {
        // A server that stops offering this after this device has used it is
        // either a downgrade or an attack on what this device remembers.
        status = _device != null || !_pins.isEmpty
            ? SealingStatus.untrusted
            : SealingStatus.unavailable;
        return;
      }
      await _refresh();
      if (generation != _generation) {
        forgetSession();
        return;
      }
      _loadedFor = _scope;
    } catch (e) {
      errorMessage = describeError(e);
      status = SealingStatus.unknown;
    } finally {
      isLoading = false;
    }
  }

  Future<void> _readLocal() async {
    final rawDevice = await _storage.read(key: _deviceStorageKey);
    _device = rawDevice == null
        ? null
        : _DeviceKeys.fromJson(jsonDecode(rawDevice) as Map<String, dynamic>);
    final rawPins = await _storage.read(key: _pinsStorageKey);
    _pins = rawPins == null
        ? _Pins()
        : _Pins.fromJson(jsonDecode(rawPins) as Map<String, dynamic>);
  }

  /// Writes go one at a time, so an older snapshot can't land after a newer one.
  Future<void> _savePins() {
    final key = _pinsStorageKey;
    final snapshot = jsonEncode(_pins.toJson());
    Future<void> write() => _storage.write(key: key, value: snapshot);
    final previous = _pinWrites;
    final done = previous == null ? write() : previous.then((_) => write());
    _pinWrites = done;
    done.whenComplete(() {
      if (identical(_pinWrites, done)) _pinWrites = null;
    }).ignore();
    return done;
  }

  Future<void> _saveDevice(_DeviceKeys device) {
    _device = device;
    return _storage.write(
      key: _deviceStorageKey,
      value: jsonEncode(device.toJson()),
    );
  }

  /// Fetches the state, applies it, lets the passkey act on it, and replaces any
  /// key that's due. Each of those changes the state, so it is read again.
  Future<void> _refresh() async {
    await _applyState(await _fetchState());
    if (await _applyPasskey()) await _applyState(await _fetchState());
    await _rotateDue();
  }

  Future<void> _rotateDue() async {
    final due = [
      for (final entry in _workspaces.entries)
        if (entry.value.mustRotate) entry.key,
    ];
    if (due.isEmpty || !_trusted) return;
    for (final workspace in due) {
      final held = _workspaces[workspace]!;
      if (await _othersDependOn(workspace)) continue;
      try {
        await _startEpoch(
          workspace,
          held.currentEpoch + 1,
          held.keys[held.currentEpoch],
        );
      } on ApiException catch (e) {
        // Another device replaced it first; the read below picks that up.
        if (e.code != AppErrorCode.sealedVersionConflict) rethrow;
      }
    }
    await _applyState(await _fetchState());
  }

  Future<Map<String, dynamic>> _fetchState() async {
    final data = await _api.get('/api/sealed/state');
    return data as Map<String, dynamic>;
  }

  @action
  Future<void> _applyState(Map<String, dynamic> state) async {
    // Before anything else changes: what comes after reads it without waiting.
    final granters = await _grantersFor(state);
    _lastState = state;
    _granters = granters;
    final user = _currentUser();
    final served = <DeviceChainEntry>[];
    var unreadable = false;
    for (final e in (state['devices'] as List<dynamic>? ?? const [])) {
      // One entry a client can't parse must break the list at that point, not
      // stop this device loading: it could then neither read nor recover.
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
    chain = verified;
    chainBroken = verified.broken || unreadable;

    _workspaces.clear();
    writableWorkspaces.clear();
    lockedWorkspaces.clear();
    thisDeviceSeq = null;

    final device = _device;
    if (device != null) {
      for (final entry in verified.live) {
        if (entry.kind == DeviceChainEntry.kindDevice &&
            _sameBytes(entry.hpkePublicKey, device.hpke.publicKey) &&
            _sameBytes(entry.signingPublicKey, device.signing.publicKey)) {
          thisDeviceSeq = entry.seq;
        }
      }
    }

    if (_pinsContradict(served, verified)) {
      status = SealingStatus.untrusted;
      thisDeviceSeq = null;
      return;
    }

    unreviewedEntries.clear();
    removedFromList = false;
    if (served.isEmpty) {
      status = SealingStatus.notSetUp;
      return;
    }
    if (thisDeviceSeq == null) {
      removedFromList = !_pins.isEmpty && !chainBroken;
      status = SealingStatus.needsThisDevice;
      return;
    }
    if (_pins.isEmpty) {
      // A list naming this device proves nothing: its public keys are public.
      // This device has no reason yet to believe the list is the real one.
      status = SealingStatus.needsConfirmation;
      return;
    }
    status = SealingStatus.ready;

    if (!chainBroken) {
      _pins.setupPending = false;
      _pins.headSeq = verified.headSeq;
      _pins.headHash = SealedFormats.encode(verified.headHash);
    }
    unreviewedEntries.addAll(
      verified.entries.where(
        (e) => e.seq > _pins.reviewedSeq && !_pins.ownSeqs.contains(e.seq),
      ),
    );

    for (final row in _keyRows(state)) {
      final workspace = row['workspace'] as String;
      final opened = _openWorkspace(
        workspace,
        row,
        _granters[workspace] ?? const {},
      );
      if (opened == null) {
        lockedWorkspaces.add(workspace);
        continue;
      }
      _workspaces[workspace] = opened;
      if (opened.writable) writableWorkspaces.add(workspace);
    }
    await _savePins();
  }

  /// Who handed this person keys, per workspace, and whose list this device
  /// can check their copies against. Only a member whose fingerprint the person
  /// compared counts: anyone can encrypt to a public key, so a member the server
  /// made up could otherwise hand over a key it knows, and read what this person
  /// writes under it. The others are noted in [pendingGrants].
  Future<Map<String, Map<String, VerifiedChain>>> _grantersFor(
    Map<String, dynamic> state,
  ) async {
    final me = _currentUser();
    final named = <String, Set<String>>{};
    for (final raw in (state['workspaces'] as List<dynamic>? ?? const [])) {
      final row = raw as Map<String, dynamic>;
      for (final w in (row['wraps'] as List<dynamic>? ?? const [])) {
        final granter = (w as Map<String, dynamic>)['granter'] as String? ?? '';
        if (granter.isNotEmpty && granter != me) {
          named.putIfAbsent(row['workspace'] as String, () => {}).add(granter);
        }
      }
    }
    final out = <String, Map<String, VerifiedChain>>{};
    final pending = <String, Set<String>>{};
    final lookup = _membersOf;
    for (final entry in named.entries) {
      final chains = <String, VerifiedChain>{};
      List<MemberKeys> members = const [];
      if (lookup != null) {
        try {
          // Fresh: a grant names how far its granter's list had got, and an
          // older copy of that list would refuse it.
          members = await lookup(entry.key, fresh: true);
        } catch (_) {
          // Unreachable now; the copies wait, as for an unverified granter.
        }
      }
      for (final granter in entry.value) {
        MemberKeys? member;
        for (final m in members) {
          if (m.user == granter) member = m;
        }
        if (member != null && member.state == MemberKeyState.verified) {
          chains[granter] = member.chain;
        } else {
          pending.putIfAbsent(entry.key, () => {}).add(granter);
        }
      }
      out[entry.key] = chains;
    }
    runInAction(() {
      pendingGrants
        ..clear()
        ..addAll(pending);
    });
    return out;
  }

  /// Whether the list as served can't be the one this device has seen. Pinning
  /// only the start would let a stolen device fork the list from before its
  /// removal, in which it is still on the list.
  bool _pinsContradict(List<DeviceChainEntry> served, VerifiedChain verified) {
    if (_pins.isEmpty) return false;
    if (served.isEmpty) return !_pins.setupPending;
    if (verified.entries.isEmpty) return true;
    if (SealedFormats.encode(verified.entries.first.hash) != _pins.firstHash) {
      return true;
    }
    if (_pins.headSeq == 0) return false;
    final pinned = verified.bySeq(_pins.headSeq);
    return pinned == null ||
        SealedFormats.encode(pinned.hash) != _pins.headHash;
  }

  /// Opens this device's newest wrapped key, then walks back through the older
  /// ones. Returns null if it holds none. Each hand-over must be signed by a
  /// device on the list: anyone can encrypt to a public key, so an unsigned one
  /// could be a key the server chose in order to read what's written under it.
  ///
  /// A copy from another member is checked against [granters], their lists as
  /// this device pinned them, and never against this person's own.
  _WorkspaceKeys? _openWorkspace(
    String workspace,
    Map<String, dynamic> row,
    Map<String, VerifiedChain> granters,
  ) {
    final seq = thisDeviceSeq;
    final device = _device;
    if (seq == null || device == null) return null;

    final epochs = [
      for (final e in (row['epochs'] as List<dynamic>? ?? const []))
        e as Map<String, dynamic>,
    ];
    if (epochs.isEmpty) return null;
    final priorWraps = {
      for (final e in epochs)
        (e['epoch'] as num).toInt(): e['priorWrap'] as String? ?? '',
    };
    final newestEpoch = priorWraps.keys.reduce((a, b) => a > b ? a : b);
    final rotationDue = epochs.any(
      (e) =>
          (e['epoch'] as num).toInt() == newestEpoch &&
          e['rotationDue'] == true,
    );

    final wraps = [
      for (final w in (row['wraps'] as List<dynamic>? ?? const []))
        if ((w['deviceSeq'] as num).toInt() == seq) w as Map<String, dynamic>,
    ]..sort((a, b) => (b['epoch'] as num).compareTo(a['epoch'] as num));

    final pinned = _pins.epochs[workspace] ?? 0;
    for (final wrap in wraps) {
      final epoch = (wrap['epoch'] as num).toInt();
      final signerSeq = (wrap['signerSeq'] as num).toInt();
      final chainSeq = (wrap['chainSeq'] as num?)?.toInt() ?? 0;
      final granter = wrap['granter'] as String? ?? '';
      final granted = granter.isNotEmpty && granter != _currentUser();
      final signerChain = granted ? granters[granter] : chain;
      if (signerChain == null) continue;
      final fromLiveDevice = signerChain.isLive(signerSeq);
      if (chainSeq < 1 || chainSeq > signerChain.headSeq) continue;
      // How far this person's own list had got when the key reached them.
      final ownSeq = granted
          ? (wrap['recipientChainSeq'] as num?)?.toInt() ?? 0
          : chainSeq;
      if (ownSeq < 1 || ownSeq > chain.headSeq) continue;

      final key = granted
          ? _openGrant(
              workspace: workspace,
              epoch: epoch,
              recipient: device.hpke,
              wrap: wrap['wrap'] as String,
              granter: granter,
              granterChain: signerChain,
              signerSeq: signerSeq,
              chainSeq: chainSeq,
              recipientChainSeq: ownSeq,
              signature: wrap['signature'] as String,
            )
          : _openWrap(
              workspace: workspace,
              epoch: epoch,
              recipient: device.hpke,
              wrap: wrap['wrap'] as String,
              signerSeq: signerSeq,
              chainSeq: chainSeq,
              signature: wrap['signature'] as String,
            );
      if (key == null) continue;

      // Each epoch has one key. A removed device may have kept its signing key,
      // so it can re-offer a key this device already knows and nothing else:
      // otherwise it could choose the key, and everything written under it.
      final pinKey = '$workspace:$epoch';
      final hash = _keyHash(key);
      final knownHash = _pins.epochKeys[pinKey];
      if (knownHash != null && knownHash != hash) continue;
      if (!fromLiveDevice && knownHash == null) continue;

      final keys = <int, Uint8List>{epoch: key};
      for (var e = epoch; e > 1; e--) {
        final prior = priorWraps[e];
        if (prior == null || prior.isEmpty) break;
        try {
          final opened = SealedFormats.openPriorEpoch(
            newKey: keys[e]!,
            wrapped: prior,
            workspace: workspace,
            epoch: e,
          );
          if (opened.length != Sealing.keyLength) break;
          keys[e - 1] = opened;
        } on SealingException {
          break;
        } on FormatException {
          break;
        }
      }

      // A newer key must lead back to the one this device knows. Naming a huge
      // epoch would otherwise pin it, and block every genuine write from then on.
      if (pinned > 0 && epoch > pinned) {
        final known = keys[pinned];
        if (known == null ||
            _keyHash(known) != _pins.epochKeys['$workspace:$pinned']) {
          continue;
        }
      }

      if (fromLiveDevice) {
        _pins.epochKeys[pinKey] = hash;
        if (epoch > pinned) _pins.epochs[workspace] = epoch;
      }

      final isNewest = epoch == newestEpoch && epoch >= pinned;
      // This device sees a removal the key predates for itself, so the server
      // can't keep it writing under a key a removed device has by hiding a flag.
      // For a granted key, a removal on the granter's list after the grant counts
      // the same: that device may have kept it.
      final predatesRemoval =
          chain.lastRemovalSeq > ownSeq ||
          (granted && signerChain.lastRemovalSeq > chainSeq);
      final canAct = isNewest && !chainBroken;
      return _WorkspaceKeys(
        keys: keys,
        currentEpoch: epoch,
        chainSeq: ownSeq,
        writable: canAct && fromLiveDevice && !rotationDue && !predatesRemoval,
        mustRotate:
            canAct && (rotationDue || !fromLiveDevice || predatesRemoval),
      );
    }
    return null;
  }

  static String _keyHash(Uint8List key) => SealedFormats.encode(
    Sealing.sha256(Sealing.context('revoked-epoch-key-hash-v1', [key])),
  );

  /// Sends signed entries, then checks the server actually kept them. It could
  /// answer "ok" and store nothing, leaving a thief on the list while the person
  /// is told they've been removed.
  Future<void> _commit(
    List<DeviceChainEntry> entries, {
    List<Map<String, dynamic>> wraps = const [],
  }) async {
    await _api.post(
      '/api/sealed/devices',
      body: {
        'entries': [for (final e in entries) e.toJson()],
        'wraps': wraps,
      },
    );
    await _applyState(await _fetchState());
    for (final entry in entries) {
      final served = chain.bySeq(entry.seq);
      if (served == null || !_sameBytes(served.hash, entry.hash)) {
        throw const SealingException(
          'The server did not save the change to the device list.',
        );
      }
    }
    _pins.ownSeqs.addAll(entries.map((e) => e.seq));
    unreviewedEntries.removeWhere(
      (e) => entries.any((own) => own.seq == e.seq),
    );
    if (unreviewedEntries.isEmpty) _pins.reviewedSeq = chain.headSeq;
    await _savePins();
  }

  Future<void> _markReviewed() async {
    _pins.reviewedSeq = chain.headSeq;
    unreviewedEntries.clear();
    await _savePins();
  }

  /// The person looked at what changed on their list and is fine with it.
  @action
  Future<void> acknowledgeNewEntries() => _markReviewed();

  Uint8List? _openWrap({
    required String workspace,
    required int epoch,
    required SealingKeyPair recipient,
    required String wrap,
    required int signerSeq,
    required int chainSeq,
    required String signature,
  }) {
    final signer = chain.bySeq(signerSeq);
    if (signer == null || signer.action != DeviceChainEntry.actionAdd) {
      return null;
    }
    try {
      final signed = SealedFormats.wrapSignaturePayload(
        workspace: workspace,
        epoch: epoch,
        recipientHpkeKey: recipient.publicKey,
        wrap: wrap,
        chainSeq: chainSeq,
      );
      if (!Sealing.verify(
        signer.signingPublicKey,
        signed,
        SealedFormats.decode(signature),
      )) {
        return null;
      }
      return SealedFormats.openWorkspaceKey(
        recipient: recipient,
        wrap: wrap,
        workspace: workspace,
        epoch: epoch,
      );
    } on SealingException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Opens a key another member handed to [recipient], one of this person's
  /// entries, once its signature checks out against the granter's own list.
  Uint8List? _openGrant({
    required String workspace,
    required int epoch,
    required SealingKeyPair recipient,
    required String wrap,
    required String granter,
    required VerifiedChain granterChain,
    required int signerSeq,
    required int chainSeq,
    required int recipientChainSeq,
    required String signature,
  }) {
    final signer = granterChain.bySeq(signerSeq);
    if (signer == null || signer.action != DeviceChainEntry.actionAdd) {
      return null;
    }
    final me = _currentUser();
    try {
      final signed = SealedFormats.grantSignaturePayload(
        workspace: workspace,
        epoch: epoch,
        recipientUser: me,
        recipientHpkeKey: recipient.publicKey,
        wrap: wrap,
        granterUser: granter,
        granterChainSeq: chainSeq,
        recipientChainSeq: recipientChainSeq,
      );
      if (!Sealing.verify(
        signer.signingPublicKey,
        signed,
        SealedFormats.decode(signature),
      )) {
        return null;
      }
      return SealedFormats.openGrantedWorkspaceKey(
        recipient: recipient,
        wrap: wrap,
        workspace: workspace,
        epoch: epoch,
        recipientUser: me,
        granterUser: granter,
      );
    } on SealingException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// A workspace key for one of [member]'s entries, signed by this device over
  /// both lists as they stand.
  Map<String, dynamic> _grantFor({
    required String workspace,
    required int epoch,
    required Uint8List key,
    required MemberKeys member,
    required DeviceChainEntry recipient,
  }) {
    final device = _device!;
    final wrap = SealedFormats.grantWorkspaceKey(
      recipientHpkeKey: recipient.hpkePublicKey,
      key: key,
      workspace: workspace,
      epoch: epoch,
      recipientUser: member.user,
      granterUser: _currentUser(),
    );
    return {
      'user': member.user,
      'deviceSeq': recipient.seq,
      'wrap': wrap,
      'signerSeq': thisDeviceSeq!,
      'chainSeq': chain.headSeq,
      'recipientChainSeq': member.chain.headSeq,
      'signature': SealedFormats.encode(
        Sealing.sign(
          device.signing,
          SealedFormats.grantSignaturePayload(
            workspace: workspace,
            epoch: epoch,
            recipientUser: member.user,
            recipientHpkeKey: recipient.hpkePublicKey,
            wrap: wrap,
            granterUser: _currentUser(),
            granterChainSeq: chain.headSeq,
            recipientChainSeq: member.chain.headSeq,
          ),
        ),
      ),
    };
  }

  /// Hands this workspace's current key to every live entry on [member]'s
  /// list. Only under a key this device may write with, only to a list this
  /// device checked, and only to someone the server says may read the vault.
  @action
  Future<bool> grantAccess(String workspace, MemberKeys member) async {
    errorMessage = null;
    final held = _workspaces[workspace];
    if (!_trusted || held == null || !held.writable) {
      errorMessage =
          'This device cannot hand out this workspace’s key right now.';
      return false;
    }
    if (member.isSelf ||
        !member.usable ||
        !member.canRead ||
        member.chain.broken ||
        member.chain.live.isEmpty) {
      errorMessage = 'Their keys cannot be trusted right now.';
      return false;
    }
    try {
      final epoch = held.currentEpoch;
      await _api.post(
        '/api/sealed/workspaces/$workspace/grants',
        body: {
          'epoch': epoch,
          'grants': [
            for (final entry in member.chain.live)
              _grantFor(
                workspace: workspace,
                epoch: epoch,
                key: held.keys[epoch]!,
                member: member,
                recipient: entry,
              ),
          ],
        },
      );
      return true;
    } catch (e) {
      errorMessage = describeError(e);
      return false;
    }
  }

  /// The members a new key of [workspace] must reach besides this person: who
  /// held the old one, may still read, and whose list this device trusts. Empty
  /// unless this person may hand out keys, for the server would refuse them.
  Future<List<MemberKeys>> _carriedMembers(String workspace) async {
    final lookup = _membersOf;
    if (lookup == null || workspace == _accountScope) return const [];
    try {
      // Fresh: who holds the key changes with every grant.
      final members = await lookup(workspace, fresh: true);
      final self = members.where((m) => m.isSelf).firstOrNull;
      if (self == null || !self.canGrant) return const [];
      return [
        for (final m in members)
          if (!m.isSelf && m.canRead && m.holdsKey && m.usable) m,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Whether replacing [workspace]'s key here would cut others off: they hold
  /// it, and this person may not hand them the new one. Left to someone who may.
  Future<bool> _othersDependOn(String workspace) async {
    final lookup = _membersOf;
    if (lookup == null || workspace == _accountScope) return false;
    try {
      // Fresh: who holds the key changes with every grant.
      final members = await lookup(workspace, fresh: true);
      final self = members.where((m) => m.isSelf).firstOrNull;
      if (self == null || self.canGrant) return false;
      return members.any((m) => !m.isSelf && m.holdsKey);
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _wrapFor({
    required String workspace,
    required int epoch,
    required Uint8List key,
    required DeviceChainEntry recipient,
    required SealingKeyPair signer,
    required int signerSeq,
    required int chainSeq,
  }) {
    final wrap = SealedFormats.wrapWorkspaceKey(
      recipientHpkeKey: recipient.hpkePublicKey,
      key: key,
      workspace: workspace,
      epoch: epoch,
    );
    return {
      'workspace': workspace,
      'epoch': epoch,
      'deviceSeq': recipient.seq,
      'wrap': wrap,
      'signerSeq': signerSeq,
      'chainSeq': chainSeq,
      'signature': SealedFormats.encode(
        Sealing.sign(
          signer,
          SealedFormats.wrapSignaturePayload(
            workspace: workspace,
            epoch: epoch,
            recipientHpkeKey: recipient.hpkePublicKey,
            wrap: wrap,
            chainSeq: chainSeq,
          ),
        ),
      ),
    };
  }

  Future<void> _startEpoch(
    String workspace,
    int epoch,
    Uint8List? prior,
  ) async {
    final device = _device!;
    final seq = thisDeviceSeq!;
    final key = Sealing.newSymmetricKey();
    final carried = await _carriedMembers(workspace);
    await _api.post(
      workspace == _accountScope
          ? '/api/sealed/account/epochs'
          : '/api/sealed/workspaces/$workspace/epochs',
      body: {
        'epoch': epoch,
        'priorWrap': prior == null
            ? ''
            : SealedFormats.wrapPriorEpoch(
                newKey: key,
                priorKey: prior,
                workspace: workspace,
                epoch: epoch,
              ),
        'wraps': [
          for (final entry in chain.live)
            _wrapFor(
              workspace: workspace,
              epoch: epoch,
              key: key,
              recipient: entry,
              signer: device.signing,
              signerSeq: seq,
              chainSeq: chain.headSeq,
            ),
        ],
        if (carried.isNotEmpty)
          'grants': [
            for (final member in carried)
              for (final entry in member.chain.live)
                _grantFor(
                  workspace: workspace,
                  epoch: epoch,
                  key: key,
                  member: member,
                  recipient: entry,
                ),
          ],
      },
    );
  }

  /// Makes sure this device can encrypt in [workspace], starting its key if
  /// nobody has yet.
  @action
  Future<bool> ensureWorkspaceKey(String workspace) async {
    errorMessage = null;
    if (!_trusted || workspace.isEmpty) return false;
    if (writableWorkspaces.contains(workspace)) return true;
    try {
      // Another device may have started the key since this one last looked.
      await _refresh();
      if (!_trusted) {
        errorMessage =
            'The device list changed. Review it in Settings before encrypting '
            'anything.';
        return false;
      }
      if (lockedWorkspaces.contains(workspace) ||
          _workspaces.containsKey(workspace)) {
        return writableWorkspaces.contains(workspace);
      }
      try {
        await _startEpoch(workspace, 1, null);
      } on ApiException catch (e) {
        // Started elsewhere between that read and this write.
        if (e.code != AppErrorCode.sealedVersionConflict) rethrow;
      }
      await _refresh();
      return writableWorkspaces.contains(workspace);
    } catch (e) {
      errorMessage = describeError(e);
      return false;
    }
  }

  /// Makes sure this device holds this person's account key, making it if no
  /// device has yet. False when it can't: another device holds the key and
  /// hasn't handed it here, or this device isn't trusted.
  @action
  Future<bool> ensureAccountKey() async {
    final scope = _accountScope;
    if (!_trusted) return false;
    if (writableWorkspaces.contains(scope)) return true;
    try {
      await _refresh();
      if (!_trusted) return false;
      if (lockedWorkspaces.contains(scope) || _workspaces.containsKey(scope)) {
        return writableWorkspaces.contains(scope);
      }
      try {
        await _startEpoch(scope, 1, null);
      } on ApiException catch (e) {
        // Made on another device between that read and this write.
        if (e.code != AppErrorCode.sealedVersionConflict) rethrow;
      }
      await _refresh();
      return writableWorkspaces.contains(scope);
    } catch (_) {
      return false;
    }
  }

  /// Creates the recovery key and shows it. Nothing is uploaded until the
  /// person has confirmed saving it, so walking away changes nothing.
  /// What the passkey this session signed in with should do about the list, if
  /// anything, and does it: joins a device the list doesn't name through a
  /// passkey entry it can prove is its own, or enrols the passkey from a trusted
  /// device the first time the list sees that credential. True when it changed
  /// the list. A failure is kept for the person and never stops a load.
  Future<bool> _applyPasskey() async {
    final p = _heldPasskey;
    if (p == null || _passkeyBusy) return false;
    _passkeyBusy = true;
    try {
      switch (status) {
        case SealingStatus.needsThisDevice:
        case SealingStatus.needsConfirmation:
          return await _joinWithPasskey(p);
        case SealingStatus.ready:
          if (!_trusted ||
              p.credentialId.isEmpty ||
              chain.everNamedPasskey(p.credentialId)) {
            return false;
          }
          await _enrollPasskey(p);
          return true;
        case SealingStatus.unknown:
        case SealingStatus.unavailable:
        case SealingStatus.notSetUp:
        case SealingStatus.untrusted:
          return false;
      }
    } catch (e) {
      runInAction(() => passkeyError = describeError(e));
      return false;
    } finally {
      _passkeyBusy = false;
    }
  }

  /// Joins from a passkey entry whose keys this device can derive. The entry's
  /// anchor proves the real passkey signed the list's root, which only a device
  /// holding the same secret could have done, so the root is pinned from it.
  /// Nothing is evicted: unlike the recovery key, this is the ordinary way in.
  Future<bool> _joinWithPasskey(PasskeySignIn p) async {
    if (chainBroken || chain.entries.isEmpty) return false;
    final secret = p.secret!;
    final hpke = PasskeyKeys.hpkeKey(secret);
    final signing = PasskeyKeys.signingKey(secret);
    final root = chain.entries.first.hash;
    DeviceChainEntry? holder;
    for (final e in chain.livePasskeys) {
      if (_sameBytes(e.hpkePublicKey, hpke.publicKey) &&
          _sameBytes(e.signingPublicKey, signing.publicKey) &&
          Sealing.verify(
            signing.publicKey,
            SealedFormats.passkeyAnchorPayload(
              _currentUser(),
              root,
              e.credentialId,
            ),
            e.anchorSignature,
          )) {
        holder = e;
      }
    }
    if (holder == null) return false;
    await _joinThrough(
      holder: holder,
      hpke: hpke,
      signing: signing,
      root: root,
    );
    return true;
  }

  DeviceChainEntry _passkeyEntry(
    PasskeySignIn p, {
    required int seq,
    required Uint8List previousHash,
    required Uint8List rootHash,
    required int signerSeq,
    required SealingKeyPair signer,
  }) {
    final secret = p.secret!;
    final signing = PasskeyKeys.signingKey(secret);
    return DeviceChainEntry.sign(
      user: _currentUser(),
      seq: seq,
      action: DeviceChainEntry.actionAdd,
      kind: DeviceChainEntry.kindPasskey,
      label: p.name.isEmpty ? 'Passkey' : p.name,
      credentialId: p.credentialId,
      hpkePublicKey: PasskeyKeys.hpkeKey(secret).publicKey,
      signingPublicKey: signing.publicKey,
      targetSeq: 0,
      previousHash: previousHash,
      signerSeq: signerSeq,
      signer: signer,
      anchorSignature: Sealing.sign(
        signing,
        SealedFormats.passkeyAnchorPayload(
          _currentUser(),
          rootHash,
          p.credentialId,
        ),
      ),
    );
  }

  /// Puts the passkey on the list, signed by this device, and hands it every key
  /// this device may write under. From then on it receives each new key like any
  /// entry, and a device signing in with it can join by itself.
  Future<void> _enrollPasskey(PasskeySignIn p) async {
    if (!_trusted || p.credentialId.isEmpty) {
      throw const SealingException(
        'This device cannot change the device list right now.',
      );
    }
    if (chain.livePasskey(p.credentialId) != null) return;
    final entry = _passkeyEntry(
      p,
      seq: chain.nextSeq,
      previousHash: chain.headHash,
      rootHash: chain.entries.first.hash,
      signerSeq: thisDeviceSeq!,
      signer: _device!.signing,
    );
    await _commit([entry], wraps: _wrapsForNewEntry(entry));
  }

  /// Makes the passkey this session signed in with a key holder, at the person's
  /// request. The automatic path leaves alone a passkey they once took off.
  @action
  Future<bool> connectPasskey() async {
    final p = _heldPasskey;
    passkeyError = null;
    errorMessage = null;
    if (p == null) return false;
    isSaving = true;
    try {
      await _applyState(await _fetchState());
      await _enrollPasskey(p);
      await _refresh();
      return chain.livePasskey(p.credentialId) != null;
    } catch (e) {
      passkeyError = describeError(e);
      return false;
    } finally {
      isSaving = false;
    }
  }

  /// Takes a passkey's entry off the list, when it has one. The server can't do
  /// this when the passkey itself is removed, because only a key holder can sign
  /// it. True when no live entry names the credential afterwards.
  @action
  Future<bool> removePasskeyEntry(String credentialId) async {
    final entry = chain.livePasskey(credentialId);
    if (entry == null) return true;
    return removeDevice(entry.seq);
  }

  /// Puts this device on the list on the strength of [holder], an entry whose
  /// keys this device holds: removes [removeSeqs] and signs its own entry with
  /// them, carries every key wrapped to [holder] over to itself, and pins the
  /// list from [root]. Nothing is pinned until the server has shown all of that
  /// landed; pinning sooner would leave a failed join trusting a fork.
  Future<void> _joinThrough({
    required DeviceChainEntry holder,
    required SealingKeyPair hpke,
    required SealingKeyPair signing,
    required Uint8List root,
    List<int> removeSeqs = const [],
  }) async {
    var device = _device;
    if (device == null) {
      device = _DeviceKeys.generate();
      await _saveDevice(device);
    }

    // Removals first: a list at its cap would otherwise refuse this device, and
    // it may already be on a fork's list.
    final entries = <DeviceChainEntry>[];
    var nextSeq = chain.nextSeq;
    var previous = chain.headHash;
    final existing = thisDeviceSeq;
    for (final target in removeSeqs) {
      final removal = _removalEntry(
        seq: nextSeq++,
        target: target,
        previousHash: previous,
        signerSeq: holder.seq,
        signer: signing,
      );
      entries.add(removal);
      previous = removal.hash;
    }
    final entry = existing != null
        ? chain.bySeq(existing)!
        : DeviceChainEntry.sign(
            user: _currentUser(),
            seq: nextSeq,
            action: DeviceChainEntry.actionAdd,
            kind: DeviceChainEntry.kindDevice,
            label: _deviceLabel(),
            hpkePublicKey: device.hpke.publicKey,
            signingPublicKey: device.signing.publicKey,
            targetSeq: 0,
            previousHash: previous,
            signerSeq: holder.seq,
            signer: signing,
          );
    if (existing == null) entries.add(entry);

    if (entries.isNotEmpty) {
      await _commit(
        entries,
        wraps: existing == null
            ? _carriedWraps(
                holder: holder,
                hpke: hpke,
                signing: signing,
                recipient: entry,
              )
            : const [],
      );
    } else {
      await _applyState(await _fetchState());
    }
    _pins
      ..firstHash = SealedFormats.encode(root)
      ..headSeq = chain.headSeq
      ..headHash = SealedFormats.encode(chain.headHash)
      ..reviewedSeq = chain.headSeq
      ..setupPending = false;
    await _savePins();
  }

  /// Every key wrapped to [holder] that this device can open, wrapped again to
  /// [recipient] and signed by [holder]'s key.
  List<Map<String, dynamic>> _carriedWraps({
    required DeviceChainEntry holder,
    required SealingKeyPair hpke,
    required SealingKeyPair signing,
    required DeviceChainEntry recipient,
  }) {
    final wraps = <Map<String, dynamic>>[];
    for (final row in _keyRows(_lastState)) {
      final workspace = row['workspace'] as String;
      final own = [
        for (final w in (row['wraps'] as List<dynamic>? ?? const []))
          if ((w['deviceSeq'] as num).toInt() == holder.seq)
            w as Map<String, dynamic>,
      ]..sort((a, b) => (b['epoch'] as num).compareTo(a['epoch'] as num));
      for (final w in own) {
        final epoch = (w['epoch'] as num).toInt();
        final signerSeq = (w['signerSeq'] as num).toInt();
        final chainSeq = (w['chainSeq'] as num?)?.toInt() ?? 0;
        final granter = w['granter'] as String? ?? '';
        final granted = granter.isNotEmpty && granter != _currentUser();
        // Only from devices still on a list: re-signing what a removed device
        // handed over would launder a key it may have chosen. A granted key
        // is checked against its granter's list, and only one already
        // checked here: the person compared their fingerprint.
        final signerChain = granted
            ? (_granters[workspace] ?? const {})[granter]
            : chain;
        if (signerChain == null || !signerChain.isLive(signerSeq)) continue;
        final ownSeq = granted
            ? (w['recipientChainSeq'] as num?)?.toInt() ?? 0
            : chainSeq;
        final key = granted
            ? _openGrant(
                workspace: workspace,
                epoch: epoch,
                recipient: hpke,
                wrap: w['wrap'] as String,
                granter: granter,
                granterChain: signerChain,
                signerSeq: signerSeq,
                chainSeq: chainSeq,
                recipientChainSeq: ownSeq,
                signature: w['signature'] as String,
              )
            : _openWrap(
                workspace: workspace,
                epoch: epoch,
                recipient: hpke,
                wrap: w['wrap'] as String,
                signerSeq: signerSeq,
                chainSeq: chainSeq,
                signature: w['signature'] as String,
              );
        if (key == null) continue;
        wraps.add(
          _wrapFor(
            workspace: workspace,
            epoch: epoch,
            key: key,
            recipient: recipient,
            signer: signing,
            signerSeq: holder.seq,
            // Carried over: a fresh number would hide that this key predates
            // a removal, and spare it from being replaced.
            chainSeq: ownSeq,
          ),
        );
        break;
      }
    }
    return wraps;
  }

  @action
  void beginSetup() {
    _replacingRecovery = false;
    _beginRecovery();
  }

  @action
  void beginRecoveryReplacement() {
    _replacingRecovery = true;
    _beginRecovery();
  }

  void _beginRecovery() {
    errorMessage = null;
    final secret = Sealing.randomBytes(Sealing.keyLength);
    _pendingRecoverySecret = secret;
    recoveryCode = RecoveryCode.encode(secret);
    recoveryConfirm.clear();
  }

  @action
  void cancelRecovery() {
    _pendingRecoverySecret = null;
    recoveryCode = null;
    recoveryConfirm.clear();
  }

  static String _deviceLabel() {
    if (Platform.isAndroid) return 'Android device';
    if (Platform.isIOS) return 'iPhone or iPad';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isWindows) return 'Windows computer';
    if (Platform.isLinux) return 'Linux computer';
    return 'Device';
  }

  /// Finishes setting up or replacing the recovery key, once confirmed. Safe to
  /// press again after a failure: what already landed is not done twice.
  @action
  Future<bool> finishRecovery({required String workspace}) async {
    final secret = _pendingRecoverySecret;
    if (secret == null || !recoveryConfirmMatches) return false;
    errorMessage = null;
    isSaving = true;
    try {
      if (_replacingRecovery) {
        await _replaceRecovery(secret);
      } else {
        if (workspace.isEmpty) {
          throw const SealingException('No workspace is selected.');
        }
        await _firstSetup(secret);
        if (!_workspaces.containsKey(workspace) &&
            !lockedWorkspaces.contains(workspace)) {
          await _startEpoch(workspace, 1, null);
        }
      }
      await _refresh();
      if (_workspaces.values.any((held) => held.mustRotate)) {
        throw const SealingException(
          'The recovery key was saved, but the encryption key could not be '
          'replaced. Check the connection and reload.',
        );
      }
      cancelRecovery();
      _loadedFor = _scope;
      return true;
    } catch (e) {
      errorMessage = describeError(e);
      return false;
    } finally {
      isSaving = false;
    }
  }

  DeviceChainEntry _recoveryEntry(
    Uint8List secret, {
    required int seq,
    required Uint8List previousHash,
    required Uint8List rootHash,
    required int signerSeq,
    required SealingKeyPair signer,
  }) {
    final signing = RecoveryCode.signingKey(secret);
    return DeviceChainEntry.sign(
      user: _currentUser(),
      seq: seq,
      action: DeviceChainEntry.actionAdd,
      kind: DeviceChainEntry.kindRecovery,
      label: 'Recovery key',
      hpkePublicKey: RecoveryCode.hpkeKey(secret).publicKey,
      signingPublicKey: signing.publicKey,
      targetSeq: 0,
      previousHash: previousHash,
      signerSeq: signerSeq,
      signer: signer,
      anchorSignature: Sealing.sign(
        signing,
        SealedFormats.recoveryAnchorPayload(_currentUser(), rootHash),
      ),
    );
  }

  Future<void> _firstSetup(Uint8List secret) async {
    await _readLocal();
    await _applyState(await _fetchState());
    if (status == SealingStatus.ready) {
      // A retry whose first attempt landed. The code on screen may be a newer
      // one than the list holds, and the person believes this one works.
      final recovery = chain.liveRecovery;
      final hpke = RecoveryCode.hpkeKey(secret).publicKey;
      if (recovery == null || !_sameBytes(recovery.hpkePublicKey, hpke)) {
        await _replaceRecovery(secret);
      }
      return;
    }
    if (status != SealingStatus.notSetUp) {
      throw const SealingException(
        'This account already has encrypted records. This device can be added '
        'instead.',
      );
    }

    // Saved before the upload, and never replaced: a device list naming a key
    // that a crash lost could never be used.
    final device = _device ?? _DeviceKeys.generate();
    await _saveDevice(device);
    final first = DeviceChainEntry.sign(
      user: _currentUser(),
      seq: 1,
      action: DeviceChainEntry.actionAdd,
      kind: DeviceChainEntry.kindDevice,
      label: _deviceLabel(),
      hpkePublicKey: device.hpke.publicKey,
      signingPublicKey: device.signing.publicKey,
      targetSeq: 0,
      previousHash: Uint8List(0),
      signerSeq: 1,
      signer: device.signing,
    );
    final recovery = _recoveryEntry(
      secret,
      seq: 2,
      previousHash: first.hash,
      rootHash: first.hash,
      signerSeq: 1,
      signer: device.signing,
    );
    final entries = [first, recovery];
    final passkey = _heldPasskey;
    if (passkey != null && passkey.credentialId.isNotEmpty) {
      entries.add(
        _passkeyEntry(
          passkey,
          seq: 3,
          previousHash: recovery.hash,
          rootHash: first.hash,
          signerSeq: 1,
          signer: device.signing,
        ),
      );
    }

    // Pinned from what this device signed itself, before anything is uploaded.
    // Trusting the list the server sends back would let it put its own device
    // first and collect the workspace key this device then hands out.
    _pins
      ..firstHash = SealedFormats.encode(first.hash)
      ..headSeq = entries.length
      ..headHash = SealedFormats.encode(entries.last.hash)
      ..reviewedSeq = entries.length
      ..setupPending = true;
    await _savePins();

    await _api.post(
      '/api/sealed/devices',
      body: {
        'entries': [for (final e in entries) e.toJson()],
      },
    );
    await _applyState(await _fetchState());
    if (status != SealingStatus.ready) {
      throw const SealingException(
        'The server did not return what this device saved.',
      );
    }
  }

  DeviceChainEntry _removalEntry({
    required int seq,
    required int target,
    required Uint8List previousHash,
    required int signerSeq,
    required SealingKeyPair signer,
  }) => DeviceChainEntry.sign(
    user: _currentUser(),
    seq: seq,
    action: DeviceChainEntry.actionRemove,
    kind: '',
    label: '',
    hpkePublicKey: Uint8List(0),
    signingPublicKey: Uint8List(0),
    targetSeq: target,
    previousHash: previousHash,
    signerSeq: signerSeq,
    signer: signer,
  );

  Future<void> _replaceRecovery(Uint8List secret) async {
    await _applyState(await _fetchState());
    if (!_trusted) {
      throw const SealingException(
        'This device cannot change the device list right now.',
      );
    }
    final device = _device!;
    final seq = thisDeviceSeq!;
    final entries = <DeviceChainEntry>[];
    var nextSeq = chain.nextSeq;
    var previous = chain.headHash;
    final old = chain.liveRecovery;
    if (old != null) {
      final removal = _removalEntry(
        seq: nextSeq++,
        target: old.seq,
        previousHash: previous,
        signerSeq: seq,
        signer: device.signing,
      );
      entries.add(removal);
      previous = removal.hash;
    }
    final fresh = _recoveryEntry(
      secret,
      seq: nextSeq,
      previousHash: previous,
      rootHash: chain.entries.first.hash,
      signerSeq: seq,
      signer: device.signing,
    );
    entries.add(fresh);
    await _commit(entries, wraps: _wrapsForNewEntry(fresh));
  }

  /// Only keys this device may itself write under are passed on. Handing over a
  /// key from a removed device would launder it: the new device would see a
  /// signer still on the list, and trust it.
  List<Map<String, dynamic>> _wrapsForNewEntry(DeviceChainEntry entry) {
    final device = _device!;
    final seq = thisDeviceSeq!;
    return [
      for (final held in _workspaces.entries)
        if (held.value.writable)
          _wrapFor(
            workspace: held.key,
            epoch: held.value.currentEpoch,
            key: held.value.keys[held.value.currentEpoch]!,
            recipient: entry,
            signer: device.signing,
            signerSeq: seq,
            chainSeq: held.value.chainSeq,
          ),
    ];
  }

  @action
  void clearDeviceConfirmation() => deviceConfirmation = null;

  /// Gets this device ready to be added, and shows the code that adds it.
  @action
  Future<void> prepareThisDevice() async {
    errorMessage = null;
    try {
      await _readLocal();
      var device = _device;
      if (device == null) {
        device = _DeviceKeys.generate();
        await _saveDevice(device);
      }
      deviceInvite = DeviceInvite(
        hpkePublicKey: device.hpke.publicKey,
        signingPublicKey: device.signing.publicKey,
        label: _deviceLabel(),
      ).encodeToString();
    } catch (e) {
      errorMessage = describeError(e);
    }
  }

  String? get thisDeviceFingerprint {
    final device = _device;
    return device == null
        ? null
        : KeysStore.fingerprint(
            device.hpke.publicKey,
            device.signing.publicKey,
          );
  }

  /// Checks a pasted or scanned code and returns the device's fingerprint.
  String? fingerprintOfInvite(String code) {
    final invite = DeviceInvite.tryParse(code);
    return invite == null
        ? null
        : KeysStore.fingerprint(invite.hpkePublicKey, invite.signingPublicKey);
  }

  /// Adds another device from the code it shows, and hands it every key. Leaves
  /// [deviceConfirmation] for the new device to enter, which is how it learns
  /// that the list it joined is the real one.
  @action
  Future<bool> addDevice(String code) async {
    errorMessage = null;
    deviceConfirmation = null;
    final invite = DeviceInvite.tryParse(code);
    if (invite == null) {
      errorMessage = 'The code is incomplete. The whole code must be copied.';
      return false;
    }
    isSaving = true;
    try {
      // Signed against the list as it stands now: another device may have
      // changed it, and an entry on a stale list would break it for everyone.
      await _refresh();
      if (!_trusted) {
        errorMessage = 'This device cannot change the device list right now.';
        return false;
      }
      final device = _device!;
      final seq = thisDeviceSeq!;
      // Already on the list, say after a failed attempt or a rejoin: show the code
      // again. It only names an entry that's really there, so it gives nothing
      // away, and without it that device could never finish joining.
      if (chain.live.any(
        (e) => _sameBytes(e.signingPublicKey, invite.signingPublicKey),
      )) {
        deviceConfirmation = DeviceConfirmation.forEntry(
          chain.entries.last,
        ).encodeToString();
        deviceCodeInput.clear();
        return true;
      }
      final entry = DeviceChainEntry.sign(
        user: _currentUser(),
        seq: chain.nextSeq,
        action: DeviceChainEntry.actionAdd,
        kind: DeviceChainEntry.kindDevice,
        label: invite.label,
        hpkePublicKey: invite.hpkePublicKey,
        signingPublicKey: invite.signingPublicKey,
        targetSeq: 0,
        previousHash: chain.headHash,
        signerSeq: seq,
        signer: device.signing,
      );
      // Set first: if the server took this and only the read after it failed, the
      // new device is stuck without this code, and adding it again only says it
      // is already on the list.
      deviceConfirmation = DeviceConfirmation.forEntry(entry).encodeToString();
      await _commit([entry], wraps: _wrapsForNewEntry(entry));
      deviceCodeInput.clear();
      return true;
    } on ApiException catch (e) {
      errorMessage = describeError(e);
      // A refusal means nothing landed, so there is nothing to confirm.
      if (e.statusCode < 500) deviceConfirmation = null;
      return false;
    } catch (e) {
      errorMessage = describeError(e);
      return false;
    } finally {
      isSaving = false;
    }
  }

  /// Takes this device from "a list names me" to trusting it, using the code a
  /// device it can see showed it.
  @action
  Future<bool> confirmThisDevice(String code) async {
    errorMessage = null;
    final confirmation = DeviceConfirmation.tryParse(code);
    if (confirmation == null) {
      errorMessage = 'The code is incomplete. The whole code must be copied.';
      return false;
    }
    isSaving = true;
    try {
      await _readLocal();
      await _applyState(await _fetchState());
      final entry = chain.bySeq(confirmation.seq);
      final seq = thisDeviceSeq;
      if (entry == null ||
          chainBroken ||
          !confirmation.matches(entry) ||
          seq == null ||
          entry.seq < seq) {
        errorMessage =
            'The code does not match the device list. The list should not be '
            'trusted until the cause is known.';
        return false;
      }
      _pins
        ..firstHash = SealedFormats.encode(chain.entries.first.hash)
        ..headSeq = entry.seq
        ..headHash = SealedFormats.encode(entry.hash)
        ..reviewedSeq = entry.seq;
      await _savePins();
      confirmationInput.clear();
      await _refresh();
      _loadedFor = _scope;
      return status == SealingStatus.ready;
    } catch (e) {
      errorMessage = describeError(e);
      return false;
    } finally {
      isSaving = false;
    }
  }

  /// What removing [targetSeq] takes off the list with it, including itself.
  List<DeviceChainEntry> removalsFor(int targetSeq) {
    final seq = thisDeviceSeq;
    if (seq == null) return const [];
    return [
      for (final id in chain.removalsFor(targetSeq, keep: seq))
        if (chain.bySeq(id) != null) chain.bySeq(id)!,
    ];
  }

  /// Takes a device off the list, with everything it added, and replaces every
  /// key it held, so it can't read anything written from now on. Only true once
  /// the keys have actually been replaced.
  @action
  Future<bool> removeDevice(int targetSeq) async {
    errorMessage = null;
    isSaving = true;
    try {
      // Signed against the list as it stands now: another device may have
      // changed it, and an entry on a stale list would break it for everyone.
      await _applyState(await _fetchState());
      final seq = thisDeviceSeq;
      if (!_trusted || seq == null || targetSeq == seq) return false;
      if (!chain.isLive(targetSeq)) return true;
      final device = _device!;

      final entries = <DeviceChainEntry>[];
      var nextSeq = chain.nextSeq;
      var previous = chain.headHash;
      for (final id in chain.removalsFor(targetSeq, keep: seq)) {
        final entry = _removalEntry(
          seq: nextSeq++,
          target: id,
          previousHash: previous,
          signerSeq: seq,
          signer: device.signing,
        );
        entries.add(entry);
        previous = entry.hash;
      }
      await _commit(entries);
      await _refresh();
      if (_workspaces.values.any((held) => !held.writable)) {
        errorMessage =
            'The device was removed from the list, but the encryption key '
            'could not be replaced. Check the connection and reload.';
        return false;
      }
      return true;
    } catch (e) {
      errorMessage = describeError(e);
      return false;
    } finally {
      isSaving = false;
    }
  }

  /// Joins from the recovery key, for someone with no device left.
  ///
  /// The recovery key's public half is public, so finding it on a list proves
  /// nothing. Its own signature over the list's root proves the start is real,
  /// but it can't vouch for anything added since, and a server could serve a fork
  /// in which a removed thief is still on the list. So this device trusts no
  /// other device on it: it removes them all and starts a new key, which only it
  /// and the recovery key receive. The person adds their other devices again.
  ///
  /// Nothing is pinned until the server has shown all of that landed. Pinning
  /// sooner would leave a failed restore trusting the fork it was meant to
  /// escape, with the thief still on it.
  @action
  Future<bool> restoreWithRecoveryKey() async {
    errorMessage = null;
    final secret = RecoveryCode.decode(recoveryInput.text);
    if (secret == null) {
      errorMessage = 'The recovery key is incorrect. Check for typos.';
      return false;
    }
    isSaving = true;
    try {
      await _readLocal();
      await _applyState(await _fetchState());
      if (status == SealingStatus.untrusted) {
        errorMessage = 'The device list changed. Review it before continuing.';
        return false;
      }
      if (chainBroken || chain.entries.isEmpty) {
        errorMessage = 'This device cannot read the device list right now.';
        return false;
      }
      final hpke = RecoveryCode.hpkeKey(secret);
      final signing = RecoveryCode.signingKey(secret);
      final recovery = chain.liveRecovery;
      if (recovery == null ||
          !_sameBytes(recovery.hpkePublicKey, hpke.publicKey) ||
          !_sameBytes(recovery.signingPublicKey, signing.publicKey)) {
        errorMessage = 'The recovery key does not belong to this account.';
        return false;
      }
      final root = chain.entries.first.hash;
      if (!Sealing.verify(
        signing.publicKey,
        SealedFormats.recoveryAnchorPayload(_currentUser(), root),
        recovery.anchorSignature,
      )) {
        errorMessage = 'The recovery key does not belong to this account.';
        return false;
      }

      // Every device and passkey comes off: a thief with a stolen device could
      // have added either, and this device can't tell which.
      await _joinThrough(
        holder: recovery,
        hpke: hpke,
        signing: signing,
        root: root,
        removeSeqs: [
          for (final other in chain.live)
            if (other.kind != DeviceChainEntry.kindRecovery &&
                other.seq != thisDeviceSeq)
              other.seq,
        ],
      );

      recoveryInput.clear();
      await _refresh();
      _loadedFor = _scope;
      return status == SealingStatus.ready;
    } catch (e) {
      errorMessage = describeError(e);
      return false;
    } finally {
      isSaving = false;
    }
  }

  /// For someone who lost every device and their recovery key: deletes what
  /// nobody can read any more, and clears the way to set up again.
  @action
  Future<bool> startOver() async {
    if (!startOverConfirmed) return false;
    errorMessage = null;
    isSaving = true;
    try {
      await _api.post(
        '/api/sealed/reset',
        body: {'confirm': KeysStore.startOverPhrase},
      );
      await _storage.delete(key: _deviceStorageKey);
      await _storage.delete(key: _pinsStorageKey);
      forgetSession();
      await load();
      startOverConfirm.clear();
      return true;
    } catch (e) {
      errorMessage = describeError(e);
      return false;
    } finally {
      isSaving = false;
    }
  }

  /// Stops trusting the old list, after the person started over elsewhere. This
  /// device keeps its keys and what it knows of its records, and has to join like
  /// a new device: through a device that can vouch for the list, or the recovery
  /// key. So a server that forces this gets no way to read anything, and no way
  /// to roll back or downgrade a record this device has seen.
  @action
  Future<void> forgetThisDevice() async {
    _pins = _pins.keepingRecordHistory();
    await _savePins();
    await load();
  }

  /// Encrypts [value] under a fresh key for this version of this record. Throws
  /// [SealingException] when this device may not write in [workspace].
  SealedPayload sealValue({
    required String workspace,
    required String record,
    required String recordKey,
    required int version,
    required String value,
    String label = '',
    String type = 'text',
    String format = 'default',
    SealedFileInfo? file,
  }) {
    final held = _workspaces[workspace];
    if (held == null || !held.writable || !_trusted) {
      throw const SealingException(
        'This device cannot encrypt in this workspace right now.',
      );
    }
    final epoch = held.currentEpoch;
    final valueKey = Sealing.newSymmetricKey();
    return SealedPayload(
      valueKey: valueKey,
      sealedValue: SealedFormats.sealValue(
        valueKey: valueKey,
        value: SealedContent(
          value: value,
          label: label,
          type: type,
          format: format,
          file: file,
        ).encode(),
        workspace: workspace,
        record: record,
        recordKey: recordKey,
        version: version,
      ),
      keyEpoch: epoch,
      keyWrap: SealedFormats.wrapValueKey(
        workspaceKey: held.keys[epoch]!,
        valueKey: valueKey,
        workspace: workspace,
        record: record,
        version: version,
        epoch: epoch,
      ),
    );
  }

  ({String wrap, int epoch})? sealBookmarkKey({
    required Uint8List linkKey,
    required String server,
    required String origin,
    required String slug,
  }) {
    final held = _workspaces[_accountScope];
    if (held == null || !held.writable || !_trusted) return null;
    final epoch = held.currentEpoch;
    return (
      wrap: SealedFormats.wrapBookmarkKey(
        accountKey: held.keys[epoch]!,
        linkKey: linkKey,
        user: _currentUser(),
        server: server,
        origin: origin,
        slug: slug,
        epoch: epoch,
      ),
      epoch: epoch,
    );
  }

  Uint8List? openBookmarkKey({
    required String wrap,
    required int epoch,
    required String server,
    required String origin,
    required String slug,
  }) {
    if (status != SealingStatus.ready || !_trusted) return null;
    final key = _workspaces[_accountScope]?.keys[epoch];
    if (key == null) return null;
    try {
      return SealedFormats.openBookmarkKey(
        accountKey: key,
        wrapped: wrap,
        user: _currentUser(),
        server: server,
        origin: origin,
        slug: slug,
        epoch: epoch,
      );
    } on SealingException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Encrypts an identity's private key for the owner's other devices, under
  /// their account key, which no other member is ever handed. Null when this
  /// device holds no writable account key ([ensureAccountKey] first); the
  /// caller then leaves the key where it is.
  ({String wrap, int epoch})? sealIdentityKey({
    required String workspace,
    required String identity,
    required String privateKeyPem,
  }) {
    final held = _workspaces[_accountScope];
    if (held == null || !held.writable || !_trusted) return null;
    final epoch = held.currentEpoch;
    return (
      wrap: SealedFormats.wrapAccountIdentityKey(
        accountKey: held.keys[epoch]!,
        privateKeyPem: privateKeyPem,
        workspace: workspace,
        identity: identity,
        user: _currentUser(),
        epoch: epoch,
      ),
      epoch: epoch,
    );
  }

  /// Decrypts an identity key wrapped on some device of this account, or
  /// returns null when this device can't: it holds no key for that epoch, or
  /// the data doesn't authenticate. [scope] is the identity's sealedKeyScope:
  /// `account`, or empty for a key wrapped under the workspace key before
  /// account keys existed.
  String? openIdentityKey({
    required String workspace,
    required String identity,
    required int epoch,
    required String wrap,
    String scope = '',
  }) {
    if (status != SealingStatus.ready || !_trusted) return null;
    final account = scope == identityKeyScopeAccount;
    final key = _workspaces[account ? _accountScope : workspace]?.keys[epoch];
    if (key == null) return null;
    try {
      return account
          ? SealedFormats.openAccountIdentityKey(
              accountKey: key,
              wrapped: wrap,
              workspace: workspace,
              identity: identity,
              user: _currentUser(),
              epoch: epoch,
            )
          : SealedFormats.openIdentityKey(
              workspaceKey: key,
              wrapped: wrap,
              workspace: workspace,
              identity: identity,
              epoch: epoch,
            );
    } on SealingException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// The key this version of [record] is encrypted under, or null when this
  /// device can't open it. The same refusals as [openContent]: no key for its
  /// epoch, or a version or epoch older than this device has already seen.
  Uint8List? _valueKeyOf(models.Record record) {
    if (status != SealingStatus.ready || !record.sealed) return null;
    final key = _workspaces[record.workspace]?.keys[record.keyEpoch];
    if (key == null) return null;
    if (record.sealedVersion < (_pins.versions[record.id] ?? 0)) return null;
    if (record.keyEpoch < (_pins.recordEpochs[record.id] ?? 0)) return null;
    try {
      final valueKey = SealedFormats.openValueKey(
        workspaceKey: key,
        wrapped: record.keyWrap,
        workspace: record.workspace,
        record: record.id,
        version: record.sealedVersion,
        epoch: record.keyEpoch,
      );
      return valueKey.length == Sealing.keyLength ? valueKey : null;
    } on SealingException {
      return null;
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  /// A key for a link that is about to carry its first encrypted record. It
  /// travels in the link's address and never reaches the server
  /// (design/e2ee-sharing.md §3).
  Uint8List newLinkKey() => Sealing.newSymmetricKey();

  /// What [link] holds for [record] once it carries it: the record's current
  /// value key for whoever opens the link with [linkKey], and the key to that
  /// for whoever writes the record next. Null when this device can't open the
  /// record.
  Map<String, dynamic>? sealForLink({
    required Uint8List linkKey,
    required String link,
    required models.Record record,
  }) {
    final valueKey = _valueKeyOf(record);
    if (valueKey == null) return null;
    return {
      'record': record.id,
      'version': record.sealedVersion,
      ..._linkWraps(
        copyKey: SealedFormats.linkCopyKey(linkKey: linkKey, record: record.id),
        valueKey: valueKey,
        workspace: record.workspace,
        link: link,
        record: record.id,
        version: record.sealedVersion,
      ),
    };
  }

  /// A record's first encrypted version, while the payload is still in memory.
  Map<String, dynamic> initialLinkSeal({
    required Uint8List linkKey,
    required String link,
    required models.Record record,
    required Uint8List valueKey,
    required int version,
  }) => {
    'link': link,
    ..._linkWraps(
      copyKey: SealedFormats.linkCopyKey(linkKey: linkKey, record: record.id),
      valueKey: valueKey,
      workspace: record.workspace,
      link: link,
      record: record.id,
      version: version,
    ),
  };

  /// Carries [link] over to the version of [record] being written, whose
  /// value is under [nextValueKey]. [writerWrap] is what the link held for
  /// the version this device is replacing; it opens only with that version's
  /// value key, which is why a link the server made up can't be renewed.
  /// Null when it doesn't open.
  Map<String, dynamic>? renewLinkSeal({
    required String link,
    required String writerWrap,
    required models.Record record,
    required Uint8List nextValueKey,
    required int nextVersion,
  }) {
    final valueKey = _valueKeyOf(record);
    if (valueKey == null) return null;
    try {
      final copyKey = SealedFormats.openLinkWriter(
        valueKey: valueKey,
        wrapped: writerWrap,
        workspace: record.workspace,
        link: link,
        record: record.id,
        version: record.sealedVersion,
      );
      return {
        'link': link,
        'expectedWriterWrap': writerWrap,
        ..._linkWraps(
          copyKey: copyKey,
          valueKey: nextValueKey,
          workspace: record.workspace,
          link: link,
          record: record.id,
          version: nextVersion,
        ),
      };
    } on SealingException {
      return null;
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  Map<String, String> _linkWraps({
    required Uint8List copyKey,
    required Uint8List valueKey,
    required String workspace,
    required String link,
    required String record,
    required int version,
  }) => {
    'viewerWrap': SealedFormats.wrapLinkViewer(
      copyKey: copyKey,
      valueKey: valueKey,
      workspace: workspace,
      record: record,
      version: version,
    ),
    'writerWrap': SealedFormats.wrapLinkWriter(
      valueKey: valueKey,
      copyKey: copyKey,
      workspace: workspace,
      link: link,
      record: record,
      version: version,
    ),
  };

  /// [linkKey] for the devices that may show the link's address again: under
  /// this person's account key, and under the workspace's key when
  /// [forWorkspace] is set, which is for a link seen by more than its owner.
  /// Null when this device holds no writable key for a scope it was asked
  /// for ([ensureAccountKey] first).
  Map<String, dynamic>? wrapLinkKey({
    required Uint8List linkKey,
    required String link,
    required String workspace,
    bool forAccount = true,
    bool forWorkspace = false,
  }) {
    if (!_trusted) return null;
    final out = <String, dynamic>{};
    for (final scope in [
      if (forAccount) _accountScope,
      if (forWorkspace) workspace,
    ]) {
      final held = _workspaces[scope];
      if (held == null || !held.writable) return null;
      final epoch = held.currentEpoch;
      out[scope] = {
        'epoch': epoch,
        'wrap': SealedFormats.wrapLinkKey(
          scopeKey: held.keys[epoch]!,
          linkKey: linkKey,
          scope: scope,
          link: link,
          epoch: epoch,
        ),
      };
    }
    return out;
  }

  /// The key of [link] from what the server keeps of it in [wraps], or null
  /// when none of them opens on this device: its owner's copy opens for the
  /// owner alone, the workspace's for whoever holds the workspace's key.
  Uint8List? openLinkKey({
    required String link,
    required String workspace,
    required Map<String, dynamic> wraps,
  }) {
    if (status != SealingStatus.ready || !_trusted) return null;
    for (final scope in [_accountScope, workspace]) {
      final entry = wraps[scope];
      if (entry is! Map) continue;
      final epoch = (entry['epoch'] as num?)?.toInt();
      final wrap = entry['wrap'];
      final key = _workspaces[scope]?.keys[epoch];
      if (epoch == null || wrap is! String || key == null) continue;
      try {
        return SealedFormats.openLinkKey(
          scopeKey: key,
          wrapped: wrap,
          scope: scope,
          link: link,
          epoch: epoch,
        );
      } on SealingException {
        continue;
      } on FormatException {
        continue;
      } on RangeError {
        continue;
      }
    }
    return null;
  }

  /// The key new values go under, when this device may write in [workspace].
  int? writableEpoch(String workspace) {
    final held = _workspaces[workspace];
    return held != null && held.writable && _trusted ? held.currentEpoch : null;
  }

  /// Remembers a value this device just wrote, so the server can't serve the
  /// previous one straight afterwards.
  void noteWritten(String record, {required int version, required int epoch}) {
    _pins.versions[record] = version;
    _pins.recordEpochs[record] = epoch;
    _pins.acceptedPlain.remove(record);
    unawaited(_savePins());
  }

  /// Decrypts a sealed record, or returns null if this device can't: it holds no
  /// key, the data doesn't authenticate, or it is older than what this device
  /// has already seen. Any malformed row is treated the same way, so one bad row
  /// can't take down the whole vault.
  String? openRecord(models.Record record) => openContent(record)?.value;

  /// What [openRecord] decrypts, with the label and format that travel inside it.
  SealedContent? openContent(models.Record record) {
    if (status != SealingStatus.ready) return null;
    final held = _workspaces[record.workspace];
    final key = held?.keys[record.keyEpoch];
    if (key == null) return null;
    if (record.sealedVersion < (_pins.versions[record.id] ?? 0)) return null;
    // A removed device still has old keys. Without this it could, with the
    // server's help, write a "newer" version under a key this record has left.
    if (record.keyEpoch < (_pins.recordEpochs[record.id] ?? 0)) return null;
    try {
      final valueKey = SealedFormats.openValueKey(
        workspaceKey: key,
        wrapped: record.keyWrap,
        workspace: record.workspace,
        record: record.id,
        version: record.sealedVersion,
        epoch: record.keyEpoch,
      );
      if (valueKey.length != Sealing.keyLength) return null;
      final content = SealedContent.decode(
        SealedFormats.openValue(
          valueKey: valueKey,
          sealed: record.sealedValue,
          workspace: record.workspace,
          record: record.id,
          recordKey: record.key,
          version: record.sealedVersion,
        ),
      );
      if (_pins.versions[record.id] != record.sealedVersion ||
          _pins.recordEpochs[record.id] != record.keyEpoch ||
          _pins.acceptedPlain.containsKey(record.id)) {
        noteWritten(
          record.id,
          version: record.sealedVersion,
          epoch: record.keyEpoch,
        );
      }
      return content;
    } on SealingException {
      return null;
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    } on ArgumentError {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// The proof the server wants before storing a sealed record in plaintext.
  Map<String, dynamic> signUnseal({
    required String record,
    required int expectedVersion,
    required String value,
  }) {
    final device = _device;
    final seq = thisDeviceSeq;
    if (!_trusted || device == null || seq == null) {
      throw const SealingException('This device cannot change that right now.');
    }
    return {
      'deviceSeq': seq,
      'signature': SealedFormats.encode(
        Sealing.sign(
          device.signing,
          SealedFormats.unsealPayload(
            _currentUser(),
            record,
            expectedVersion,
            value,
          ),
        ),
      ),
    };
  }

  /// Ends this account's other sessions. A removed device's session otherwise
  /// keeps working, and can go on reading plain records and deleting sealed ones.
  @action
  Future<bool> signOutOtherSessions() async {
    errorMessage = null;
    isSaving = true;
    try {
      final data = await _api.post('/api/sealed/sessions/revoke');
      final token = (data as Map<String, dynamic>)['token'] as String;
      await _api.replaceToken(token);
      return true;
    } catch (e) {
      errorMessage = describeError(e);
      return false;
    } finally {
      isSaving = false;
    }
  }

  /// Whether this device knows [recordId] as encrypted, so a plain copy now
  /// means someone unsealed it, or the server is passing off a value of its own.
  /// Plain writes to it are refused until the person says it was them.
  bool knewAsSealed(String recordId) =>
      _pins.versions.containsKey(recordId) &&
      !_pins.acceptedPlain.containsKey(recordId);

  /// The person confirmed they unsealed it themselves. The version stays pinned:
  /// resealing moves it forward, so an old sealed copy can't come back.
  Future<void> acceptUnsealed(String recordId) async {
    final version = _pins.versions[recordId];
    if (version == null) return;
    _pins.acceptedPlain[recordId] = version;
    await _savePins();
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
