import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Opens [route] remembering the page it was opened from, for a page several
/// places lead to, so its back arrow returns there rather than to one parent.
void goReturning(BuildContext context, String route) {
  final from = GoRouterState.of(context).uri.path;
  context.go(Uri(path: route, queryParameters: {'from': from}).toString());
}

/// Back to the page that opened this one through [goReturning], or to
/// [fallback] when it was reached some other way.
void goBack(BuildContext context, String fallback) {
  final from = GoRouterState.of(context).uri.queryParameters['from'];
  // Only a path inside the app: the query can come from a pasted link.
  final inApp = from != null && from.startsWith('/') && !from.startsWith('//');
  context.go(inApp ? from : fallback);
}
