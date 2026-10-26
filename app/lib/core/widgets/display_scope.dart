import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/state/display_preferences.dart';

/// Applies the in-app display preferences under [child]: text size on top of
/// the system's, and reduced motion when either the system or the person
/// asks for it. Everything below reads them from `MediaQuery` as usual.
class DisplayScope extends StatelessWidget {
  final Widget child;

  const DisplayScope({super.key, required this.child});

  /// The largest text the app is laid out for: twice the system's own
  /// largest setting would break more than it helps.
  static const double maxScale = 3;

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final media = MediaQuery.of(context);
        final factor = DisplayPreferences.textScale;
        final reduce = DisplayPreferences.reduceMotion;
        if (factor == 1.0 && !reduce) return child;
        return MediaQuery(
          data: media.copyWith(
            textScaler: factor == 1.0
                ? media.textScaler
                : TextScaler.linear(
                    (media.textScaler.scale(1) * factor).clamp(1.0, maxScale),
                  ),
            disableAnimations: media.disableAnimations || reduce,
          ),
          child: child,
        );
      },
    );
  }
}
