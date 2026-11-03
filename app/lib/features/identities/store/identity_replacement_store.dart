import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/credential.dart';
import 'package:revoked_app/core/models/identity.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/features/attestations/store/credentials_store.dart';
import 'package:revoked_app/features/identities/store/identities_store.dart';

part 'identity_replacement_store.g.dart';

/// Where a replacement stands.
enum ReplacementStage {
  /// Choosing what takes the old identity's place.
  choosing,

  /// Attestations are being moved.
  moving,

  /// Some attestations could not be moved: retry, revoke anyway, or leave
  /// both identities standing for now.
  review,

  /// Every attestation moved, or the person let the rest go, and the old
  /// identity is revoked.
  done,
}

/// An attestation that stayed on the identity being replaced, and why.
class ReissueFailure {
  final Credential credential;
  final String reason;

  const ReissueFailure(this.credential, this.reason);
}

/// Replacing an identity: another identity takes its place, every
/// attestation bound to the old one is issued again for the new one, and the
/// old one is revoked.
///
/// The old identity's key authorizes each move, so no issuer has to involve a
/// person. It is revoked last, because revoking it is what ends that key's say:
/// once revoked, nothing bound to it can be moved any more. An issuer that
/// cannot be reached leaves its attestation on the old identity, and the
/// person decides — retry, or revoke anyway and let it go with the old one.
// ignore: library_private_types_in_public_api
class IdentityReplacementStore = _IdentityReplacementStore
    with _$IdentityReplacementStore;

abstract class _IdentityReplacementStore with Store {
  final IdentitiesStore _identities;
  final CredentialsStore _credentials;

  _IdentityReplacementStore(this._identities, this._credentials);

  /// The name of a new identity taking the old one's place.
  final ObservableTextController nameController = ObservableTextController();

  /// The identity being replaced.
  @observable
  Identity? from;

  /// The identity taking its place, once there is one.
  @observable
  Identity? to;

  /// An identity the person already has, chosen to take the old one's place;
  /// null for a new one.
  @observable
  String? targetId;

  @observable
  ReplacementStage stage = ReplacementStage.choosing;

  /// Why the replacement could not go on: the new identity could not be
  /// made, or the old one could not be revoked.
  @observable
  String? errorMessage;

  /// Attestations still to be moved, in order.
  final ObservableList<Credential> pending = ObservableList<Credential>();

  /// Attestations now bound to [to].
  final ObservableList<Credential> moved = ObservableList<Credential>();

  /// Attestations that stayed on [from].
  final ObservableList<ReissueFailure> failed =
      ObservableList<ReissueFailure>();

  /// The identities that can take [from]'s place as they are: standing, in
  /// the same workspace, and able to sign on this device.
  @computed
  List<Identity> get targets {
    final old = from;
    if (old == null) return const [];
    return [
      for (final i in _identities.identities)
        if (i.id != old.id &&
            !i.isRevoked &&
            i.workspace == old.workspace &&
            _identities.hasLocalKey(i.id))
          i,
    ];
  }

  /// The attestations that would move now.
  @computed
  List<Credential> get bound {
    final old = from;
    return old == null ? const [] : _credentials.boundTo(old.id);
  }

  /// What stops the replacement from starting, or null when nothing does.
  @computed
  String? get problem {
    final old = from;
    if (old == null) return 'No identity is being replaced.';
    if (!_identities.hasLocalKey(old.id)) {
      return 'The key of ${old.name} is not on this device, so it cannot '
          'vouch for another identity from here.';
    }
    if (targetId == null && nameController.text.trim().isEmpty) {
      return 'A name for the new identity is required.';
    }
    return null;
  }

  @action
  void begin(Identity identity) {
    from = identity;
    to = null;
    targetId = null;
    stage = ReplacementStage.choosing;
    errorMessage = null;
    pending.clear();
    moved.clear();
    failed.clear();
    nameController.text = identity.name;
    _credentials.loadIfDue();
  }

  @action
  void chooseTarget(String? identityId) => targetId = identityId;

  /// Makes or takes the identity that replaces [from], then moves every
  /// attestation bound to [from] to it.
  @action
  Future<void> start() async {
    final old = from;
    if (old == null || problem != null) return;
    errorMessage = null;
    stage = ReplacementStage.moving;

    var next = to;
    if (next == null && targetId != null) {
      next = _identities.byId(targetId!);
    }
    if (next == null) {
      final before = {for (final i in _identities.identities) i.id};
      final created = await _identities.createIdentity(
        name: nameController.text.trim(),
        isPrimary: old.isPrimary,
      );
      if (!created) {
        errorMessage =
            _identities.errorMessage ?? 'The new identity could not be made.';
        stage = ReplacementStage.choosing;
        return;
      }
      for (final i in _identities.identities) {
        if (!before.contains(i.id)) next = i;
      }
      if (next == null) {
        errorMessage = 'The new identity could not be found.';
        stage = ReplacementStage.choosing;
        return;
      }
    }
    to = next;
    // The primary signs by default; whatever replaces it takes that over.
    if (old.isPrimary) await _identities.setPrimary(next.id);

    await _credentials.load();
    await _move(_credentials.boundTo(old.id));
  }

  /// Tries the attestations that stayed on [from] once more.
  @action
  Future<void> retry() async {
    final again = [for (final f in failed) f.credential];
    failed.clear();
    errorMessage = null;
    stage = ReplacementStage.moving;
    await _move(again);
  }

  /// Revokes [from] although some attestations stayed on it. They stop being
  /// valid with it.
  @action
  Future<void> revokeAnyway() async {
    errorMessage = null;
    await _retire();
  }

  @action
  Future<void> _move(List<Credential> credentials) async {
    final old = from, next = to;
    if (old == null || next == null) return;
    pending
      ..clear()
      ..addAll(credentials);
    // One at a time and each on its own: one issuer that cannot be reached
    // leaves only its own attestation behind.
    for (final c in credentials) {
      try {
        final kept = await _credentials.reissue(
          credential: c,
          from: old,
          to: next,
        );
        moved.add(kept);
      } catch (e) {
        failed.add(ReissueFailure(c, describeError(e)));
      }
      pending.remove(c);
    }
    if (failed.isEmpty) {
      await _retire();
    } else {
      stage = ReplacementStage.review;
    }
  }

  @action
  Future<void> _retire() async {
    final old = from;
    if (old == null) return;
    final ok = await _identities.revokeIdentity(old.id);
    if (ok) {
      stage = ReplacementStage.done;
    } else {
      errorMessage =
          _identities.errorMessage ?? '${old.name} could not be revoked.';
      stage = ReplacementStage.review;
    }
  }
}
