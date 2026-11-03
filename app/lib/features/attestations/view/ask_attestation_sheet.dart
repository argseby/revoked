import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
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
      title: 'Link for the issuer',
      link: ask.link,
      message:
          'The issuer opens it in Revoked and fills in the details. The offer '
          'link they return is accepted with ${identity!.name}.',
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
                  'A club, an employer or another issuer confirms a fact '
                  'about an identity. The link is not sent automatically.',
                ).muted.small,
                AppSpacing.gapLg,
                AppFormField(
                  label: 'Kind',
                  inset: false,
                  child: AppTextField(
                    controller: store.askTypeController,
                    hint: 'membership',
                    mono: true,
                  ),
                ),
                AppSpacing.gapSm,
                AppFormField(
                  label: 'Details (optional)',
                  inset: false,
                  child: AppTextField(
                    controller: store.askClaimsController,
                    hint: 'member_since, board',
                    mono: true,
                  ),
                ),
                AppSpacing.gapLg,
                AppFormField(
                  label: 'Your identity',
                  inset: false,
                  child: IdentityPicker(
                    selectedId: store.askIdentityId,
                    onChanged: store.setAskIdentity,
                  ),
                ),
                if (problem != null &&
                    store.askTypeController.text.trim().isNotEmpty) ...[
                  AppSpacing.gapSm,
                  AppErrorText(problem),
                ],
                AppSpacing.gapLg,
                Row(
                  children: [
                    AppButton(
                      label: 'Cancel',
                      style: AppButtonStyle.accent,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    AppSpacing.gapMd,
                    Expanded(
                      child: AppButton(
                        icon: AppIcons.qrCode,
                        label: 'Create link',
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
