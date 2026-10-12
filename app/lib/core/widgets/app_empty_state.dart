import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:url_launcher/url_launcher.dart';

/// One step of how a feature works, shown on its empty screen.
class AppEmptyStep {
  final String title;
  final String detail;

  const AppEmptyStep(this.title, this.detail);
}

/// What a screen shows while it has nothing to list.
///
/// With only [icon], [title] and [subtitle] it is the short, centered notice
/// used for "not found" pages. A first-run screen also passes [steps], an
/// [example] and actions: someone who has never used the feature learns what
/// it is for, sees what an entry looks like, and can start from right here
/// instead of hunting for the + button.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  final Widget? secondaryAction;

  /// A sample entry, drawn with a dashed outline so it never passes for data.
  final AppEmptyExample? example;

  /// How the feature works, in order. Three short steps read best.
  final List<AppEmptyStep> steps;

  /// Something that has to happen elsewhere first, such as an empty vault on
  /// the Links screen.
  final String? notice;

  /// The docs page that explains the feature, opened in the browser.
  final String? learnMoreLabel;
  final String? learnMoreUrl;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.secondaryAction,
    this.example,
    this.steps = const [],
    this.notice,
    this.learnMoreLabel,
    this.learnMoreUrl,
  }) : assert(
         (learnMoreLabel == null) == (learnMoreUrl == null),
         'a docs link needs both its label and its url',
       );

  bool get _explains => steps.isNotEmpty || example != null || notice != null;

  @override
  Widget build(BuildContext context) {
    return _explains ? _explainer(context) : _notice(context);
  }

  Widget _notice(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            AppSpacing.gapMd,
            Text(title),
            AppSpacing.gapXxs,
            Text(subtitle, textAlign: .center).muted.small,
            if (action != null || secondaryAction != null) ...[
              AppSpacing.gapLg,
              _actions(alignment: WrapAlignment.center),
            ],
            if (learnMoreUrl != null) ...[
              AppSpacing.gapSm,
              _learnMore(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _explainer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenH(context),
          AppSpacing.xxl,
          AppSpacing.screenH(context),
          // Clears the shell's floating buttons, like a list page does.
          AppSpacing.gigantic * 3,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - AppSpacing.gigantic * 4).clamp(
              0,
              double.infinity,
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: AppRadius.allPill,
                    ),
                    child: Icon(
                      icon,
                      size: 24,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  AppSpacing.gapLg,
                  Text(title).header,
                  AppSpacing.gapXs,
                  Text(subtitle).muted,
                  if (example != null) ...[AppSpacing.gapXl, example!],
                  if (steps.isNotEmpty) AppSpacing.gapXl,
                  for (final (i, step) in steps.indexed) ...[
                    if (i > 0) AppSpacing.gapMd,
                    _StepRow(number: i + 1, step: step),
                  ],
                  if (notice != null) ...[
                    AppSpacing.gapXl,
                    AppAlert(
                      leading: const Icon(AppIcons.info),
                      content: Text(notice!).small,
                    ),
                  ],
                  if (action != null || secondaryAction != null) ...[
                    AppSpacing.gapXl,
                    _actions(alignment: WrapAlignment.start),
                  ],
                  if (learnMoreUrl != null) ...[
                    AppSpacing.gapSm,
                    _learnMore(context),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions({required WrapAlignment alignment}) {
    return Wrap(
      alignment: alignment,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [?action, ?secondaryAction],
    );
  }

  Widget _learnMore(BuildContext context) {
    return AppButton(
      icon: AppIcons.boxArrowUpRight,
      label: learnMoreLabel!,
      style: AppButtonStyle.ghost,
      size: AppButtonSize.small,
      onTap: () async {
        final ok = await launchUrl(
          Uri.parse(learnMoreUrl!),
          mode: LaunchMode.externalApplication,
        );
        if (!ok && context.mounted) {
          AppToast.error(context, 'Could not open $learnMoreUrl');
        }
      },
    );
  }
}

class _StepRow extends StatelessWidget {
  final int number;
  final AppEmptyStep step;

  const _StepRow({required this.number, required this.step});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppRadius.allPill,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text('$number').muted.small,
        ),
        AppSpacing.gapMd,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(step.title, bold: true),
              Text(step.detail).muted.small,
            ],
          ),
        ),
      ],
    );
  }
}

/// A made-up entry on an empty screen: what the list will hold once it is
/// used. The dashed outline and muted text keep it from reading as real data.
class AppEmptyExample extends StatelessWidget {
  final String title;
  final String? detail;
  final String? badge;

  const AppEmptyExample({
    super.key,
    required this.title,
    this.detail,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Example',
      child: CustomPaint(
        painter: _DashedOutline(color: scheme.outline),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: title,
                        style: TextStyle(color: scheme.onSurface),
                      ),
                      if (detail != null) TextSpan(text: '  ·  $detail'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (badge != null) ...[
                AppSpacing.gapSm,
                AppBadge(label: badge!, variant: AppBadgeVariant.outline),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedOutline extends CustomPainter {
  final Color color;

  const _DashedOutline({required this.color});

  static const double _dash = 5;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path()
      ..addRRect(AppRadius.allMd.toRRect(Offset.zero & size).deflate(0.5));
    for (final PathMetric metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += _dash + _gap) {
        canvas.drawPath(metric.extractPath(d, d + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline old) => old.color != color;
}
