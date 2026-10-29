import 'package:revoked_app/core/config/app_config.dart';

/// The domains `blocked-domains.txt` lists as impersonating Revoked.
class ServerBlocklist {
  final List<RegExp> _rules;

  const ServerBlocklist._(this._rules);

  factory ServerBlocklist.parse(String text) {
    final rules = <RegExp>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim().toLowerCase();
      if (line.isEmpty || line.startsWith('#')) continue;
      final pattern = line.split('*').map(RegExp.escape).join('[^.]*');
      rules.add(RegExp('^$pattern\$'));
    }
    return ServerBlocklist._(rules);
  }

  /// Whether [host], or any domain it is a subdomain of, matches a rule.
  /// The official domain is exempt, so a bad line cannot lock everyone out.
  bool blocks(String host) {
    final h = host.trim().toLowerCase();
    if (h.isEmpty || AppConfig.isOfficialDomain(h)) return false;
    final labels = h.split('.');
    for (var i = 0; i < labels.length; i++) {
      final candidate = labels.sublist(i).join('.');
      if (_rules.any((r) => r.hasMatch(candidate))) return true;
    }
    return false;
  }
}
