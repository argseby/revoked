import 'package:revoked_app/core/utils/deep_links.dart';

/// A share link saved to the account so it can be reopened later. Only a
/// pointer: opening one goes through the same public view as the link itself.
class Bookmark {
  final String id;

  /// host[:port] of the server the share lives on; empty for this server.
  final String origin;
  final String slug;
  final String label;

  /// Ids of the [BookmarkGroup]s it is filed under; empty when ungrouped.
  final List<String> groups;
  final String? created;

  const Bookmark({
    required this.id,
    required this.origin,
    required this.slug,
    required this.label,
    this.groups = const [],
    this.created,
  });

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      id: json['id'] as String,
      origin: json['origin'] as String? ?? '',
      slug: json['slug'] as String,
      label: json['label'] as String? ?? '',
      groups: (json['groups'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      created: json['created'] as String?,
    );
  }

  String get title => label.isEmpty ? slug : label;

  String get location =>
      DeepLinks.locationFor(Uri.parse(DeepLinks.share(slug, origin: origin)))!;
}

/// A named list of bookmarks, like a playlist. A bookmark may sit in several.
class BookmarkGroup {
  final String id;
  final String name;

  const BookmarkGroup({required this.id, required this.name});

  factory BookmarkGroup.fromJson(Map<String, dynamic> json) {
    return BookmarkGroup(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
    );
  }
}
