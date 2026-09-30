import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/passkey.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:url_launcher/url_launcher.dart';

/// The passkeys this account signs in with: which devices hold one, a way to
/// add another, and a way to remove one that is gone. The last one stays —
/// without it there is no way back in.
class PasskeysSection extends StatefulWidget {
  const PasskeysSection({super.key});

  @override
  State<PasskeysSection> createState() => _PasskeysSectionState();
}

class _PasskeysSectionState extends State<PasskeysSection>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => Stores.passkeys.load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A passkey is added in the browser; coming back is when it shows up.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) Stores.passkeys.load();
  }

  Future<void> _addHere() async {
    final link = await Stores.passkeys.addLink();
    if (!mounted) return;
    if (link == null ||
        !await launchUrl(link, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      AppToast.error(
        context,
        'Could not open the page',
        subtitle: Stores.passkeys.errorMessage,
      );
    }
  }

  Future<void> _copyLink() async {
    final link = await Stores.passkeys.addLink();
    if (!mounted) return;
    if (link == null) {
      AppToast.error(
        context,
        'Could not make a link',
        subtitle: Stores.passkeys.errorMessage,
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: link.toString()));
    if (!mounted) return;
    AppToast.success(
      context,
      'Link copied',
      subtitle: 'Open it on the other device within 15 minutes. It works once.',
    );
  }

  Future<void> _remove(Passkey passkey) async {
    final ok = await showAppDialog(
      context: context,
      title: 'Remove ${passkey.title}?',
      message:
          'It stops signing in to this account at once. The passkey itself '
          'stays on that device until you delete it there.',
      confirmLabel: 'Remove',
      confirmIcon: AppIcons.trash,
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (!await Stores.passkeys.remove(passkey.id) && mounted) {
      AppToast.error(
        context,
        'Could not remove it',
        subtitle: Stores.passkeys.errorMessage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.passkeys;
    return AppCard(
      child: Observer(
        builder: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (store.isLoading && store.passkeys.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(child: AppSpinner()),
              )
            else if (store.passkeys.isEmpty)
              Text(store.errorMessage ?? 'No passkeys found.').muted.small
            else
              for (final p in store.passkeys) ...[
                _row(p, only: store.passkeys.length == 1),
                const AppDivider(),
              ],
            AppSpacing.gapMd,
            const Text(
              'Add one on every device you use, so losing a device does not '
              'lock you out.',
            ).muted.small,
            AppSpacing.gapMd,
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppButton(
                  icon: AppIcons.plus,
                  label: 'Add on this device',
                  size: AppButtonSize.small,
                  onTap: _addHere,
                ),
                AppButton(
                  icon: AppIcons.copy,
                  label: 'Copy link for another device',
                  style: AppButtonStyle.accent,
                  size: AppButtonSize.small,
                  onTap: _copyLink,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(Passkey p, {required bool only}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          const Icon(AppIcons.key, size: 18),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.title),
                Text(
                  'Added ${_day(p.created)} · '
                  '${p.lastUsedAt == null ? 'not used yet' : 'last used ${_day(p.lastUsedAt)}'}',
                ).muted.small,
              ],
            ),
          ),
          // The only one cannot go: there would be no way back in.
          if (!only)
            AppButton(
              label: 'Remove',
              icon: AppIcons.trash,
              style: AppButtonStyle.destructive,
              size: AppButtonSize.small,
              onTap: () => _remove(p),
            ),
        ],
      ),
    );
  }
}

String _day(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.replaceFirst(' ', 'T'))?.toLocal();
  if (d == null) return '—';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
