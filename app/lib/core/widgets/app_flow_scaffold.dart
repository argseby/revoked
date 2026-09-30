import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/window_chrome.dart';

/// The frame of every full-screen page outside the tabs — a link someone sent,
/// a tool asking to connect, a proposed share:
///
///   [← Back]  Title                                   [actions]
///             Link proposal · expires 15 Oct
///   ─────────────────────────────────────────────────────────────
///   body (an `AppPageBody` of groups)
///   ─────────────────────────────────────────────────────────────
///                                       ( Decline ) ( Connect )
///
/// The page's name and status live in the top bar, not again in the body, so
/// the body starts with what the page is about. The decision sits in a bar
/// pinned to the bottom, so it is in the same place on every one of these
/// pages and never scrolls out of reach.
class AppFlowScaffold extends StatelessWidget {
  final String title;

  /// One line under the title: what kind of page this is and its state.
  final String? subtitle;

  final Widget body;

  /// The way out, top left.
  final VoidCallback onClose;
  final String closeLabel;

  /// Trailing top-bar controls, such as a bookmark button.
  final List<Widget> actions;

  /// The page's decision, pinned to the bottom. Usually an [AppActionBar].
  final Widget? bottomBar;

  const AppFlowScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    required this.onClose,
    this.closeLabel = 'Back',
    this.actions = const [],
    this.bottomBar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: AppSpacing.screenH(context),
        title: Row(
          children: [
            AppButton(
              icon: AppIcons.arrowLeft,
              tooltip: closeLabel,
              style: AppButtonStyle.accent,
              onTap: onClose,
            ),
            AppSpacing.gapMd,
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).header,
                  if (subtitle != null && subtitle!.isNotEmpty)
                    AppText(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).small.muted,
                ],
              ),
            ),
          ],
        ),
        actions: [
          for (final a in actions) ...[a, AppSpacing.gapSm],
          const WindowControlsGap(),
          SizedBox(width: AppSpacing.screenH(context) - AppSpacing.sm),
        ],
      ),
      body: body,
      bottomNavigationBar: bottomBar,
    );
  }
}

/// The decision at the foot of a flow page: the way out on the left of the
/// pair, the main action on the right. On a phone the buttons share the
/// width; on a wider window they keep their size at the right edge.
class AppActionBar extends StatelessWidget {
  final List<Widget> children;

  /// A line above the buttons — what pressing them will do.
  final Widget? note;

  const AppActionBar({super.key, required this.children, this.note});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final narrow = AppSpacing.isNarrow(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenH(context),
            AppSpacing.md,
            AppSpacing.screenH(context),
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (note != null) ...[note!, AppSpacing.gapSm],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) AppSpacing.gapSm,
                    narrow ? Expanded(child: children[i]) : children[i],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A page that has one thing to say — done, broken, or signed out — centred,
/// with the next step under it.
class AppStatusMessage extends StatelessWidget {
  final IconData icon;

  /// Tints the icon tile: success, a warning, an error.
  final Color? accent;
  final String title;
  final String message;
  final List<Widget> actions;

  const AppStatusMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.accent,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.screenH(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: AppRadius.allLg,
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            AppSpacing.gapLg,
            AppText(title, textAlign: TextAlign.center).header,
            AppSpacing.gapSm,
            AppText(message, textAlign: TextAlign.center).muted,
            if (actions.isNotEmpty) ...[
              AppSpacing.gapXl,
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
