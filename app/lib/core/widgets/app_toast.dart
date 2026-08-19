import 'dart:async';

import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/motion.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// Lightweight toast notifications shown at the TOP of the screen via an
/// [Overlay] (so they don't cover bottom content / nav). Auto-dismiss after a
/// few seconds; tap to dismiss early. Replaces the old bottom SnackBar.
class AppToast {
  static OverlayEntry? _entry;

  static void success(
    BuildContext context,
    String message, {
    String? subtitle,
  }) {
    _show(
      context,
      message,
      subtitle: subtitle,
      icon: AppIcons.checkCircle,
      iconColor: Theme.of(context).colorScheme.inversePrimary,
    );
  }

  static void error(BuildContext context, String message, {String? subtitle}) {
    _show(
      context,
      message,
      subtitle: subtitle,
      icon: AppIcons.xCircle,
      iconColor: Theme.of(context).colorScheme.inverseError,
    );
  }

  static void _show(
    BuildContext context,
    String message, {
    String? subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _entry?.remove();
    _entry = null;

    final scheme = Theme.of(context).colorScheme;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        message: message,
        subtitle: subtitle,
        icon: icon,
        iconColor: iconColor,
        scheme: scheme,
        onClosed: () {
          if (_entry == entry) _entry = null;
          entry.remove();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final ColorScheme scheme;
  final VoidCallback onClosed;

  const _ToastWidget({
    required this.message,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.scheme,
    required this.onClosed,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.duration)
      ..forward();
    _timer = Timer(const Duration(seconds: 3), _dismiss);
  }

  void _dismiss() {
    _timer?.cancel();
    if (!mounted) {
      widget.onClosed();
      return;
    }
    _controller.reverse().then((_) => widget.onClosed());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: AppMotion.curve);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.3),
                end: Offset.zero,
              ).animate(curved),
              child: Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.md,
                  left: AppSpacing.lg,
                  right: AppSpacing.lg,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: GestureDetector(
                    onTap: _dismiss,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 460),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: widget.scheme.inverseSurface,
                        borderRadius: AppRadius.allMd,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: DefaultTextStyle.merge(
                        style: TextStyle(color: widget.scheme.onInverseSurface),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.icon,
                              size: 18,
                              color: widget.iconColor,
                            ),
                            AppSpacing.gapMd,
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(widget.message),
                                  if (widget.subtitle != null) ...[
                                    AppSpacing.gapXxs,
                                    DefaultTextStyle.merge(
                                      style: TextStyle(
                                        color: widget.scheme.onInverseSurface
                                            .withValues(alpha: 0.8),
                                      ),
                                      child: Text(widget.subtitle!).small,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
