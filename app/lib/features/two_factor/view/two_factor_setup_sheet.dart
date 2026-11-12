import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_qr_code.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/two_factor/two_factor.dart';
import 'package:revoked_app/features/two_factor/view/two_factor_code_prompt.dart';

/// Sets up an authenticator app: the server makes a secret, shown here as a
/// QR code and as text, and a code from the app turns it on. Resolves true
/// once it is on.
Future<bool> showTwoFactorSetupSheet(BuildContext context) async {
  final done = await showAppSheet<bool>(
    context: context,
    builder: (_) => const _TwoFactorSetupSheet(),
  );
  return done ?? false;
}

class _TwoFactorSetupSheet extends StatefulWidget {
  const _TwoFactorSetupSheet();

  @override
  State<_TwoFactorSetupSheet> createState() => _TwoFactorSetupSheetState();
}

class _TwoFactorSetupSheetState extends State<_TwoFactorSetupSheet> {
  final _api = TwoFactorApi(Stores.api);
  final _setup = Local<TotpSetup?>(null);
  final _loadError = Local<String?>(null);
  final _codeError = Local<String?>(null);
  final _busy = Local(false);

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    _loadError.value = null;
    try {
      _setup.value = await _api.setup();
    } catch (e) {
      _loadError.value = describeTwoFactorError(e);
    }
  }

  Future<void> _confirm(String code) async {
    _busy.value = true;
    _codeError.value = null;
    try {
      await _api.confirm(code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _codeError.value = describeTwoFactorError(e);
    } finally {
      _busy.value = false;
    }
  }

  Future<void> _copy(String secret) async {
    await Clipboard.setData(ClipboardData(text: secret));
    if (!mounted) return;
    AppToast.success(context, 'Secret copied');
  }

  @override
  Widget build(BuildContext context) =>
      Observer(builder: (_) => _build(context));

  Widget _build(BuildContext context) {
    final setup = _setup.value;
    final loadError = _loadError.value;
    return SingleChildScrollView(
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
          const Text('Set up an authenticator app').header,
          AppSpacing.gapXxs,
          const Text(
            'The code is scanned with an authenticator app, or the secret is '
            'entered there by hand. Signing in then asks for the 6-digit code '
            'the app shows, after the passkey.',
          ).muted.small,
          AppSpacing.gapLg,
          if (loadError != null) ...[
            AppAlert(
              destructive: true,
              leading: const Icon(AppIcons.exclamation),
              title: const Text('Setup could not start'),
              content: Text(loadError),
            ),
            AppSpacing.gapLg,
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Close',
                    style: AppButtonStyle.accent,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                AppSpacing.gapMd,
                Expanded(
                  child: AppButton(
                    icon: AppIcons.arrowClockwise,
                    label: 'Try again',
                    onTap: _start,
                  ),
                ),
              ],
            ),
          ] else if (setup == null)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: AppSpinner()),
            )
          else ...[
            Center(child: AppQrCode(data: setup.otpauthUri)),
            AppSpacing.gapLg,
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    groupTotpSecret(setup.secret),
                    key: const ValueKey('two-factor-secret'),
                    style: const TextStyle(fontFamily: AppFont.mono),
                  ),
                ),
                AppButton(
                  icon: AppIcons.copy,
                  tooltip: 'Copy secret',
                  style: AppButtonStyle.ghost,
                  size: AppButtonSize.small,
                  onTap: () => _copy(setup.secret),
                ),
              ],
            ),
            AppSpacing.gapXl,
            TwoFactorCodePrompt(
              title: 'Code from the app',
              submitLabel: 'Turn on',
              busy: _busy.value,
              error: _codeError.value,
              onSubmit: _confirm,
              onCancel: () => Navigator.of(context).pop(false),
            ),
          ],
        ],
      ),
    );
  }
}
