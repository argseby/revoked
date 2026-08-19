import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_colors.dart';

/// Semantic colors for the common `status` field on links and requests.
///
/// Keep the mapping in one place so every screen renders "active" the
/// same green-blue, "paused" the same amber, etc.
abstract class StatusColors {
  static Color background(ThemeData theme, String status) {
    return _color(theme, status).withValues(alpha: 0.1);
  }

  static Color border(ThemeData theme, String status) {
    return _color(theme, status).withValues(alpha: 0.3);
  }

  static Color foreground(ThemeData theme, String status) {
    return _color(theme, status);
  }

  static String displayLabel(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'paused':
        return 'Paused';
      case 'revoked':
        return 'Revoked';
      case 'expired':
        return 'Expired';
      case 'completed':
        return 'Completed';
      default:
        if (status.isEmpty) return 'Unknown';
        return status[0].toUpperCase() + status.substring(1);
    }
  }

  static Color _color(ThemeData theme, String status) {
    switch (status) {
      case 'active':
        return theme.colorScheme.primary;
      case 'paused':
        return theme.colorScheme.warning;
      case 'completed':
        return theme.colorScheme.primary;
      case 'revoked':
      case 'expired':
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.onSurfaceVariant;
    }
  }
}
