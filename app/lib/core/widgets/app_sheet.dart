import 'dart:async';

import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/motion.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/state/sheet_tracker.dart';

/// Opens the app's one modal surface for a form or a list of choices: a
/// bottom sheet on a phone, a full-height panel on the trailing edge of a
/// wider window. Every create, edit and options flow goes through here, so
/// they all open in the same place at the same width.
///
/// A sheet closes only through its own buttons unless [dismissible]: a stray
/// click beside a half-filled form would throw the input away. Pass it for a
/// sheet that holds nothing to lose — a viewer, a menu, a pick-one list.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool dismissible = false,
}) {
  SheetTracker.opened();
  // A sheet leaves in one of two ways: popped, which completes its future, or
  // thrown away with the tabs' navigator when the app opens a full-screen page
  // such as a share link — which never completes it. Counting only the first
  // left the shell's floating buttons hidden until a restart. Either way now
  // releases the count, and only once.
  var released = false;
  void release() {
    if (released) return;
    released = true;
    SheetTracker.closed();
  }

  Widget content(BuildContext ctx) =>
      _SheetPresence(onGone: release, child: builder(ctx));

  final Future<T?> future;
  try {
    future = AppSpacing.isNarrow(context)
        ? _bottomSheet<T>(context, content, isScrollControlled, dismissible)
        : _sidePanel<T>(context, content, dismissible);
  } catch (_) {
    release();
    rethrow;
  }
  future.whenComplete(release);
  return future;
}

Future<T?> _bottomSheet<T>(
  BuildContext context,
  WidgetBuilder content,
  bool isScrollControlled,
  bool dismissible,
) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: dismissible,
    enableDrag: dismissible,
    showDragHandle: dismissible,
    useSafeArea: true,
    // A sheet is the same color as the page beneath it, so a heavy scrim is
    // what made the page look like a second, greyer background. Dim just
    // enough to read as modal and separate the sheet with its own outline.
    barrierColor: scheme.scrim.withValues(alpha: 0.2),
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (ctx) => Padding(
      // Keyboard on top of the gesture-nav inset: without the second term
      // a sheet's bottom row of buttons sits under the home indicator.
      padding: EdgeInsets.only(
        top: dismissible ? 0 : AppSpacing.xxl,
        bottom:
            MediaQuery.of(ctx).viewInsets.bottom +
            MediaQuery.of(ctx).viewPadding.bottom,
      ),
      child: content(ctx),
    ),
  );
}

/// Pushed on the nearest navigator, like the bottom sheet, so it is thrown
/// away with the tabs when a full-screen page opens instead of floating over
/// it.
Future<T?> _sidePanel<T>(
  BuildContext context,
  WidgetBuilder content,
  bool dismissible,
) {
  final scheme = Theme.of(context).colorScheme;
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: false,
    barrierDismissible: dismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: scheme.scrim.withValues(alpha: 0.2),
    transitionDuration: AppMotion.of(context),
    transitionBuilder: (ctx, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: AppMotion.curve),
      child: child,
    ),
    pageBuilder: (ctx, _, _) => Align(
      alignment: AlignmentDirectional.centerEnd,
      child: SizedBox(
        width: AppSpacing.panelWidth,
        height: double.infinity,
        child: Material(
          color: scheme.surface,
          shape: BorderDirectional(
            start: BorderSide(color: scheme.outlineVariant),
          ),
          child: SafeArea(
            left: false,
            child: Padding(
              padding: EdgeInsets.only(
                top: AppSpacing.xxl,
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              // Loose, like a bottom sheet's constraints: content sizes to
              // itself and scrolls only when it outgrows the panel.
              child: Align(alignment: Alignment.topCenter, child: content(ctx)),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Reports when the sheet's content leaves the tree, however it left.
class _SheetPresence extends StatefulWidget {
  final VoidCallback onGone;
  final Widget child;

  const _SheetPresence({required this.onGone, required this.child});

  @override
  State<_SheetPresence> createState() => _SheetPresenceState();
}

class _SheetPresenceState extends State<_SheetPresence> {
  @override
  void dispose() {
    // After the frame: the count is read by the shell's Observer, which must
    // not be marked dirty while the tree is being torn down.
    scheduleMicrotask(widget.onGone);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
