import 'package:material_ui/material_ui.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';

/// Shown in place of a list that failed to load. Sits at the top of the empty
/// space, where the content would have started — a failure centred in the
/// viewport reads as a state of the whole app rather than of this list. Filling
/// a screen it keeps the screen's edges and scrolls when the window is too
/// short for it; inside a scrolling page, which has its own, it only keeps
/// clear of what is above and below it.
class AppLoadError extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const AppLoadError({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final side = bounded ? AppSpacing.screenH(context) : 0.0;
        final body = Padding(
          padding: EdgeInsets.fromLTRB(
            side,
            AppSpacing.lg,
            side,
            AppSpacing.lg,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppAlert(
                  destructive: true,
                  leading: const Icon(AppIcons.exclamation),
                  title: Text(title),
                  content: Text(message),
                ),
                if (onRetry != null) ...[
                  AppSpacing.gapMd,
                  AppButton(
                    icon: AppIcons.arrowClockwise,
                    label: 'Retry',
                    style: AppButtonStyle.accent,
                    onTap: onRetry,
                  ),
                ],
              ],
            ),
          ),
        );
        return bounded ? SingleChildScrollView(child: body) : body;
      },
    );
  }
}

/// Above a list whose refresh failed: the list stays, because what you last saw
/// is more use than an error in its place.
class AppRefreshFailed extends StatelessWidget {
  final VoidCallback onRetry;

  const AppRefreshFailed({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AppListBanner(
      icon: AppIcons.exclamation,
      message: 'Refresh failed. Showing the last loaded data.',
      action: AppButton(
        icon: AppIcons.arrowClockwise,
        label: 'Retry',
        style: AppButtonStyle.accent,
        size: AppButtonSize.small,
        onTap: onRetry,
      ),
    );
  }
}
