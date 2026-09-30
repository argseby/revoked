import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/utils/deadline.dart';

/// Where a link sits in the Links list. The order is the order on screen:
/// what needs a decision first, what is finished last.
enum LinkGroup { attention, active, paused, closed }

/// Why a live link needs a look soon, in the list's own words.
class LinkAttention {
  /// The row's subtitle: "Expires in 2 days", "9 of 10 views used".
  final String reason;

  /// The row's badge: "Soon", "9/10".
  final String short;

  const LinkAttention(this.reason, this.short);
}

/// A live link that is about to stop working on its own — it runs out of time
/// or out of views. Null when there is nothing to act on.
LinkAttention? linkAttention(Link link, DateTime now) {
  if (link.status != 'active') return null;

  // The server only marks a link expired the next time someone opens it;
  // until then it still says active, so go by the date.
  final expiry = expiryNotice(link.expiresAt, now);
  if (expiry != null) {
    return LinkAttention(
      expiry,
      isPastExpiry(link.expiresAt, now) ? 'Expired' : 'Soon',
    );
  }

  if (link.maxViews > 0) {
    final left = link.maxViews - link.viewCount;
    // The last fifth of the views, and at least the very last one.
    final threshold = (link.maxViews / 5).floor().clamp(1, link.maxViews);
    if (left <= threshold) {
      final used = link.viewCount.clamp(0, link.maxViews);
      return LinkAttention(
        left <= 0
            ? 'All ${link.maxViews} views used'
            : '$used of ${link.maxViews} views used',
        '$used/${link.maxViews}',
      );
    }
  }

  return null;
}

LinkGroup linkGroup(Link link, DateTime now) {
  return switch (link.status) {
    'active' =>
      linkAttention(link, now) == null ? LinkGroup.active : LinkGroup.attention,
    'paused' => LinkGroup.paused,
    _ => LinkGroup.closed,
  };
}
