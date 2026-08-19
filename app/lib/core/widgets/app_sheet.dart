import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';

/// Opens a modal bottom sheet. Replaces shadcn's
/// `openSheet(context:, position: OverlayPosition.bottom, builder:)`.
/// Scrollable, with a drag handle, and lifted above the keyboard.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: true,
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
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: builder(ctx),
    ),
  );
}
