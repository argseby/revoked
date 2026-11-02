/// What each optional scope tells a service, in words for the person.
const signInScopeLabels = {
  'profile': 'Your name',
  'email': 'Your email address',
  'revoked_identity': 'Your Revoked identity',
};

/// What the consent screen shows for a sign-in the app opened on its server
/// (`POST /oidc/authorize/app`): who asks, as which account, what each scope
/// would reveal, and the person's entries for each vault key asked for.
///
/// [ticket] names the request on the server; the decision is recorded against
/// it, and it is spent by the first answer.
class SignInConsent {
  final String ticket;

  /// The service's origin.
  final String client;

  /// The account the app is signed into.
  final String accountEmail;

  /// The optional scopes asked for, in the order the server lists them.
  final List<SignInScope> scopes;

  /// The vault keys asked for, each with the entries that could answer it.
  final List<SignInLinkAsk> links;

  /// How the active workspace's vault is filed, for browsing it.
  final List<SignInSection> sections;

  /// The names the person could give this service, when it asks for one.
  final List<SignInNameOption> nameOptions;

  /// The option to start from: what they gave this service last time. Empty
  /// when nothing is picked yet.
  final String nameSelected;

  /// The person's active identities in every workspace, primary first, for
  /// finding one whose key is on this device.
  final List<String> signers;

  /// When the person disconnected this service, if they did and have not come
  /// back since.
  final String? disconnectedAt;

  /// Whether this sign-in gives the service a new ID.
  final bool newId;

  const SignInConsent({
    required this.ticket,
    required this.client,
    required this.accountEmail,
    required this.scopes,
    required this.links,
    this.sections = const [],
    this.nameOptions = const [],
    this.nameSelected = '',
    this.signers = const [],
    this.disconnectedAt,
    this.newId = false,
  });

  factory SignInConsent.fromJson(Map<String, dynamic> json) {
    final account = json['account'] as Map<String, dynamic>? ?? const {};
    final selected = json['nameSelected'] as Map<String, dynamic>?;
    final disconnected = json['disconnected'] as Map<String, dynamic>?;
    return SignInConsent(
      ticket: json['ticket'] as String,
      client: json['client'] as String? ?? '',
      accountEmail: account['email'] as String? ?? '',
      scopes: [
        for (final s in json['scopes'] as List<dynamic>? ?? const [])
          SignInScope.fromJson(s as Map<String, dynamic>),
      ],
      links: [
        for (final l in json['links'] as List<dynamic>? ?? const [])
          SignInLinkAsk.fromJson(l as Map<String, dynamic>),
      ],
      sections: [
        for (final s in json['sections'] as List<dynamic>? ?? const [])
          SignInSection.fromJson(s as Map<String, dynamic>),
      ],
      nameOptions: [
        for (final o in json['nameOptions'] as List<dynamic>? ?? const [])
          SignInNameOption.fromJson(o as Map<String, dynamic>),
      ],
      signers: [
        for (final id in json['signers'] as List<dynamic>? ?? const [])
          id as String,
      ],
      nameSelected: selected == null
          ? ''
          : SignInNameOption.tokenFor(
              selected['kind'] as String? ?? '',
              selected['id'] as String? ?? '',
            ),
      disconnectedAt: disconnected?['at'] as String?,
      newId: disconnected?['newId'] as bool? ?? false,
    );
  }

  /// The service's host, for showing who is asking.
  String get clientHost => Uri.tryParse(client)?.host ?? client;
}

/// A section of the person's vault.
class SignInSection {
  final String id;
  final String name;
  final List<String> records;

  /// Whether it holds entries made for a service they signed in to.
  final bool isSignIn;

  const SignInSection({
    required this.id,
    required this.name,
    this.records = const [],
    this.isSignIn = false,
  });

  factory SignInSection.fromJson(Map<String, dynamic> json) => SignInSection(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    records: [
      for (final r in json['records'] as List<dynamic>? ?? const [])
        r as String,
    ],
    isSignIn: (json['key'] as String? ?? '').startsWith('signin_'),
  );
}

/// One optional scope, and the value it would reveal when the server knows.
class SignInScope {
  final String scope;
  final String value;

  const SignInScope({required this.scope, this.value = ''});

  factory SignInScope.fromJson(Map<String, dynamic> json) => SignInScope(
    scope: json['scope'] as String,
    value: json['value'] is String ? json['value'] as String : '',
  );
}

/// A name the person could give a service: one of their identities' names, or
/// a vault entry that reads as a name.
class SignInNameOption {
  static const fromIdentity = 'identity';
  static const fromRecord = 'record';

  final String kind;
  final String id;
  final String value;

  /// The entry's key and label; empty for an identity.
  final String key;
  final String label;

  const SignInNameOption({
    required this.kind,
    required this.id,
    required this.value,
    this.key = '',
    this.label = '',
  });

  factory SignInNameOption.fromJson(Map<String, dynamic> json) =>
      SignInNameOption(
        kind: json['kind'] as String? ?? '',
        id: json['id'] as String? ?? '',
        value: json['value'] as String? ?? '',
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
      );

  /// Names this option in a select, where a value has to be one string.
  static String tokenFor(String kind, String id) => '$kind:$id';

  String get token => tokenFor(kind, id);
}

/// A vault key the service asks for, and the entries that could answer it,
/// those whose key matches first.
class SignInLinkAsk {
  final String key;
  final List<SignInLinkOption> options;

  const SignInLinkAsk({required this.key, required this.options});

  factory SignInLinkAsk.fromJson(Map<String, dynamic> json) => SignInLinkAsk(
    key: json['key'] as String,
    options: [
      for (final o in json['options'] as List<dynamic>? ?? const [])
        SignInLinkOption.fromJson(o as Map<String, dynamic>),
    ],
  );

  /// The entry offered first: the one under the same key, if there is one.
  SignInLinkOption? get match {
    for (final o in options) {
      if (o.key == key) return o;
    }
    return null;
  }
}

/// An entry the person could share. Hidden entries carry no [preview].
class SignInLinkOption {
  final String id;
  final String key;
  final String label;
  final String preview;
  final String type;

  const SignInLinkOption({
    required this.id,
    required this.key,
    this.label = '',
    this.preview = '',
    this.type = '',
  });

  bool get isFile => type == 'file';

  factory SignInLinkOption.fromJson(Map<String, dynamic> json) =>
      SignInLinkOption(
        id: json['id'] as String,
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
        preview: json['preview'] as String? ?? '',
        type: json['type'] as String? ?? '',
      );
}
