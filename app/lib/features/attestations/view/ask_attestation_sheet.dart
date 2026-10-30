import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/identity_picker.dart';
import 'package:revoked_app/core/widgets/qr_sheet.dart';

/// Asking makes a link for the attester: it fills in their Attest form with
/// the type, the claims and the identity, and they send back an offer.
Future<void> openAskAttestationSheet(BuildContext context) {
  final identities = Stores.identities;
  final usable = identities.identities.where(
    (i) => !i.isRevoked && identities.hasLocalKey(i.id),
  );
  final primary = identities.primaryIdentity;
  Stores.credentials.resetAsk(
    identityId: primary != null && usable.contains(primary)
        ? primary.id
        : usable.firstOrNull?.id,
  );
  return showAppSheet(context: context, builder: (_) => const _AskSheet());
}

class _AskSheet extends StatelessWidget {
  const _AskSheet();

  Future<void> _create(BuildContext context) async {
    final store = Stores.credentials;
    final identity = Stores.identities.byId(store.askIdentityId ?? '');
    final ask = identity == null ? null : store.ask(identity);
    if (ask == null) return;
    final navigator = Navigator.of(context);
    final root = navigator.context;
    navigator.pop();
    if (!root.mounted) return;
    await showQrSheet(
      context: root,
      title: 'Send this to whoever should attest',
      link: ask.link,
      message:
          'Opened in their Revoked app, it fills in their Attest form. They '
          'decide every value, and send you back an offer link: open it to '
          'accept the attestation with ${identity!.name}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.credentials;
    return Observer(
      builder: (_) {
        final problem = store.askProblem;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xxs,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Ask for an attestation').header,
                AppSpacing.gapXxs,
                const Text(
                  'Ask a club, an employer or anyone else to confirm '
                  'something about you. Nothing is sent from here: you get a '
                  'link to pass on.',
                ).muted.small,
                AppSpacing.gapLg,
                AppTextField(
                  controller: store.askTypeController,
                  label: 'What kind',
                  hint: 'e.g. membership',
                  mono: true,
                ),
                AppSpacing.gapSm,
                AppTextField(
                  controller: store.askClaimsController,
                  label: 'Claims you want stated (optional)',
                  hint: 'e.g. member_since, board',
                  mono: true,
                ),
                AppSpacing.gapLg,
                const Text('Issued to').small.bold.muted,
                AppSpacing.gapSm,
                IdentityPicker(
                  selectedId: store.askIdentityId,
                  onChanged: store.setAskIdentity,
                ),
                if (problem != null &&
                    store.askTypeController.text.trim().isNotEmpty) ...[
                  AppSpacing.gapSm,
                  AppErrorText(problem),
                ],
                AppSpacing.gapLg,
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Cancel',
                        style: AppButtonStyle.accent,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    AppSpacing.gapMd,
                    Expanded(
                      child: AppButton(
                        icon: AppIcons.qrCode,
                        label: 'Create ask link',
                        onTap: problem == null ? () => _create(context) : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
