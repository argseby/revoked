import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:revoked_app/core/models/tool_client.dart';

/// A text in English and German, as an entry in Works with Revoked holds it.
class LocalizedText {
  final String en;
  final String de;

  const LocalizedText({this.en = '', this.de = ''});

  static LocalizedText fromJson(Object? raw) {
    if (raw is! Map) return const LocalizedText();
    return LocalizedText(en: _line(raw['en']), de: _line(raw['de']));
  }

  /// The German text on a German device, the English one everywhere else.
  String get text => forLanguage(
    PlatformDispatcher.instance.locale.languageCode.toLowerCase(),
  );

  String forLanguage(String language) =>
      language == 'de' && de.isNotEmpty ? de : en;

  bool get isEmpty => en.isEmpty && de.isEmpty;
}

/// What a service does with Revoked, as the list filters by it.
enum ServiceKind {
  share('share', 'Share'),
  collect('collect', 'Collect'),
  prove('prove', 'Prove'),
  signIn('sign_in', 'Sign in'),
  connect('connect', 'Connect');

  const ServiceKind(this.key, this.label);
  final String key;
  final String label;

  static ServiceKind? fromKey(String key) {
    for (final k in values) {
      if (k.key == key) return k;
    }
    return null;
  }
}

enum ServiceCategory {
  health('health', 'Health'),
  housing('housing', 'Housing'),
  work('work', 'Work'),
  finance('finance', 'Finance'),
  games('games', 'Games'),
  developer('developer', 'Developer'),
  other('other', 'Other');

  const ServiceCategory(this.key, this.label);
  final String key;
  final String label;

  static ServiceCategory? fromKey(String key) {
    for (final c in values) {
      if (c.key == key) return c;
    }
    return null;
  }
}

/// How much of the vault a service can reach once connected, the strongest
/// it may ask for. The list filters by it.
enum ServiceAccess {
  linksOnly('Never reads the vault'),
  ownSection('Own section only'),
  readsVault('Reads the vault');

  const ServiceAccess(this.label);
  final String label;
}

/// One switch a service may ask for, with the reason its entry gives.
class ServicePermission {
  final String key;
  final LocalizedText reason;

  const ServicePermission({required this.key, required this.reason});

  /// The switch as the connect screen names it.
  String get label => switch (key) {
    'section' => 'Vault section',
    'read_vault' => 'Read vault',
    'revoke_links' => 'Revoke its links',
    'receive_links' => 'Receive links',
    'shares:read' => 'See its shares',
    'shares:manage' => 'Manage shares',
    'requests:manage' => 'Manage requests',
    'attestations:issue' => 'Issue attestations',
    'vault:read' => 'Read its section',
    'vault:write' => 'Add to its section',
    _ => key,
  };

  /// Allows something that cannot be taken back, as the connect screen
  /// marks it.
  bool get sensitive => const {
    'read_vault',
    'receive_links',
    'shares:manage',
    'requests:manage',
  }.contains(key);
}

/// One service listed in Works with Revoked. Everything here was reviewed in
/// the repository's `services/` folder; nothing comes from the service.
class WorksWithService {
  final String slug;

  /// The service's origin: what identifies it, and what proposals are
  /// matched against.
  final String origin;
  final String name;
  final LocalizedText description;
  final String operatorName;
  final String imprint;
  final String security;
  final String privacyPolicy;
  final String website;
  final String source;
  final bool selfHostable;

  /// The servers it works with; empty for every Revoked server.
  final List<String> servers;
  final List<String> languages;
  final String pricing;
  final List<ServiceCategory> categories;
  final List<ServiceKind> does;
  final List<String> shareTemplates;
  final List<String> shareKeys;
  final List<String> requestTemplates;
  final List<ServicePermission> permissions;
  final LocalizedText stores;
  final bool builtByRevoked;

  /// Whether the service's own domain confirmed the entry with its proof
  /// file. Unverified entries are reviewed too; only that confirmation is
  /// missing.
  final bool verified;

  /// The origin stopped answering; the entry is removed if it stays so.
  final bool unavailable;
  final String reviewed;

  const WorksWithService({
    required this.slug,
    required this.origin,
    required this.name,
    this.description = const LocalizedText(),
    this.operatorName = '',
    this.imprint = '',
    this.security = '',
    this.privacyPolicy = '',
    this.website = '',
    this.source = '',
    this.selfHostable = false,
    this.servers = const [],
    this.languages = const [],
    this.pricing = '',
    this.categories = const [],
    this.does = const [],
    this.shareTemplates = const [],
    this.shareKeys = const [],
    this.requestTemplates = const [],
    this.permissions = const [],
    this.stores = const LocalizedText(),
    this.builtByRevoked = false,
    this.verified = false,
    this.unavailable = false,
    this.reviewed = '',
  });

  /// Reads one entry, or null when it lacks what identifies it. Unknown
  /// words in its lists are skipped, so an older app keeps working with a
  /// newer catalog.
  static WorksWithService? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final origin = ToolClient.origin(_line(raw['origin']));
    final slug = _line(raw['slug']);
    final name = _line(raw['name']);
    if (origin == null || slug.isEmpty || name.isEmpty) return null;
    final operator = raw['operator'] is Map ? raw['operator'] as Map : {};
    final proposes = raw['proposes'] is Map ? raw['proposes'] as Map : {};
    final shares = proposes['shares'] is Map ? proposes['shares'] as Map : {};
    final requests = proposes['requests'] is Map
        ? proposes['requests'] as Map
        : {};
    return WorksWithService(
      slug: slug,
      origin: origin,
      name: name,
      description: LocalizedText.fromJson(raw['description']),
      operatorName: _line(operator['name']),
      imprint: _https(operator['imprint']),
      security: _contact(operator['security']),
      privacyPolicy: _https(raw['privacy_policy']),
      website: _https(raw['website']),
      source: _https(raw['source']),
      selfHostable: raw['self_hostable'] == true,
      servers: _strings(raw['servers']),
      languages: _strings(raw['languages']),
      pricing: _line(raw['pricing']),
      categories: [
        for (final k in _strings(raw['categories']))
          ?ServiceCategory.fromKey(k),
      ],
      does: [for (final k in _strings(raw['does'])) ?ServiceKind.fromKey(k)],
      shareTemplates: _strings(shares['templates']),
      shareKeys: _strings(shares['keys']),
      requestTemplates: _strings(requests['templates']),
      permissions: [
        if (raw['permissions'] is List)
          for (final p in raw['permissions'] as List)
            if (p is Map && _line(p['key']).isNotEmpty)
              ServicePermission(
                key: _line(p['key']),
                reason: LocalizedText.fromJson(p['reason']),
              ),
      ],
      stores: LocalizedText.fromJson(raw['stores']),
      builtByRevoked: raw['built_by_revoked'] == true,
      verified: raw['verified'] == true,
      unavailable: raw['status'] == 'unavailable',
      reviewed: _line(raw['reviewed']),
    );
  }

  String get host => Uri.parse(origin).host;

  bool get worksWithAnyServer => servers.isEmpty;

  bool declares(String permissionKey) =>
      permissions.any((p) => p.key == permissionKey);

  ServiceAccess get access {
    if (declares('read_vault')) return ServiceAccess.readsVault;
    if (declares('section') ||
        declares('vault:read') ||
        declares('vault:write')) {
      return ServiceAccess.ownSection;
    }
    return ServiceAccess.linksOnly;
  }

  String get pricingLabel => switch (pricing) {
    'free' => 'Free',
    'paid' => 'Paid',
    'freemium' => 'Free and paid plans',
    _ => '',
  };

  /// The words a search matches against.
  String get searchText => [
    name,
    host,
    description.en,
    description.de,
    operatorName,
    for (final c in categories) c.label,
    for (final k in does) k.label,
    ...shareTemplates,
    ...shareKeys,
    ...requestTemplates,
  ].join(' ').toLowerCase();

  /// What a connect link asks for beyond this entry. The tool's address is
  /// bound to the link by the app and the server, so a lookup by origin is
  /// enough: a page claiming another tool's origin only sends its answer
  /// back to that tool. Revoking and receiving links are offered to every
  /// tool and so are never counted.
  List<String> undeclaredForConnect(ConnectRequest r) => [
    if (r.section && !declares('section')) 'section',
    if (r.vault && !declares('read_vault')) 'read_vault',
    for (final key in r.permissions)
      if (!declares(key)) key,
  ];

  /// Record keys a share proposal names beyond this entry's.
  List<String> undeclaredKeys(Iterable<String> keys) => [
    for (final key in keys)
      if (!shareKeys.contains(key)) key,
  ];
}

/// The whole list, as built from the repository by `cmd/works-with`.
class WorksWithCatalog {
  static const schema = 1;

  final List<WorksWithService> services;

  const WorksWithCatalog(this.services);

  static const empty = WorksWithCatalog([]);

  /// Parses a catalog, or null when it is not one this app can read. A bad
  /// entry is skipped rather than failing the list.
  static WorksWithCatalog? parse(String body) {
    try {
      final raw = jsonDecode(body);
      if (raw is! Map || raw['schema'] != schema) return null;
      final list = raw['services'];
      if (list is! List) return null;
      final seen = <String>{};
      return WorksWithCatalog([
        for (final s in list.map(WorksWithService.fromJson))
          if (s != null && seen.add(s.origin)) s,
      ]);
    } catch (_) {
      return null;
    }
  }

  /// The entry for [origin], or null when the service is not listed. Not
  /// being listed is normal and says nothing about a tool.
  WorksWithService? forOrigin(String origin) {
    final o = ToolClient.origin(origin);
    if (o == null) return null;
    for (final s in services) {
      if (s.origin == o) return s;
    }
    return null;
  }

  WorksWithService? bySlug(String slug) {
    for (final s in services) {
      if (s.slug == slug) return s;
    }
    return null;
  }
}

String _line(Object? raw) =>
    raw is String ? raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').trim() : '';

List<String> _strings(Object? raw) => [
  if (raw is List)
    for (final e in raw)
      if (_line(e).isNotEmpty) _line(e),
];

/// Only https addresses are opened from an entry.
String _https(Object? raw) {
  final s = _line(raw);
  final uri = Uri.tryParse(s);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty ? s : '';
}

String _contact(Object? raw) {
  final s = _line(raw);
  if (s.startsWith('mailto:') && s.contains('@')) return s;
  return _https(s);
}
