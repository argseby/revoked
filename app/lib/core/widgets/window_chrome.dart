import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart' show when;
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';

/// The window's own minimize / maximize / close buttons, drawn as ordinary
/// [AppButton]s so they sit in the same row as a screen's actions instead of
/// costing a second bar above them.
class WindowControls extends StatelessWidget {
  const WindowControls({super.key});

  /// Width the rule and the three buttons take, so a top bar can keep that
  /// much of its trailing edge clear for the layer they are drawn in.
  static const double extent =
      AppSpacing.sm * 2 + 1 + 3 * AppButton.normalExtent + 2 * AppSpacing.xxs;

  @override
  Widget build(BuildContext context) {
    final window = Stores.window;
    final theme = Theme.of(context);
    return Observer(
      builder: (context) {
        final maximized = window.isMaximized;
        return Theme(
          // Closing a window is not an accent action. These keep the accent
          // shape, so they are plainly the same button as the bar's own, but
          // wear the sunken fill rather than the tint — which otherwise draws
          // the eye harder than anything a screen actually does.
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              secondaryContainer: theme.colorScheme.surfaceContainerHighest,
              onSecondaryContainer: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The window's buttons are not the screen's, so they are fenced
              // off from the actions they share the bar with.
              AppSpacing.gapSm,
              const SizedBox(
                height: AppSpacing.xxl,
                child: AppDivider(vertical: true),
              ),
              AppSpacing.gapSm,
              AppButton(
                icon: AppIcons.dash,
                style: AppButtonStyle.accent,
                tooltip: 'Minimize',
                onTap: window.minimize,
              ),
              AppSpacing.gapXxs,
              AppButton(
                icon: maximized ? AppIcons.windowStack : AppIcons.window,
                style: AppButtonStyle.accent,
                tooltip: maximized ? 'Restore' : 'Maximize',
                onTap: window.toggleMaximize,
              ),
              AppSpacing.gapXxs,
              AppButton(
                icon: AppIcons.x,
                style: AppButtonStyle.accent,
                tooltip: 'Close',
                onTap: window.close,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The trailing gap a top bar leaves for [WindowControls], so the bar's own
/// actions end where the window buttons begin.
class WindowControlsGap extends StatelessWidget {
  const WindowControlsGap({super.key});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) => SizedBox(
        width: Stores.window.ownsTitleBar
            ? WindowControls.extent + AppSpacing.xs
            : AppSpacing.xs,
      ),
    );
  }
}

/// Puts the window's title bar — a drag strip along the top edge, with the
/// buttons at its right — into the app's root overlay, the same one the toasts
/// use.
///
/// It goes there rather than into a second [Overlay] above the navigator
/// because nesting one there tripped the framework's semantics assertions on
/// every resize, and a [Tooltip] has to have an overlay to render into. An
/// entry inserted by hand stays above later routes: the navigator inserts a
/// route relative to the route below it, never at the very top.
abstract final class WindowTitleBar {
  static OverlayEntry? _entry;

  /// Called once at startup. The window answers asynchronously, so this waits
  /// for the answer rather than reading it now.
  static void attach() {
    when((_) => Stores.window.ownsTitleBar, () {
      WidgetsBinding.instance.addPostFrameCallback((_) => _insert());
    });
  }

  static void _insert() {
    if (_entry != null) return;
    final overlay = AppRouter.rootNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    final window = Stores.window;
    final entry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: Stack(
          children: [
            // Translucent, and raw pointer events rather than gestures: it
            // never joins the arena, so everything under it — the bar's own
            // buttons included — still gets every tap. Only a press that
            // travels becomes a window drag.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: kToolbarHeight,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) => window.pressed(event.position),
                onPointerMove: (event) => window.moved(event.position),
                onPointerUp: (_) => window.released(),
                onPointerCancel: (_) => window.released(),
              ),
            ),
            Positioned(
              top: (kToolbarHeight - AppButton.normalExtent) / 2,
              right: AppSpacing.xs,
              child: const WindowControls(),
            ),
          ],
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}
