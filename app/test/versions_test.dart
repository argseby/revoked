import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/utils/versions.dart';

void main() {
  test('equal releases are in step', () {
    expect(compareVersions('v0.22.0', 'v0.22.0'), VersionStanding.inStep);
    expect(compareVersions('v0.22.0', 'v0.22.0+dirty'), VersionStanding.inStep);
  });

  test('the older side is named', () {
    expect(compareVersions('v0.21.1', 'v0.22.0'), VersionStanding.appBehind);
    expect(compareVersions('v0.9.0', 'v0.10.0'), VersionStanding.appBehind);
    expect(compareVersions('v1.0.0', 'v0.22.3'), VersionStanding.serverBehind);
  });

  test('anything without a release number is unknown', () {
    expect(compareVersions('dev', 'v0.22.0'), VersionStanding.unknown);
    expect(
      compareVersions('v0.22.0', 'dev-60543ebdd60f'),
      VersionStanding.unknown,
    );
    expect(compareVersions('v0.22.0', null), VersionStanding.unknown);
  });
}
