import 'package:revoked_app/core/utils/deep_links.dart';

/// What a bookmark points at. Stored empty on everything saved before a
/// request could be handed over, which reads as a share.
enum BookmarkKind {
  share,
  request;

  static BookmarkKind parse(String? value) =>
      value == 'request' ? BookmarkKind.request : BookmarkKind.share;

  String get wire => name;
}

/// A link saved to the account so it can be reopened later — one the person
/// saved themselves, or one somebody on this server handed them. Only a
/// pointer: opening one goes through the same public view as the link itself.
class Bookmark {
  final String id;

  /// host[:port] of the server the share lives on; empty for this server.
  final String origin;
  final String slug;

  /// Whether it is something to read or something to answer.
  final BookmarkKind kind;
  final String label;
  final String sealedKey;
  final int keyEpoch;

  /// The account that put this in the tray, for one that was handed over;
  /// empty for a bookmark saved by its owner. Written by the server alone —
  /// it is what refusing a sender is aimed at.
  final String sender;

  /// Ids of the [BookmarkGroup]s it is filed under; empty when ungrouped.
  final List<String> groups;
  final String? created;

  const Bookmark({
    required this.id,
    required this.origin,
    required this.slug,
    required this.label,
    this.kind = BookmarkKind.share,
    this.sender = '',
    this.sealedKey = '',
    this.keyEpoch = 0,
    this.groups = const [],
    this.created,
  });

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      id: json['id'] as String,
      origin: json['origin'] as String? ?? '',
      slug: json['slug'] as String,
      kind: BookmarkKind.parse(json['kind'] as String?),
      label: json['label'] as String? ?? '',
      sealedKey: json['sealedKey'] as String? ?? '',
      keyEpoch: (json['keyEpoch'] as num?)?.toInt() ?? 0,
      sender: json['sender'] as String? ?? '',
      groups: (json['groups'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      created: json['created'] as String?,
    );
  }

  String get title => label.isEmpty ? slug : label;

  /// The `revoked://` link for it, naming [origin] so it resolves against the
  /// server that minted the slug.
  String deepLink(String origin) => kind == BookmarkKind.request
      ? DeepLinks.request(slug, origin: origin)
      : DeepLinks.share(slug, origin: origin);

  String get location => DeepLinks.locationFor(Uri.parse(deepLink(origin)))!;
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
