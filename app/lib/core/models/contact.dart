/// Whether a contact's key material has been shown to be whose it claims to
/// be. Set by the server alone — an address someone typed in proves nothing
/// about who reads it.
enum ContactTrust {
  unverified,
  verified,
  revoked;

  static ContactTrust parse(String? value) => switch (value) {
    'verified' => ContactTrust.verified,
    'revoked' => ContactTrust.revoked,
    _ => ContactTrust.unverified,
  };
}

/// Someone this workspace sends to and asks from.
///
/// A contact is a route rather than an identity: at most one of an account on
/// this server, a peer server, or an email address. A peer's key material is
/// held as its own fingerprint and domain, never as one of this workspace's
/// identities.
class Contact {
  final String id;
  final String workspace;
  final String name;

  /// The account on this server, when they have one; empty otherwise.
  final String user;
  final String email;
  final String peerDomain;
  final String peerFingerprint;
  final ContactTrust trust;
  final String? verifiedAt;
  final String? lastUsedAt;
  final String? created;

  const Contact({
    required this.id,
    required this.workspace,
    required this.name,
    this.user = '',
    this.email = '',
    this.peerDomain = '',
    this.peerFingerprint = '',
    this.trust = ContactTrust.unverified,
    this.verifiedAt,
    this.lastUsedAt,
    this.created,
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] as String,
      workspace: json['workspace'] as String? ?? '',
      name: json['name'] as String? ?? '',
      user: json['user'] as String? ?? '',
      email: json['email'] as String? ?? '',
      peerDomain: json['peerDomain'] as String? ?? '',
      peerFingerprint: json['peerFingerprint'] as String? ?? '',
      trust: ContactTrust.parse(json['trustState'] as String?),
      verifiedAt: json['verifiedAt'] as String?,
      lastUsedAt: json['lastUsedAt'] as String?,
      created: json['created'] as String?,
    );
  }

  /// Their address belongs to an account here, so what you send reaches them
  /// in the app. Known only once something has been sent: the server resolves
  /// the address, because no client can discover an account by id.
  bool get isHere => user.isNotEmpty;

  bool get isPeer => !isHere && peerDomain.isNotEmpty;

  bool get isEmailOnly => !isHere && !isPeer;

  /// Where they are, for the second line of a card.
  String get where => isHere
      ? email
      : isPeer
      ? 'on $peerDomain'
      : email;
}

/// What became of a grant handed to a contact.
///
/// [delivered] says the grant reached an account on this server and is in that
/// person's tray; [emailed] says it went out by email instead. With neither,
/// the grant still exists — the slug has to be passed on by hand.
class ContactGrant {
  final String id;
  final String slug;

  /// `share` for something sent, `request` for something asked.
  final String kind;
  final bool delivered;

  /// An email with the link is on its way. Queued, not yet accepted by a
  /// mail server.
  final bool emailed;

  const ContactGrant({
    required this.id,
    required this.slug,
    required this.kind,
    required this.delivered,
    this.emailed = false,
  });

  factory ContactGrant.fromJson(Map<String, dynamic> json) {
    return ContactGrant(
      id: json['id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      delivered: json['delivered'] as bool? ?? false,
      emailed: json['emailed'] as bool? ?? false,
    );
  }

  bool get isRequest => kind == 'request';
}
