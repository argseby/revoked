import 'package:flutter/widgets.dart';

import 'package:revoked_app/core/stores.dart';

/// For a screen that shows cached lists: asks them to refresh when it opens,
/// and again whenever the app comes back to the foreground, since anything may
/// have changed while it was away.
mixin RefreshOnEntry<T extends StatefulWidget> on State<T> {
  AppLifecycleListener? _lifecycle;

  /// Calls `loadIfDue` on the stores this screen reads.
  void refresh();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        Stores.invalidateLoads();
        refresh();
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) refresh();
    });
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }
}
