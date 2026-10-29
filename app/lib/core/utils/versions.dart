/// How this app's release relates to its server's.
enum VersionStanding { inStep, appBehind, serverBehind, unknown }

/// Compares two release versions such as `v0.22.0`. A `dev` build, a missing
/// server version or anything else without a release number is [unknown]:
/// claiming they match would be a guess.
VersionStanding compareVersions(String app, String? server) {
  final a = _release(app);
  final s = server == null ? null : _release(server);
  if (a == null || s == null) return VersionStanding.unknown;
  for (var i = 0; i < 3; i++) {
    if (a[i] < s[i]) return VersionStanding.appBehind;
    if (a[i] > s[i]) return VersionStanding.serverBehind;
  }
  return VersionStanding.inStep;
}

final _releasePattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)');

List<int>? _release(String version) {
  final m = _releasePattern.firstMatch(version.trim());
  if (m == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}
