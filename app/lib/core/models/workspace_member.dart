/// Represents a workspace membership from the PocketBase `workspaceMembers` collection.
class WorkspaceMember {
  final String id;
  final String user;
  final String workspace;
  final String role; // 'admin' | 'member'
  final String? created;
  final String? updated;

  WorkspaceMember({
    required this.id,
    required this.user,
    required this.workspace,
    required this.role,
    this.created,
    this.updated,
  });

  factory WorkspaceMember.fromJson(Map<String, dynamic> json) {
    return WorkspaceMember(
      id: json['id'] as String,
      user: json['user'] as String,
      workspace: json['workspace'] as String,
      role: json['role'] as String,
      created: json['created'] as String?,
      updated: json['updated'] as String?,
    );
  }

  bool get isAdmin => role == 'admin';
}
