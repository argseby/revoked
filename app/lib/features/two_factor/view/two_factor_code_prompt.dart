import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/features/two_factor/two_factor.dart';

/// Asks for the current code of the authenticator app: one field, and a
/// button that is ready once six digits are in. [onSubmit] gets the code as
/// the server takes it; [error] is what went wrong with the last one.
class TwoFactorCodePrompt extends StatefulWidget {
  final String title;
  final String? body;
  final String submitLabel;
  final IconData submitIcon;
  final bool busy;
  final String? error;
  final ValueChanged<String> onSubmit;
  final VoidCallback? onCancel;

  const TwoFactorCodePrompt({
    super.key,
    this.title = 'Authenticator code',
    this.body,
    this.submitLabel = 'Continue',
    this.submitIcon = AppIcons.check,
    this.busy = false,
    this.error,
    required this.onSubmit,
    this.onCancel,
  });

  @override
  State<TwoFactorCodePrompt> createState() => _TwoFactorCodePromptState();
}

class _TwoFactorCodePromptState extends State<TwoFactorCodePrompt> {
  // Observable, so the button follows what is typed.
  final _controller = ObservableTextController();

  @override
  void didUpdateWidget(TwoFactorCodePrompt old) {
    super.didUpdateWidget(old);
    // A refused code is cleared, so the next one is typed into an empty
    // field.
    if (widget.error != null && widget.error != old.error) _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _code => normalizeTotpCode(_controller.text);

  void _submit() {
    final code = _code;
    if (code == null || widget.busy) return;
    widget.onSubmit(code);
  }

  @override
  Widget build(BuildContext context) => Observer(builder: (_) => _build());

  Widget _build() {
    final ready = _code != null && !widget.busy;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(widget.title).header),
        if (widget.body != null) ...[
          AppSpacing.gapXxs,
          Text(widget.body!).muted.small,
        ],
        AppSpacing.gapLg,
        AppTextField(
          key: const ValueKey('two-factor-code'),
          controller: _controller,
          hint: '123456',
          mono: true,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: const [TotpCodeFormatter()],
          onSubmitted: (_) => _submit(),
        ),
        if (widget.error != null) ...[
          AppSpacing.gapMd,
          AppAlert(
            destructive: true,
            leading: const Icon(AppIcons.exclamation),
            content: Text(widget.error!),
          ),
        ],
        AppSpacing.gapLg,
        Row(
          children: [
            if (widget.onCancel != null) ...[
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  style: AppButtonStyle.accent,
                  onTap: widget.busy ? null : widget.onCancel,
                ),
              ),
              AppSpacing.gapMd,
            ],
            Expanded(
              child: AppButton(
                key: const ValueKey('two-factor-submit'),
                icon: widget.submitIcon,
                label: widget.submitLabel,
                busy: widget.busy,
                onTap: ready ? _submit : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
