import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/state/display_preferences.dart';

/// Shows [child] only at the Full detail level; at Essentials it shows
/// [essentials], or nothing.
///
/// For what an expert wants and a newcomer is better off without: a link's
/// slug and formats, a key's fingerprint, the reason behind a verdict.
/// Nothing needed to decide or act may sit behind it.
class DetailGate extends StatelessWidget {
  final Widget child;
  final Widget? essentials;

  const DetailGate({super.key, required this.child, this.essentials});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) => DisplayPreferences.detailLevel == DetailLevel.full
          ? child
          : (essentials ?? const SizedBox.shrink()),
    );
  }
}
