import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/dates.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/two_factor/two_factor.dart';
import 'package:revoked_app/features/two_factor/view/two_factor_code_prompt.dart';
import 'package:revoked_app/features/two_factor/view/two_factor_setup_sheet.dart';

/// The authenticator app this account signs in with after its passkey:
/// whether it is on, a way to set one up, and a way to turn it off — unless
/// the server requires it.
class TwoFactorSection extends StatefulWidget {
  const TwoFactorSection({super.key});

  @override
  State<TwoFactorSection> createState() => _TwoFactorSectionState();
}

class _TwoFactorSectionState extends State<TwoFactorSection> {
  final _api = TwoFactorApi(Stores.api);
  final _status = Local<TwoFactorStatus?>(null);
  final _error = Local<String?>(null);
  final _loading = Local(true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _loading.value = true;
    try {
      _status.value = await _api.status();
      _error.value = null;
    } catch (e) {
      _error.value = describeTwoFactorError(e);
    } finally {
      _loading.value = false;
    }
  }

  Future<void> _setUp() async {
    final on = await showTwoFactorSetupSheet(context);
    if (!mounted || !on) return;
    Stores.auth.markTwoFactorSetUp();
    AppToast.success(context, 'Two-factor authentication is on');
    await _load();
  }

  Future<void> _turnOff() async {
    final off = await showAppSheet<bool>(
      context: context,
      builder: (_) => const _TurnOffSheet(),
    );
    if (!mounted || off != true) return;
    AppToast.success(context, 'Two-factor authentication is off');
    await _load();
  }

  @override
  Widget build(BuildContext context) => Observer(builder: (_) => _build());

  Widget _build() {
    final status = _status.value;
    final enabled = status?.enabled ?? false;
    final required = status?.required ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppListGroup(
          title: 'Two-factor authentication',
          footer: Text(
            required
                ? 'This server requires a code from an authenticator app '
                      'after the passkey, so it cannot be turned off. A lost '
                      'authenticator is reset by the operator.'
                : 'With an authenticator app, signing in asks for its '
                      '6-digit code after the passkey.',
          ),
          children: [
            if (_loading.value && status == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: AppListSkeleton(embedded: true),
              )
            else if (status == null)
              AppDetailRow(
                icon: AppIcons.info,
                label: _error.value ?? 'Status unavailable',
                onTap: _load,
              )
            else
              AppDetailRow(
                icon: enabled ? AppIcons.shieldCheck : AppIcons.safe,
                label: enabled ? 'Authenticator app' : 'Off',
                value: enabled
                    ? 'On since ${dayOf(status.enabledAt?.toIso8601String()) ?? '—'}'
                    : required
                    ? 'Required by this server'
                    : '',
              ),
          ],
        ),
        if (status != null)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (!enabled)
                AppButton(
                  key: const ValueKey('two-factor-set-up'),
                  icon: AppIcons.shieldLock,
                  label: 'Set up',
                  style: AppButtonStyle.accent,
                  onTap: _setUp,
                )
              else if (!required)
                AppButton(
                  key: const ValueKey('two-factor-turn-off'),
                  icon: AppIcons.shieldSlash,
                  label: 'Turn off',
                  style: AppButtonStyle.accent,
                  onTap: _turnOff,
                ),
            ],
          ),
      ],
    );
  }
}

/// Turning it off takes a current code: a session alone is not enough.
class _TurnOffSheet extends StatefulWidget {
  const _TurnOffSheet();

  @override
  State<_TurnOffSheet> createState() => _TurnOffSheetState();
}

class _TurnOffSheetState extends State<_TurnOffSheet> {
  final _busy = Local(false);
  final _error = Local<String?>(null);

  Future<void> _submit(String code) async {
    _busy.value = true;
    _error.value = null;
    try {
      await TwoFactorApi(Stores.api).disable(code);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _error.value = describeTwoFactorError(e);
    } finally {
      _busy.value = false;
    }
  }

  @override
  Widget build(BuildContext context) => Observer(builder: (_) => _build());

  Widget _build() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxs,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: TwoFactorCodePrompt(
        title: 'Turn off two-factor authentication',
        body:
            'The current code of the authenticator app confirms it. Signing '
            'in then takes the passkey alone.',
        submitLabel: 'Turn off',
        submitIcon: AppIcons.shieldSlash,
        busy: _busy.value,
        error: _error.value,
        onSubmit: _submit,
        onCancel: () => Navigator.of(context).pop(false),
      ),
    );
  }
}
