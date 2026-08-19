import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/motion.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';

/// The unified list-item card shared by My Data, Share and Request so every
/// entity reads — and behaves — identically:
///
///   [icon]  Title                                       [⌄ expand]
///           key · date
///           [tag] [tag] …
///   ── expanded ──────────────────────────────────────────────
///           [optional body]
///           ( Action )( Action )( Destructive )
///
/// Tapping the card toggles the expanded panel, which reveals the optional
/// [body] (e.g. a vault record's value) and the [actions] as prominent rounded
/// pills — replacing the old per-card options sheet so taps do the same thing
/// everywhere.
class AppEntityCard extends StatefulWidget {
  final IconData icon;

  /// Sits before [icon] — a selection checkbox, nothing else so far.
  final Widget? leading;

  final String title;
  final String? subtitle;

  /// [subtitle] is a key, slug or fingerprint and reads as one.
  final bool subtitleMono;

  final String? date;
  final List<Widget> tags;

  /// Actions revealed when expanded, rendered as rounded pills. A [primary]
  /// action is tinted with the accent colour; [destructive] ones red.
  final List<AppSheetAction> actions;

  /// Detail shown whether or not the card is open (e.g. a record's value box).
  final Widget? body;

  /// Detail revealed only when the card is open, above the actions — a
  /// section's records, a template's blueprint.
  final Widget? expandedBody;

  const AppEntityCard({
    super.key,
    required this.icon,
    required this.title,
    this.leading,
    this.subtitle,
    this.subtitleMono = false,
    this.date,
    this.tags = const [],
    this.actions = const [],
    this.body,
    this.expandedBody,
  });

  /// Formats an ISO timestamp as `YYYY-MM-DD`, or null when absent/invalid —
  /// so every card shows the date the same way.
  static String? formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      final dt = DateTime.parse(iso).toLocal();
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      return '${dt.year}-$m-$d';
    } catch (_) {
      return null;
    }
  }

  @override
  State<AppEntityCard> createState() => _AppEntityCardState();
}

class _AppEntityCardState extends State<AppEntityCard> {
  static const double _leadIconSize = 18;
  static const double _bodyIndent = _leadIconSize + AppSpacing.md;

  bool _expanded = false;

  bool get _expandable =>
      widget.actions.isNotEmpty || widget.expandedBody != null;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = widget;
    final hasMeta =
        (w.subtitle != null && w.subtitle!.isNotEmpty) ||
        (w.date != null && w.date!.isNotEmpty);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      onTap: _expandable ? _toggle : null,
      child: AnimatedSize(
        duration: AppMotion.duration,
        curve: AppMotion.curve,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (w.leading != null) ...[w.leading!, AppSpacing.gapSm],
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    w.icon,
                    size: _leadIconSize,
                    color: scheme.primary,
                  ),
                ),
                AppSpacing.gapMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        w.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (hasMeta) ...[
                        AppSpacing.gapXxs,
                        Row(
                          children: [
                            if (w.subtitle != null && w.subtitle!.isNotEmpty)
                              Flexible(
                                child: w.subtitleMono
                                    ? Text(
                                        w.subtitle!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ).mono.muted.small
                                    : Text(
                                        w.subtitle!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ).muted.small,
                              ),
                            if (w.subtitle != null &&
                                w.subtitle!.isNotEmpty &&
                                w.date != null &&
                                w.date!.isNotEmpty)
                              const Text('  ·  ').muted.small,
                            if (w.date != null && w.date!.isNotEmpty)
                              Text(w.date!).muted.small,
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (_expandable) ...[
                  AppSpacing.gapSm,
                  _ExpandButton(expanded: _expanded, onTap: _toggle),
                ],
              ],
            ),
            if (w.body != null) ...[
              AppSpacing.gapMd,
              Padding(
                padding: const EdgeInsets.only(left: _bodyIndent),
                child: w.body!,
              ),
            ],
            if (w.tags.isNotEmpty) ...[
              // With a subtitle or a body above them the tags start a new
              // block; without one they are the card's only metadata, so they
              // sit where the subtitle would have — right under the title.
              (hasMeta || w.body != null)
                  ? AppSpacing.gapMd
                  : AppSpacing.gapXxs,
              Padding(
                padding: const EdgeInsets.only(left: _bodyIndent),
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: w.tags,
                ),
              ),
            ],
            if (_expanded) ...[
              AppSpacing.gapMd,
              const AppDivider(),
              AppSpacing.gapMd,
              if (w.expandedBody != null) ...[
                w.expandedBody!,
                if (w.actions.isNotEmpty) AppSpacing.gapMd,
              ],
              if (w.actions.isNotEmpty)
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [for (final a in w.actions) _ActionPill(action: a)],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The round, tinted expand/collapse affordance — makes it obvious the card
/// opens.
class _ExpandButton extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _ExpandButton({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.allPill,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(
          expanded ? AppIcons.chevronUp : AppIcons.chevronDown,
          size: 20,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// A prominent rounded action button used in the expanded card.
class _ActionPill extends StatelessWidget {
  final AppSheetAction action;

  const _ActionPill({required this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    if (action.destructive) {
      bg = scheme.errorContainer.withValues(alpha: 0.5);
      fg = scheme.error;
    } else if (action.primary) {
      bg = scheme.primaryContainer.withValues(alpha: 0.6);
      fg = scheme.onPrimaryContainer;
    } else {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurface;
    }
    final enabled = action.enabled;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: bg,
        borderRadius: AppRadius.allPill,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? action.onTap : null,
          borderRadius: AppRadius.allPill,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(action.icon, size: 16, color: fg),
                AppSpacing.gapXs,
                DefaultTextStyle.merge(
                  style: TextStyle(color: fg),
                  child: Text(action.label).small,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
