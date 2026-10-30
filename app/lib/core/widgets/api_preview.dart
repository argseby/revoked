import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/api/api_request_spec.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/motion.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/detail_gate.dart';

/// The Developer part of a create or edit form: its heading, the request and
/// what it takes to send it. Gated as a whole, so at Essentials the heading
/// never stands alone over nothing.
class ApiPreviewSection extends StatelessWidget {
  final ApiRequestSpec spec;
  final String title;

  const ApiPreviewSection({
    super.key,
    required this.spec,
    this.title = 'API request',
  });

  @override
  Widget build(BuildContext context) {
    return DetailGate(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppFormSectionHeader('Developer'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ApiPreview(spec: spec, title: title),
                Observer(
                  builder: (_) => Stores.apiKeys.apiKeys.isNotEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: const Text(
                            'You need an API key to send this yourself. '
                            'Create one in Settings → API keys.',
                          ).muted.small,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An expandable panel showing the exact API request equivalent to the action
/// being performed. The app is API-first, so create/update flows expose how to
/// reproduce them — method, URL, headers, body, and a copy-as-cURL.
///
/// Stateful so its expanded state survives parent rebuilds (the spec updates
/// live as the form changes, but the panel stays open if the user opened it).
class ApiPreview extends StatefulWidget {
  final ApiRequestSpec spec;
  final String title;

  const ApiPreview({super.key, required this.spec, this.title = 'API request'});

  @override
  State<ApiPreview> createState() => _ApiPreviewState();
}

class _ApiPreviewState extends State<ApiPreview> {
  final Local<bool> _expanded = Local(false);

  @override
  Widget build(BuildContext context) {
    // The raw request is for people who script against the API; at
    // Essentials it would only be noise beside the question being asked.
    return DetailGate(child: Observer(builder: (_) => _build(context)));
  }

  Widget _build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Stores.api.baseUrl;
    final spec = widget.spec;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _expanded.value = !_expanded.value,
            borderRadius: AppRadius.allLg,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Icon(AppIcons.server, size: 16, color: scheme.primary),
                  AppSpacing.gapMd,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title).small,
                        AppSpacing.gapXxs,
                        Text(
                          '${spec.method} ${spec.path}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ).mono.muted.small,
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded.value ? 0.5 : 0,
                    duration: AppMotion.of(context),
                    curve: AppMotion.curve,
                    child: Icon(
                      AppIcons.chevronDown,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded.value) ...[
            const AppDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxs,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: AppRadius.allMd,
                ),
                child: Text(spec.requestText(base)).mono.small.selectable,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs,
                0,
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AppButton(
                    label: 'Copy as cURL',
                    icon: AppIcons.copy,
                    style: AppButtonStyle.accent,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: spec.toCurl(base)));
                      AppToast.success(context, 'cURL copied to clipboard');
                    },
                  ),
                  if (spec.body != null)
                    AppButton(
                      label: 'Copy JSON',
                      icon: AppIcons.copy,
                      style: AppButtonStyle.accent,
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: spec.prettyBody()),
                        );
                        AppToast.success(context, 'JSON body copied');
                      },
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
