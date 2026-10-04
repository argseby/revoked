import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/attestation.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';

part 'attestations_store.g.dart';

/// How a claim's value is written into a credential.
enum ClaimKind {
  text('Text'),
  yesNo('Yes / No'),
  number('Number');

  const ClaimKind(this.label);
  final String label;
}

/// One claim being typed into a new attestation.
class ClaimDraft {
  final ObservableTextController name = ObservableTextController();
  final ObservableTextController value = ObservableTextController();
  final Observable<ClaimKind> _kind = Observable(ClaimKind.text);
  final Observable<bool> _yes = Observable(true);

  ClaimKind get kind => _kind.value;
  set kind(ClaimKind next) => runInAction(() => _kind.value = next);

  /// The value of a yes/no claim.
  bool get yes => _yes.value;
  set yes(bool next) => runInAction(() => _yes.value = next);

  static final _name = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$');

  String get trimmedName => name.text.trim();

  bool get isBlank => trimmedName.isEmpty && value.text.trim().isEmpty;

  /// What is wrong with it, or null. A row left blank is skipped, not wrong.
  String? get problem {
    if (isBlank) return null;
    if (!_name.hasMatch(trimmedName)) {
      return 'A claim name is letters, digits and underscores, starting '
          'with a letter.';
    }
    switch (kind) {
      case ClaimKind.text:
        if (value.text.trim().isEmpty) return 'A claim needs a value.';
      case ClaimKind.number:
        if (num.tryParse(value.text.trim()) == null) {
          return '“${value.text.trim()}” is not a number.';
        }
      case ClaimKind.yesNo:
        break;
    }
    return null;
  }

  /// The value as the credential states it.
  Object get encoded => switch (kind) {
    ClaimKind.text => value.text.trim(),
    ClaimKind.yesNo => yes,
    ClaimKind.number => num.parse(value.text.trim()),
  };
}

/// The attestations this workspace has issued, and the draft of a new one.
///
/// An attestation is a statement in the name of the server's domain, so the
/// server decides who may make one: its operator switches issuing on, and a
/// member needs the permission. Both refusals arrive as typed errors and are
/// shown as they are.
// ignore: library_private_types_in_public_api
class AttestationsStore = _AttestationsStore with _$AttestationsStore;

abstract class _AttestationsStore with Store {
  final ApiClient _api;

  _AttestationsStore(this._api);

  String get _basePath =>
      '/api/collections/${AppConfig.attestationsCollection}/records';

  final ObservableList<Attestation> attestations =
      ObservableList<Attestation>();

  @observable
  bool isLoading = false;

  /// Why the list could not be read, when it could not.
  @observable
  AppErrorMessage? error;

  /// Whether this server issues attestations at all: its operator's choice.
  /// Null until the server was asked.
  @observable
  bool? issuingAllowed;

  @action
  Future<void> load() async {
    isLoading = true;
    error = null;
    try {
      await loadPolicy();
      final workspace = _api.userData?['activeWorkspace'] as String? ?? '';
      final data = await _api.get(
        _basePath,
        queryParams: {
          'sort': '-created',
          if (workspace.isNotEmpty) 'filter': 'workspace = "$workspace"',
        },
      );
      final items = (data['items'] as List<dynamic>?) ?? [];
      attestations
        ..clear()
        ..addAll(
          items.map((e) => Attestation.fromJson(e as Map<String, dynamic>)),
        );
    } catch (e) {
      attestations.clear();
      error = AppErrorMessage.fromException(e);
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<void> loadPolicy() async {
    try {
      final data = await _api.get('/api/server');
      final policy = (data as Map<String, dynamic>)['attestations'];
      issuingAllowed =
          policy is Map<String, dynamic> && policy['issuing'] == true;
    } catch (_) {
      // Unknown stays unknown; creating one will say so if it is off.
    }
  }

  // The draft of a new attestation. Owned here rather than by the sheet, so
  // a half-written one survives the sheet being closed and reopened.

  final ObservableTextController typeController = ObservableTextController();
  final ObservableTextController labelController = ObservableTextController();
  final ObservableTextController subjectController = ObservableTextController();
  final ObservableTextController validDaysController =
      ObservableTextController();
  final ObservableList<ClaimDraft> draftClaims = ObservableList<ClaimDraft>();

  @observable
  bool isCreating = false;

  @observable
  AppErrorMessage? createError;

  /// The link of the offer just created. Shown once: the server keeps only a
  /// hash of its token, so it cannot be retrieved again.
  @observable
  String? lastCreatedToken;

  @action
  void resetDraft() {
    typeController.clear();
    labelController.clear();
    subjectController.clear();
    validDaysController.clear();
    draftClaims
      ..clear()
      ..add(ClaimDraft());
    isCreating = false;
    createError = null;
    lastCreatedToken = null;
  }

  @action
  void addClaim() => draftClaims.add(ClaimDraft());

  @action
  void removeClaim(ClaimDraft claim) {
    draftClaims.remove(claim);
    if (draftClaims.isEmpty) draftClaims.add(ClaimDraft());
  }

  static final _type = RegExp(r'^[\x21-\x7e]{1,255}$');
  static final _fingerprint = RegExp(r'^[0-9a-f]{64}$');

  /// What stops the draft from being issued, or null when nothing does.
  @computed
  String? get draftProblem {
    final type = typeController.text.trim();
    if (type.isEmpty) return 'Give the attestation a type.';
    if (!_type.hasMatch(type)) {
      return 'A type is written without spaces, for example membership.';
    }
    final names = <String>{};
    for (final claim in draftClaims) {
      final problem = claim.problem;
      if (problem != null) return problem;
      if (claim.isBlank) continue;
      if (!names.add(claim.trimmedName)) {
        return 'The claim “${claim.trimmedName}” is stated twice.';
      }
    }
    final subject = subjectController.text.trim().toLowerCase();
    if (subject.isNotEmpty && !_fingerprint.hasMatch(subject)) {
      return 'An identity is named by its fingerprint: 64 hexadecimal '
          'characters.';
    }
    final days = validDaysController.text.trim();
    if (days.isNotEmpty && (int.tryParse(days) ?? 0) < 1) {
      return 'The validity is a number of days, or left empty.';
    }
    return null;
  }

  /// Creates the offer. True when it exists; [lastCreatedToken] then holds
  /// the one-time token of its link.
  @action
  Future<bool> create() async {
    if (draftProblem != null) return false;
    isCreating = true;
    createError = null;
    try {
      final user = _api.userData?['id'] as String?;
      final workspace = _api.userData?['activeWorkspace'] as String?;
      if (user == null ||
          user.isEmpty ||
          workspace == null ||
          workspace.isEmpty) {
        throw StateError(
          'Cannot issue an attestation: no signed-in user or active '
          'workspace.',
        );
      }
      final days = int.tryParse(validDaysController.text.trim());
      final subject = subjectController.text.trim().toLowerCase();
      final response = await _api.postWithHeaders(
        _basePath,
        body: {
          'user': user,
          'workspace': workspace,
          'type': typeController.text.trim(),
          'label': labelController.text.trim(),
          'claims': {
            for (final claim in draftClaims)
              if (!claim.isBlank) claim.trimmedName: claim.encoded,
          },
          if (subject.isNotEmpty) 'subjectFingerprint': subject,
          if (days != null)
            'expiresAt': DateTime.now()
                .toUtc()
                .add(Duration(days: days))
                .toIso8601String(),
        },
      );
      final created = Attestation.fromJson(
        response.body as Map<String, dynamic>,
      );
      attestations.insert(0, created);
      lastCreatedToken =
          response.headers['x-attestation-token'] ??
          response.headers['X-Attestation-Token'];
      return true;
    } catch (e) {
      createError = AppErrorMessage.fromException(e);
      return false;
    } finally {
      isCreating = false;
    }
  }

  /// Withdraws an offer, or revokes an issued attestation. Either way it
  /// does not come back: a revocation is published, and verifiers read it.
  @action
  Future<bool> revoke(String id) async {
    error = null;
    try {
      final data = await _api.patch(
        '$_basePath/$id',
        body: {'status': 'revoked'},
      );
      final updated = Attestation.fromJson(data as Map<String, dynamic>);
      final idx = attestations.indexWhere((a) => a.id == id);
      if (idx != -1) attestations[idx] = updated;
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    }
  }

  /// Removes the row. An issued attestation is revoked by this as well: the
  /// credential stays out there, and deleting must not leave it valid.
  @action
  Future<bool> remove(String id) async {
    error = null;
    try {
      await _api.delete('$_basePath/$id');
      attestations.removeWhere((a) => a.id == id);
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    }
  }
}
