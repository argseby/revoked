import 'package:revoked_app/core/models/audience.dart';

/// Represents a section from the PocketBase `sections` collection.
class Section {
  final String id;
  final String key;
  final String name;
  final List<String> records;
  final String user;
  final String workspace;
  final String? created;
  final String? updated;

  /// Optional. Set when this section was instantiated as a result of an
  /// inbound public request submission.
  final String? requestedBy;

  /// Who sees it beside its owner: `private`, `workspace` or `groups`.
  /// Only the owner changes it.
  final String audienceKind;

  /// Whether the members who see it may also change it, with the permission
  /// to manage the vault: `owner` or `audience`.
  final String editing;

  /// Whether this person may change it, on a section someone else shared.
  final bool canEdit;

  /// Whether the whole workspace sees it.
  bool get shared => audienceKind == 'workspace';

  /// The owner's address, on a section someone else shared with this person.
  final String? ownerEmail;

  Section({
    required this.id,
    required this.key,
    required this.name,
    required this.records,
    required this.user,
    required this.workspace,
    this.created,
    this.updated,
    this.requestedBy,
    this.audienceKind = 'private',
    this.editing = 'owner',
    this.canEdit = false,
    this.ownerEmail,
  });

  factory Section.fromJson(Map<String, dynamic> json) {
    final requestedByRaw = json['requestedBy'];
    return Section(
      id: json['id'] as String,
      key: json['key'] as String,
      name: json['name'] as String,
      records:
          (json['records'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      user: json['user'] as String,
      workspace: json['workspace'] as String,
      created: json['created'] as String?,
      updated: json['updated'] as String?,
      requestedBy: (requestedByRaw is String && requestedByRaw.isNotEmpty)
          ? requestedByRaw
          : null,
      audienceKind: _audienceKind(json),
      editing: json['editing'] == 'audience' ? 'audience' : 'owner',
      canEdit: json['canEdit'] == true,
      ownerEmail: json['ownerEmail'] as String?,
    );
  }

  bool get isRequested => requestedBy != null && requestedBy!.isNotEmpty;

  /// Holds the entries made for a service the person signed in to, which
  /// [requestedBy] names.
  bool get isSignIn => key.startsWith('signin_');

  /// A copy with other records, keeping everything else.
  Section withRecords(List<String> records) => Section(
    id: id,
    key: key,
    name: name,
    records: records,
    user: user,
    workspace: workspace,
    created: created,
    updated: updated,
    requestedBy: requestedBy,
    audienceKind: audienceKind,
    editing: editing,
    canEdit: canEdit,
    ownerEmail: ownerEmail,
  );

  /// Older servers send only `shared`.
  static String _audienceKind(Map<String, dynamic> json) {
    final kind = json['audienceKind'];
    if (kind == null && json['shared'] == true) return 'workspace';
    return audienceKindFrom(kind);
  }
}
