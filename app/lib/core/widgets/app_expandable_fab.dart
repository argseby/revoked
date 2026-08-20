import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/motion.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_button.dart';

/// One entry an [AppExpandableFab] fans out into.
class AppFabAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const AppFabAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// A floating action button that expands in place into labelled actions —
/// used when a tab's "create" is a choice rather than a single flow.
///
/// Whether it is open is purely visual state, so it lives in a [Local] on the
/// widget itself; choosing an action or swapping tabs (which replaces the
/// widget) collapses it.
class AppExpandableFab extends StatefulWidget {
  final String tooltip;
  final List<AppFabAction> actions;

  const AppExpandableFab({
    super.key,
    required this.tooltip,
    required this.actions,
  });

  @override
  State<AppExpandableFab> createState() => _AppExpandableFabState();
}

class _AppExpandableFabState extends State<AppExpandableFab> {
  final Local<bool> _open = Local(false);

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final open = _open.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Invisible options stay in the tree so the fade runs both ways;
            // IgnorePointer keeps them from swallowing taps meant for the
            // content underneath.
            IgnorePointer(
              ignoring: !open,
              child: AnimatedOpacity(
                opacity: open ? 1 : 0,
                duration: AppMotion.duration,
                curve: AppMotion.curve,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final action in widget.actions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AppButton(
                          icon: action.icon,
                          label: action.label,
                          style: AppButtonStyle.accent,
                          size: AppButtonSize.small,
                          onTap: () {
                            _open.value = false;
                            action.onTap();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            FloatingActionButton(
              tooltip: widget.tooltip,
              onPressed: () => _open.value = !open,
              child: Icon(open ? AppIcons.x : AppIcons.plus),
            ),
          ],
        );
      },
    );
  }
}
