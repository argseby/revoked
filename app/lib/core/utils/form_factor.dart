import 'package:flutter/foundation.dart';

/// Whether the app runs on a phone or tablet: the device a person carries,
/// and so the one their passkey should live on.
bool get isMobileDevice =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);
