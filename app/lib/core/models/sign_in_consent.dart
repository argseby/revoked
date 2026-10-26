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

  const SignInConsent({
    required this.ticket,
    required this.client,
    required this.accountEmail,
    required this.scopes,
    required this.links,
  });

  factory SignInConsent.fromJson(Map<String, dynamic> json) {
    final account = json['account'] as Map<String, dynamic>? ?? const {};
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
    );
  }

  /// The service's host, for showing who is asking.
  String get clientHost => Uri.tryParse(client)?.host ?? client;
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

  const SignInLinkOption({
    required this.id,
    required this.key,
    this.label = '',
    this.preview = '',
  });

  factory SignInLinkOption.fromJson(Map<String, dynamic> json) =>
      SignInLinkOption(
        id: json['id'] as String,
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
        preview: json['preview'] as String? ?? '',
      );
}
