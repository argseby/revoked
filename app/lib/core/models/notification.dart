/// An in-app notification delivered to a user within a workspace (e.g. a
/// request was answered, a link was accessed).
class AppNotification {
  final String id;
  final String user;
  final String workspace;

  /// Machine-readable category of the event, used to pick an icon/route.
  final String type;
  final String title;
  final String? message;

  /// Together with [refId], a back-reference to the record that triggered
  /// this notification: the PocketBase collection name and that record's id.
  final String? refCollection;
  final String? refId;

  /// Whether the user has marked this notification as read.
  final bool read;
  final String? created;

  AppNotification({
    required this.id,
    required this.user,
    required this.workspace,
    required this.type,
    required this.title,
    this.message,
    this.refCollection,
    this.refId,
    required this.read,
    this.created,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      user: json['user'] as String,
      workspace: json['workspace'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      message: json['message'] as String?,
      refCollection: json['refCollection'] as String?,
      refId: json['refId'] as String?,
      read: json['read'] as bool? ?? false,
      created: json['created'] as String?,
    );
  }
}
