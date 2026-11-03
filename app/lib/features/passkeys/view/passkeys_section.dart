import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/utils/dates.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/models/passkey.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
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
        'The page could not be opened',
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
        'The link could not be created',
        subtitle: Stores.passkeys.errorMessage,
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: link.toString()));
    if (!mounted) return;
    AppToast.success(
      context,
      'Link copied',
      subtitle: 'Valid for one use within 15 minutes.',
    );
  }

  Future<void> _remove(Passkey passkey) async {
    final ok = await showAppDialog(
      context: context,
      title: 'Remove ${passkey.title}?',
      message:
          'The passkey can no longer be used to sign in. It remains on the '
          'device until deleted there.',
      confirmLabel: 'Remove',
      confirmIcon: AppIcons.trash,
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (!await Stores.passkeys.remove(passkey.id)) {
      if (!mounted) return;
      AppToast.error(
        context,
        'The passkey could not be removed',
        subtitle: Stores.passkeys.errorMessage,
      );
      return;
    }
    // Its place on the device list goes with it, where this device may sign
    // that. The server can't: only a key holder can take a key holder off.
    if (passkey.credentialId.isEmpty) return;
    await Stores.keys.ensureLoaded();
    if (Stores.keys.chain.livePasskey(passkey.credentialId) == null) return;
    final gone = await Stores.keys.removePasskeyEntry(passkey.credentialId);
    if (!gone && mounted) {
      AppToast.error(
        context,
        'The passkey still holds the encryption key',
        subtitle: 'It can be removed under End-to-end encryption.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.passkeys;
    return Observer(
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppListGroup(
            title: 'Passkeys',
            footer: const Text(
              'Passkeys allow sign-in without a password. A passkey on each '
              'device prevents lockout when one is lost.',
            ),
            children: [
              if (store.isLoading && store.passkeys.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: AppListSkeleton(embedded: true),
                )
              else if (store.passkeys.isEmpty)
                AppDetailRow(
                  icon: AppIcons.info,
                  label: store.errorMessage ?? 'No passkeys',
                )
              else
                for (final p in store.passkeys)
                  _row(p, only: store.passkeys.length == 1),
            ],
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppButton(
                icon: AppIcons.plus,
                label: 'Add on this device',
                onTap: _addHere,
              ),
              AppButton(
                icon: AppIcons.copy,
                label: 'Copy link for another device',
                style: AppButtonStyle.accent,
                onTap: _copyLink,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(Passkey p, {required bool only}) {
    return AppListRow(
      icon: AppIcons.key,
      title: p.title,
      subtitle:
          'Added ${_day(p.created)} · '
          '${p.lastUsedAt == null ? 'never used' : 'last used ${_day(p.lastUsedAt)}'}',
      onTap: () => showAppOptionsSheet(
        context: context,
        title: p.title,
        actions: [
          AppSheetAction(
            icon: AppIcons.trash,
            label: only ? 'Remove (requires another passkey)' : 'Remove',
            destructive: true,
            // The only one cannot go: there would be no way back in.
            enabled: !only,
            onTap: () => _remove(p),
          ),
        ],
      ),
    );
  }
}

String _day(String? iso) => dayOf(iso) ?? '—';
