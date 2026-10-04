import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:mobx/mobx.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/credential.dart';
import 'package:revoked_app/core/models/presentation_request.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_flow_scaffold.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/features/attestations/claim_text.dart';

/// Screen for a `revoked://present?…` link: a service asks to be shown an
/// attestation.
///
/// The person sees who asks and for what, picks one of the credentials that
/// fit, and decides claim by claim what travels. The presentation is made on
/// this device, signed with the identity key, and bound to this one request:
/// the service cannot pass it on, and nobody who copies it can use it.
class PresentationScreen extends StatefulWidget {
  /// Null when the link was malformed; the screen then says so.
  final PresentationRequest? request;

  const PresentationScreen({super.key, required this.request});

  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _PresentationScreenState extends State<PresentationScreen> {
  final _loading = Local<bool>(true);
  final _selected = Local<String?>(null);
  final _done = Local<bool>(false);
  final _next = Local<Uri?>(null);

  /// The claims that travel, for the credential currently selected.
  final ObservableSet<String> _disclose = ObservableSet<String>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final request = widget.request;
    if (request == null) {
      _loading.value = false;
      return;
    }
    await Stores.credentials.load();
    if (Stores.identities.identities.isEmpty) {
      await Stores.identities.loadIdentities();
    }
    if (!mounted) return;
    final fitting = Stores.credentials.matching(request);
    if (fitting.isNotEmpty) _select(fitting.first);
    _loading.value = false;
  }

  /// Picks a credential and starts from what the service asked for: the
  /// claims it named that this credential holds, and nothing else.
  void _select(Credential credential) {
    final held = credential.disclosures.map((d) => d.name).toSet();
    runInAction(() {
      _disclose
        ..clear()
        ..addAll(widget.request!.claims.where(held.contains));
    });
    _selected.value = credential.id;
  }

  Credential? get _credential {
    final id = _selected.value;
    for (final c in Stores.credentials.credentials) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _share() async {
    final request = widget.request!;
    final credential = _credential;
    if (credential == null) return;
    final outcome = await Stores.credentials.present(
      request: request,
      credential: credential,
      disclose: _disclose.toList(),
    );
    if (!mounted || !outcome.delivered) return;
    _next.value = outcome.next;
    _done.value = true;
    if (outcome.next != null) await _continue();
  }

  Future<void> _continue() async {
    final next = _next.value;
    if (next == null) return;
    await launchUrl(
      next,
      mode: LaunchMode.externalApplication,
    ).catchError((Object _) => false);
  }

  void _leave() => context.go(AppRoutes.vault);

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final r = widget.request;
    // Read first, so the Observer has something to follow even for a link
    // that could not be read.
    final loading = _loading.value;
    final done = _done.value;
    final fitting = r == null
        ? const <Credential>[]
        : Stores.credentials.matching(r);
    final deciding = r != null && !loading && !done && fitting.isNotEmpty;

    return AppFlowScaffold(
      title: r == null
          ? 'Show an attestation'
          : '${r.clientHost} asks for an attestation',
      subtitle: r == null ? null : 'Presentation request from ${r.clientHost}',
      closeLabel: deciding ? 'Decline and go back' : 'Back to the app',
      onClose: _leave,
      bottomBar: deciding ? _decision(context, r) : null,
      body: r == null
          ? _invalid(context)
          : loading
          ? const Center(child: AppSpinner(large: true))
          : done
          ? _shown(context, r)
          : fitting.isEmpty
          ? _nothingFits(context, r)
          : _consent(context, r, fitting),
    );
  }

  Widget _invalid(BuildContext context) {
    return AppStatusMessage(
      icon: AppIcons.exclamationTriangle,
      accent: Theme.of(context).colorScheme.error,
      title: 'This link doesn’t work',
      message:
          'It doesn’t describe a request that Revoked can answer. Start '
          'again on the service that sent it.',
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

  Widget _nothingFits(BuildContext context, PresentationRequest r) {
    final from = r.issuers.isEmpty ? '' : ' from ${r.issuers.join(' or ')}';
    return AppStatusMessage(
      icon: AppIcons.info,
      title: 'No attestation fits',
      message:
          '${r.clientHost} asks for '
          '${r.type.isEmpty ? 'an attestation' : '“${r.type}”'}$from, and '
          'none of the attestations held here is one. Nothing was shown.',
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

  Widget _shown(BuildContext context, PresentationRequest r) {
    final next = _next.value;
    return AppStatusMessage(
      icon: AppIcons.checkCircle,
      accent: Theme.of(context).colorScheme.success,
      title: 'Shown to ${r.clientHost}',
      message:
          'The attestation was presented with the claims that were ticked, '
          'and nothing else. It was made for this one request and cannot be '
          'used again.',
      actions: [
        if (next != null)
          AppButton(
            label: 'Continue on ${r.clientHost}',
            icon: AppIcons.boxArrowUpRight,
            onTap: _continue,
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

  String _identityName(Credential c) =>
      Stores.identities.byId(c.identity)?.name ?? 'an identity';

  Widget _consent(
    BuildContext context,
    PresentationRequest r,
    List<Credential> fitting,
  ) {
    final credential = _credential;
    final error = Stores.credentials.presentError;
    final scheme = Theme.of(context).colorScheme;

    return AppPageBody(
      bottomPadding: AppSpacing.xxl,
      children: [
        AppListGroup(
          title: 'Who is asking',
          trailing: const SizedBox.shrink(),
          footer: const Text(
            'The address is what identifies the service. Only continue if it '
            'is the one this request was expected from.',
          ),
          children: [
            AppDetailRow(
              icon: AppIcons.globe,
              label: 'Address',
              value: r.clientHost,
            ),
            AppDetailRow(
              icon: AppIcons.tag,
              label: 'Asks for',
              value: r.type.isEmpty ? 'Any attestation' : r.type,
            ),
            AppDetailRow(
              icon: AppIcons.shieldCheck,
              label: 'Attested by',
              value: r.issuers.isEmpty ? 'Any attester' : r.issuers.join(', '),
            ),
          ],
        ),
        AppListGroup(
          title: 'Which attestation',
          trailing: const SizedBox.shrink(),
          children: [
            for (final c in fitting)
              AppListRow(
                icon: AppIcons.shieldCheck,
                title: c.type,
                subtitle: 'From ${c.issuer} · held by ${_identityName(c)}',
                showChevron: false,
                trailing: c.id == _selected.value
                    ? Icon(AppIcons.checkCircle, color: scheme.primary)
                    : Icon(AppIcons.circle, color: scheme.outline),
                onTap: () => _select(c),
              ),
          ],
        ),
        if (credential != null)
          AppListGroup(
            title: 'What is shown',
            trailing: const SizedBox.shrink(),
            footer: const Text(
              'A claim left unticked is withheld: the service learns that the '
              'attestation holds more, not what. Who attested, the type and '
              'the identity it was issued to are always shown.',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (credential.disclosures.isEmpty)
                      const Text(
                        'This attestation states nothing beyond its type.',
                      ).muted.small,
                    for (final d in credential.disclosures)
                      AppCheckRow(
                        label: d.name,
                        subtitle: claimText(d.value),
                        badge: r.claims.contains(d.name)
                            ? const AppBadge(label: 'Asked for')
                            : null,
                        value: _disclose.contains(d.name),
                        onChanged: (on) => runInAction(
                          () => on
                              ? _disclose.add(d.name)
                              : _disclose.remove(d.name),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        if (error != null)
          AppAlert(
            destructive: true,
            title: const Text('The attestation could not be shown'),
            content: Text(error).small,
          ),
      ],
    );
  }

  Widget _decision(BuildContext context, PresentationRequest r) {
    final busy = Stores.credentials.isPresenting;
    final count = _disclose.length;
    return AppActionBar(
      note: Text(
        count == 0
            ? '${r.clientHost} learns that you hold this attestation, and '
                  'none of its claims.'
            : '${r.clientHost} learns $count '
                  '${count == 1 ? 'claim' : 'claims'} of this attestation, '
                  'and that it is yours.',
      ).muted.small,
      children: [
        AppButton(
          label: 'Decline',
          icon: AppIcons.x,
          style: AppButtonStyle.accent,
          onTap: busy ? null : _leave,
        ),
        AppButton(
          label: 'Show it',
          icon: AppIcons.send,
          busy: busy,
          onTap: busy || _credential == null ? null : _share,
        ),
      ],
    );
  }
}
