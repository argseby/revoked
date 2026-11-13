import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_composer.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/identity_picker.dart';
import 'package:revoked_app/core/widgets/qr_sheet.dart';
import 'package:revoked_app/features/vault/view/record_composer.dart';

/// Asking makes a link for the attester: it fills in their Attest form with
/// the type, the claims and the identity, and they send back an offer.
Future<void> openAskAttestationSheet(BuildContext context) {
  final identities = Stores.identities;
  Stores.credentials.resetAsk(identityId: identities.defaultSigner()?.id);
  return showAppSheet(
    context: context,
    panelWidth: vaultComposerWidth,
    builder: (_) => const _AskSheet(),
  );
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
          constraints: BoxConstraints(maxHeight: composerMaxHeight(context)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VaultComposerHeader(
                title: 'New attestation request',
                area: 'Attestations',
                areaIcon: AppIcons.attestation,
                subtitle:
                    'A club, an employer or another issuer confirms a fact '
                    'about an identity. The link is not sent automatically.',
                onClose: () => Navigator.of(context).pop(),
              ),
              const AppDivider(),
              Flexible(
                child: AppComposerSections(
                  sections: [
                    AppComposerSection(
                      title: 'Attestation',
                      icon: AppIcons.attestation,
                      children: [
                        AppComposerField(
                          label: 'Kind',
                          explanation: 'What the issuer is asked to confirm',
                          missing: store.askTypeController.text.trim().isEmpty,
                          child: AppTextField(
                            controller: store.askTypeController,
                            hint: 'membership',
                            mono: true,
                          ),
                        ),
                        AppComposerField(
                          label: 'Details (optional)',
                          explanation: 'Separated by commas',
                          error:
                              problem != null &&
                                  store.askTypeController.text.trim().isNotEmpty
                              ? problem
                              : null,
                          child: AppTextField(
                            controller: store.askClaimsController,
                            hint: 'member_since, board',
                            mono: true,
                          ),
                        ),
                      ],
                    ),
                    AppComposerSection(
                      title: 'Identity',
                      icon: AppIcons.shieldCheck,
                      children: [
                        AppComposerField(
                          label: 'Your identity',
                          missing: store.askIdentityId == null,
                          explanation:
                              'The offer the issuer returns is accepted with '
                              'this identity.',
                          child: IdentityPicker(
                            selectedId: store.askIdentityId,
                            onChanged: store.setAskIdentity,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const AppDivider(),
              AppComposerFooter(
                label: 'Create link',
                icon: AppIcons.plus,
                onSubmit: problem == null ? () => _create(context) : null,
                onCancel: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
  }
}
