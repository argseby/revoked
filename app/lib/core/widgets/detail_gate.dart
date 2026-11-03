import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/models/feature.dart';
import 'package:revoked_app/core/stores.dart';

/// Shows [child] while the Developer feature is on; otherwise [essentials],
/// or nothing.
///
/// For what an expert wants and a newcomer is better off without: a link's
/// slug and formats, a key's fingerprint, the request behind a form.
/// Nothing needed to decide or act may sit behind it.
class DetailGate extends StatelessWidget {
  final Widget child;
  final Widget? essentials;

  const DetailGate({super.key, required this.child, this.essentials});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) => Stores.features.visible(Feature.developer)
          ? child
          : (essentials ?? const SizedBox.shrink()),
    );
  }
}
