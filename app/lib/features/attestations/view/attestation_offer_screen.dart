import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/feature.dart';
import 'package:revoked_app/core/models/attestation.dart';
import 'package:revoked_app/core/models/credential.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_flow_scaffold.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_trust_badge.dart';
import 'package:revoked_app/core/widgets/identity_picker.dart';
import 'package:revoked_app/features/attestations/claim_text.dart';

/// Screen for a `revoked://a/<host>/<token>` link: someone offers to attest
/// something about one of this person's identities.
///
/// What would be stated, and by which domain, is shown before anything is
/// decided. Accepting signs the issuer's challenge with the chosen identity's
/// key — proof that the identity is this person's — and the credential that
/// comes back is kept on their own server.
class AttestationOfferScreen extends StatefulWidget {
  final String token;

  /// host[:port] the offer says it lives on; null = the signed-in server.
  final String? origin;

  const AttestationOfferScreen({super.key, required this.token, this.origin});

  @override
  State<AttestationOfferScreen> createState() => _AttestationOfferScreenState();
}

class _AttestationOfferScreenState extends State<AttestationOfferScreen> {
  /// The identity the credential would be issued to. Null until the person
  /// picks one, or one is the obvious choice.
  final _identity = Local<String?>(null);
  final _accepted = Local<Credential?>(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final identities = Stores.identities;
    await Future.wait([
      Stores.credentials.probeOffer(widget.token, widget.origin),
      if (identities.identities.isEmpty) identities.loadIdentities(),
    ]);
    if (!mounted) return;
    _identity.value = _suggested();
  }

  /// The identity an offer made for one identity names, when it is among
  /// this person's; otherwise their primary one.
  String? _suggested() {
    final store = Stores.identities;
    final usable = store.identities.where(
      (i) => !i.isRevoked && store.hasLocalKey(i.id),
    );
    final bound = Stores.credentials.offer?.subjectFingerprint ?? '';
    for (final i in usable) {
      if (bound.isNotEmpty && i.fingerprint == bound) return i.id;
    }
    return store.defaultSigner()?.id;
  }

  Future<void> _accept() async {
    final id = _identity.value;
    if (id == null) return;
    final kept = await Stores.credentials.acceptOffer(
      token: widget.token,
      origin: widget.origin,
      identityId: id,
    );
    if (!mounted) return;
    if (kept != null) _accepted.value = kept;
  }

  void _leave() {
    Stores.credentials.clearOffer();
    context.go(AppRoutes.overview);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final store = Stores.credentials;
    final offer = store.offer;
    final accepted = _accepted.value;
    final deciding = offer != null && accepted == null;

    return AppFlowScaffold(
      title: offer == null ? 'Attestation offer' : offer.title,
      subtitle: offer == null || offer.serverDomain.isEmpty
          ? null
          : 'Offered by ${offer.serverDomain}',
      closeLabel: deciding ? 'Decline and go back' : 'Back to the app',
      onClose: _leave,
      bottomBar: deciding ? _decision(context, offer) : null,
      feature: Feature.attestations,
      body: accepted != null
          ? _kept(context, accepted)
          : offer != null
          ? _consent(context, offer)
          : store.offerError != null
          ? _unavailable(context)
          : const Center(child: AppSpinner(large: true)),
    );
  }

  Widget _unavailable(BuildContext context) {
    final error = Stores.credentials.offerError!;
    return AppStatusMessage(
      icon: AppIcons.exclamationTriangle,
      accent: Theme.of(context).colorScheme.error,
      title: error.title,
      message: error.description,
      actions: [
        AppButton(
          label: 'Back to the app',
          icon: AppIcons.arrowLeft,
          style: AppButtonStyle.accent,
          onTap: _leave,
        ),
      ],
    );
  }

  Widget _kept(BuildContext context, Credential credential) {
    return AppStatusMessage(
      icon: AppIcons.checkCircle,
      accent: Theme.of(context).colorScheme.success,
      title: 'Attestation accepted',
      message:
          '${credential.issuer} confirmed “${credential.type}”. It is stored '
          'under Attestations. The details shared are chosen each time it is '
          'shown.',
      actions: [
        AppButton(
          label: 'See attestations',
          icon: AppIcons.shieldCheck,
          onTap: () {
            Stores.credentials.clearOffer();
            context.go(AppRoutes.attestationsHeld);
          },
        ),
        AppButton(
          label: 'Done',
          icon: AppIcons.check,
          style: AppButtonStyle.accent,
          onTap: _leave,
        ),
      ],
    );
  }

  Widget _trust() {
    final store = Stores.credentials;
    final verdict = store.offerTrust;
    if (verdict != null) return AppTrustBadge(verdict: verdict);
    if (!store.isVerifyingOffer) return const SizedBox.shrink();
    return const Row(
      children: [
        AppSpinner(),
        SizedBox(width: AppSpacing.sm),
        Text('Verifying the sender…'),
      ],
    );
  }

  Widget _consent(BuildContext context, AttestationOffer offer) {
    final store = Stores.credentials;
    final error = store.offerError;
    final verdict = store.offerTrust;
    final proven = verdict?.state == TrustState.verified;

    return AppPageBody(
      bottomPadding: AppSpacing.xxl,
      children: [
        _trust(),
        AppListGroup(
          title: 'Issuer',
          trailing: const SizedBox.shrink(),
          footer: Text(
            proven
                ? 'This domain is shown as the issuer to anyone who checks it.'
                : 'This server could not be verified as '
                      '${offer.serverDomain}. Any check of this attestation '
                      'will reject it.',
          ),
          children: [
            AppDetailRow(
              icon: AppIcons.globe,
              label: 'Domain',
              value: offer.serverDomain,
            ),
            if (offer.workspaceName.isNotEmpty)
              AppDetailRow(
                icon: AppIcons.personWorkspace,
                label: 'Workspace',
                value: offer.workspaceName,
              ),
          ],
        ),
        AppListGroup(
          title: 'Details',
          trailing: const SizedBox.shrink(),
          footer: Text(
            offer.wasAccepted
                ? 'Already accepted. The same identity can fetch it again.'
                : 'The details shared are chosen each time it is shown.',
          ),
          children: [
            AppDetailRow(icon: AppIcons.tag, label: 'Kind', value: offer.type),
            for (final entry in offer.claims.entries)
              AppDetailRow(label: entry.key, value: claimText(entry.value)),
            if (offer.expiresAt != null)
              AppDetailRow(
                icon: AppIcons.clock,
                label: 'Valid until',
                value: dayText(offer.expiresAt),
              ),
          ],
        ),
        AppListGroup(
          title: 'Identity',
          trailing: const SizedBox.shrink(),
          footer: Text(
            offer.subjectFingerprint.isEmpty
                ? 'Bound to this identity. Its key stays on this device, and '
                      'only this identity can show the attestation.'
                : 'This offer is restricted to one identity and can only be '
                      'accepted with it.',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: IdentityPicker(
                selectedId: _identity.value,
                onChanged: (id) => _identity.value = id,
              ),
            ),
          ],
        ),
        if (error != null)
          AppAlert(
            destructive: true,
            title: Text(error.title),
            content: Text(error.description).small,
          ),
      ],
    );
  }

  Widget _decision(BuildContext context, AttestationOffer offer) {
    final store = Stores.credentials;
    final busy = store.isAccepting;
    // A server that contradicts its own DNS pin is not accepted from at all.
    final blocked = store.offerTrust?.allowsSubmit == false;
    final ready = _identity.value != null && !blocked;
    return AppActionBar(
      note: Text(
        blocked
            ? 'This server does not match its domain’s DNS record. Nothing '
                  'from it can be accepted.'
            : 'Accepting proves ownership of this identity to '
                  '${offer.serverDomain}. Nothing else is sent.',
      ).muted.small,
      children: [
        AppButton(
          label: 'Decline',
          icon: AppIcons.x,
          style: AppButtonStyle.accent,
          onTap: busy ? null : _leave,
        ),
        AppButton(
          label: offer.wasAccepted ? 'Fetch again' : 'Accept',
          icon: AppIcons.shieldCheck,
          busy: busy,
          onTap: busy || !ready ? null : _accept,
        ),
      ],
    );
  }
}
