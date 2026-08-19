import 'package:flutter/material.dart';

/// The app's only animation: 200 ms ease-out. Every fade, size change or
/// slide uses exactly this; navigation does not animate at all.
abstract final class AppMotion {
  static const duration = Duration(milliseconds: 200);
  static const curve = Curves.easeOut;
}
