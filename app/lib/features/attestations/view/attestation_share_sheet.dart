import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/attestation_share.dart';
import 'package:revoked_app/core/models/credential.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/qr_sheet.dart';
import 'package:revoked_app/features/attestations/claim_text.dart';

/// Opens the form that makes a link for [credential], and once it is made,
/// shows the link to pass on. [context] stays mounted after the form closes.
Future<void> openAttestationShareSheet(
  BuildContext context,
  Credential credential,
) async {
  final made = await showAppSheet<NewAttestationShare>(
    context: context,
    dismissible: true,
    builder: (_) => _ShareForm(credential: credential),
  );
  if (made == null || !context.mounted) return;
  await showQrSheet(
    context: context,
    title: 'Link created',
    link: made.url,
    message:
        'Whoever opens it sees this attestation with the details picked, '
        'until ${dayText(made.expiresAt?.toIso8601String())}. It is shown '
        'once: it cannot be copied again later.',
    dismissible: false,
  );
}

class _ShareForm extends StatefulWidget {
  final Credential credential;

  const _ShareForm({required this.credential});

  @override
  State<_ShareForm> createState() => _ShareFormState();
}

class _ShareFormState extends State<_ShareForm> {
  /// Every detail starts picked: whoever is sent the link is meant to see
  /// the attestation. Any can be left out.
  late final _disclose = Local<Set<String>>({
    for (final d in widget.credential.disclosures) d.name,
  });
  final _days = Local<int>(7);

  static const _durations = [(1, '1 day'), (7, '7 days'), (30, '30 days')];

  Future<void> _create() async {
    final made = await Stores.credentials.share(
      credential: widget.credential,
      disclose: _disclose.value,
      days: _days.value,
    );
    if (made != null && mounted) Navigator.of(context).pop(made);
  }

  void _toggle(String name, bool on) {
    final next = {..._disclose.value};
    on ? next.add(name) : next.remove(name);
    _disclose.value = next;
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.credentials;
    final claims = widget.credential.disclosures;
    return Observer(
      builder: (_) => ConstrainedBox(
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
              const Text('Share link').header,
              AppSpacing.gapXxs,
              Text(
                'Shows ${widget.credential.type} from '
                '${widget.credential.issuer} to whoever opens the link. The '
                'issuer, the kind and the identity are always shown.',
              ).muted.small,
              AppSpacing.gapLg,
              const Text('Details'),
              AppSpacing.gapSm,
              if (claims.isEmpty)
                const Text(
                  'This attestation has no details beyond its kind.',
                ).muted.small,
              for (final d in claims)
                AppCheckRow(
                  label: d.name,
                  subtitle: claimText(d.value),
                  value: _disclose.value.contains(d.name),
                  onChanged: (on) => _toggle(d.name, on),
                ),
              AppSpacing.gapLg,
              const Text('Open for'),
              AppSpacing.gapSm,
              Align(
                alignment: Alignment.centerLeft,
                child: AppSegmented<int>(
                  value: _days.value,
                  items: [
                    for (final (days, label) in _durations)
                      AppSegmentedItem(value: days, label: label),
                  ],
                  onChanged: (days) => _days.value = days,
                ),
              ),
              if (store.shareError != null) ...[
                AppSpacing.gapLg,
                AppAlert(
                  destructive: true,
                  title: const Text('The link could not be created'),
                  content: Text(store.shareError!).small,
                ),
              ],
              AppSpacing.gapXl,
              AppButton(
                icon: AppIcons.link,
                label: 'Create link',
                busy: store.isSharing,
                onTap: store.isSharing ? null : _create,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The open links of one held attestation, each with a way to end it.
class AttestationShareList extends StatelessWidget {
  final Credential credential;

  const AttestationShareList({super.key, required this.credential});

  Future<void> _end(BuildContext context, AttestationShare link) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'End this link?',
      message: 'Whoever opens it afterwards sees nothing.',
      confirmLabel: 'End link',
      confirmIcon: AppIcons.xCircle,
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await Stores.credentials.revokeShare(link);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'Link ended');
    } else {
      AppToast.error(
        context,
        'The link could not be ended',
        subtitle: Stores.credentials.shareError,
      );
    }
  }

  String _summary(AttestationShare link) {
    final opened = switch (link.viewCount) {
      0 => 'Not opened yet',
      1 => 'Opened once',
      final n => 'Opened $n times',
    };
    final what = link.disclosed.isEmpty
        ? 'no details'
        : link.disclosed.join(', ');
    return '$opened · until ${dayText(link.expiresAt?.toIso8601String())}'
        ' · $what';
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final open = [
          for (final l
              in Stores.credentials.shares[credential.id] ??
                  const <AttestationShare>[])
            if (l.isOpen) l,
        ];
        if (open.isEmpty) {
          return const AppListCard(
            children: [
              AppDetailRow(icon: AppIcons.link, label: 'No open links.'),
            ],
          );
        }
        return AppListCard(
          children: [
            for (final link in open)
              AppListRow(
                icon: AppIcons.link,
                title: 'Link from ${dayText(link.created?.toIso8601String())}',
                subtitle: _summary(link),
                trailing: AppButton(
                  icon: AppIcons.x,
                  tooltip: 'End link',
                  style: AppButtonStyle.ghost,
                  size: AppButtonSize.small,
                  onTap: () => _end(context, link),
                ),
              ),
          ],
        );
      },
    );
  }
}
