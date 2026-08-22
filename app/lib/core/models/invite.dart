import 'package:revoked_app/core/models/identity_status_assertion.dart';

/// A permission as a person picks or reads it, mirroring the catalogue in the
/// Go backend's `util/permissions.go`.
///
/// The server stores the expanded scopes and hands back these labelled entries,
/// so the app never has to translate scope strings itself — or drift from the
/// backend's idea of what a permission means.
class InvitePermission {
  final String key;
  final String label;
  final String description;

  /// Marks a permission whose holder can extend or revoke other people's
  /// access, so the UI can warn before it is handed out.
  final bool destructive;

  /// The scopes this permission expands to. Grants are stored expanded, so this
  /// is what lets a stored grant be named back as the permissions that were
  /// picked — counting the scopes instead would report a larger number.
  final List<String> scopes;

  const InvitePermission({
    required this.key,
    required this.label,
    required this.description,
    this.destructive = false,
    this.scopes = const [],
  });

  factory InvitePermission.fromJson(Map<String, dynamic> json) {
    return InvitePermission(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      description: json['description'] as String? ?? '',
      destructive: json['destructive'] as bool? ?? false,
      scopes: ((json['scopes'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  /// Whether a stored scope set includes everything this permission needs.
  bool isSatisfiedBy(List<String> grantedScopes) =>
      scopes.isNotEmpty && scopes.every(grantedScopes.contains);
}

/// Names a stored (expanded) scope set back as the permissions it represents.
List<InvitePermission> permissionsFromScopes(
  List<InvitePermission> catalogue,
  List<String> scopes,
) => catalogue.where((p) => p.isSatisfiedBy(scopes)).toList();

/// What an invite grants, as returned by `GET /api/public/invites/:token`
/// before the recipient decides whether to accept.
class InvitePreview {
  final String label;
  final String workspaceName;
  final String? invitedBy;
  final List<InvitePermission> permissions;
  final bool requiresEmail;
  final String? expiresAt;

  /// The domain this server claims, and the root key it serves. Without them
  /// the recipient has nothing to walk the DNS chain against — and accepting
  /// hands an account to whoever is on the other end.
  final String serverDomain;
  final String serverRootFingerprint;

  /// What the server can actually back up about whoever sent this.
  final InviteInviter? inviter;

  const InvitePreview({
    required this.label,
    required this.workspaceName,
    required this.permissions,
    this.invitedBy,
    this.requiresEmail = false,
    this.expiresAt,
    this.serverDomain = '',
    this.serverRootFingerprint = '',
    this.inviter,
  });

  factory InvitePreview.fromJson(Map<String, dynamic> json) {
    final workspace = (json['workspace'] as Map<String, dynamic>?) ?? const {};
    final server = (json['server'] as Map<String, dynamic>?) ?? const {};
    final perms = (json['permissions'] as List<dynamic>?) ?? const [];
    return InvitePreview(
      label: json['label'] as String? ?? '',
      workspaceName: workspace['name'] as String? ?? 'this workspace',
      invitedBy: _orNull(json['invitedBy'] as String?),
      permissions: perms
          .map((e) => InvitePermission.fromJson(e as Map<String, dynamic>))
          .toList(),
      requiresEmail: json['requiresEmail'] as bool? ?? false,
      expiresAt: _orNull(json['expiresAt'] as String?),
      serverDomain: server['domain'] as String? ?? '',
      serverRootFingerprint: server['rootFingerprint'] as String? ?? '',
      inviter: InviteInviter.fromJson(json['inviter']),
    );
  }

  bool get grantsDestructive => permissions.any((p) => p.destructive);
}

/// What the issuing server states about whoever created an invite.
///
/// There is no address-confirmation flow, so nothing here claims the email was
/// proven — a "verified" flag would be theatre. What the server can say is
/// whose account the address belongs to, whether it even sits in the server's
/// own domain, whether that account may still invite, and which identity it
/// holds. Only the last of those is independently checkable, and it is the one
/// the recipient's DNS chain actually runs on.
class InviteInviter {
  final String email;
  final String emailDomain;
  final String serverDomain;

  /// True only on an exact domain match. Treating a parent domain as the same
  /// organisation needs a public suffix list to be safe, and a wrong "same
  /// organisation" is worse than naming both domains and letting a person judge.
  final bool emailMatchesServer;

  /// False when the account behind the invite is no longer a member who may
  /// invite. The server refuses the acceptance too — this is so the recipient
  /// learns why before they try.
  final bool canStillInvite;

  final String identityName;
  final String identityFingerprint;
  final String parentSignature;
  final String domainAtIssue;
  final String identityStatus;
  final IdentityStatusAssertion? statusAssertion;

  const InviteInviter({
    required this.email,
    required this.emailDomain,
    required this.serverDomain,
    required this.emailMatchesServer,
    required this.canStillInvite,
    this.identityName = '',
    this.identityFingerprint = '',
    this.parentSignature = '',
    this.domainAtIssue = '',
    this.identityStatus = '',
    this.statusAssertion,
  });

  bool get hasIdentity => identityFingerprint.isNotEmpty;
  bool get identityRevoked =>
      identityStatus.isNotEmpty && identityStatus != 'active';

  static InviteInviter? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final identity = (json['identity'] as Map<String, dynamic>?) ?? const {};
    return InviteInviter(
      email: json['email'] as String? ?? '',
      emailDomain: json['emailDomain'] as String? ?? '',
      serverDomain: json['serverDomain'] as String? ?? '',
      emailMatchesServer: json['emailMatchesServer'] as bool? ?? false,
      canStillInvite: json['canStillInvite'] as bool? ?? true,
      identityName: identity['name'] as String? ?? '',
      identityFingerprint: identity['fingerprint'] as String? ?? '',
      parentSignature: identity['parentSignature'] as String? ?? '',
      domainAtIssue: identity['domainAtIssue'] as String? ?? '',
      identityStatus: identity['status'] as String? ?? '',
      statusAssertion: IdentityStatusAssertion.fromJson(
        identity['statusAssertion'],
      ),
    );
  }
}

/// An invite this workspace has issued, from the `invites` collection.
///
/// [plainToken] is only ever present on the response that created the invite —
/// the server stores a hash and returns the token once, in a header.
class Invite {
  final String id;
  final String workspace;
  final String label;
  final String status;
  final List<String> permissions;
  final String? email;
  final String? expiresAt;
  final int maxUses;
  final int useCount;
  final String? created;
  final String? plainToken;

  const Invite({
    required this.id,
    required this.workspace,
    required this.label,
    required this.status,
    required this.permissions,
    this.email,
    this.expiresAt,
    this.maxUses = 0,
    this.useCount = 0,
    this.created,
    this.plainToken,
  });

  factory Invite.fromJson(Map<String, dynamic> json, {String? plainToken}) {
    final perms = (json['permissions'] as List<dynamic>?) ?? const [];
    return Invite(
      id: json['id'] as String,
      workspace: json['workspace'] as String? ?? '',
      label: json['label'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      permissions: perms.map((e) => e.toString()).toList(),
      email: _orNull(json['email'] as String?),
      expiresAt: _orNull(json['expiresAt'] as String?),
      maxUses: (json['maxUses'] as num?)?.toInt() ?? 0,
      useCount: (json['useCount'] as num?)?.toInt() ?? 0,
      created: json['created'] as String?,
      plainToken: plainToken,
    );
  }

  bool get isActive => status == 'active';
  bool get isSingleUse => maxUses == 1;

  /// Remaining uses, or null when the invite is unlimited.
  int? get usesLeft => maxUses > 0 ? (maxUses - useCount) : null;
}

String? _orNull(String? v) => (v == null || v.isEmpty) ? null : v;

/// A person in the workspace, as returned by `GET /api/workspaces/{id}/members`.
///
/// Comes from a dedicated route rather than the collection API: `users` is
/// readable only by its owner, so expanding the relation would hide everyone
/// else and leave a list of ids.
class WorkspaceMemberDetail {
  final String id;
  final String userId;
  final String email;
  final String role;
  final List<InvitePermission> permissions;
  final bool isSelf;

  /// The only member who can still invite. Removing or demoting them would
  /// leave the workspace with nobody able to restore access, so the UI blocks
  /// it rather than letting the server refuse.
  final bool isLastAdmin;

  const WorkspaceMemberDetail({
    required this.id,
    required this.userId,
    required this.email,
    required this.role,
    required this.permissions,
    this.isSelf = false,
    this.isLastAdmin = false,
  });

  factory WorkspaceMemberDetail.fromJson(Map<String, dynamic> json) {
    final perms = (json['permissions'] as List<dynamic>?) ?? const [];
    return WorkspaceMemberDetail(
      id: json['id'] as String,
      userId: json['user'] as String? ?? '',
      email: json['email'] as String? ?? 'Unknown account',
      role: json['role'] as String? ?? 'member',
      permissions: perms
          .map((e) => InvitePermission.fromJson(e as Map<String, dynamic>))
          .toList(),
      isSelf: json['isSelf'] as bool? ?? false,
      isLastAdmin: json['isLastAdmin'] as bool? ?? false,
    );
  }

  List<String> get permissionKeys => permissions.map((p) => p.key).toList();
}

/// The member listing plus what the caller is allowed to do with it.
class WorkspaceMembers {
  final List<WorkspaceMemberDetail> members;

  /// What the caller may hand out; anything else would be refused as
  /// escalation, so the editor only offers these.
  final List<InvitePermission> grantable;
  final bool canManage;

  const WorkspaceMembers({
    required this.members,
    required this.grantable,
    required this.canManage,
  });

  factory WorkspaceMembers.fromJson(Map<String, dynamic> json) {
    final members = (json['members'] as List<dynamic>?) ?? const [];
    final grantable = (json['grantable'] as List<dynamic>?) ?? const [];
    return WorkspaceMembers(
      members: members
          .map((e) => WorkspaceMemberDetail.fromJson(e as Map<String, dynamic>))
          .toList(),
      grantable: grantable
          .map((e) => InvitePermission.fromJson(e as Map<String, dynamic>))
          .toList(),
      canManage: json['canManage'] as bool? ?? false,
    );
  }
}
