import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/network/api_client.dart';

void main() {
  test('typing the bare domain is enough', () {
    expect(
      AppConfig.isOfficialServer(
        ApiClient.normalizeServerUrl('api.revoked.link'),
      ),
      isTrue,
    );
  });

  test('the official server is api.revoked.link over https', () {
    expect(AppConfig.isOfficialServer('https://api.revoked.link'), isTrue);
    expect(AppConfig.isOfficialServer('https://API.revoked.link'), isTrue);
    expect(AppConfig.isOfficialServer('https://api.revoked.link:443'), isTrue);
  });

  test('anything else is not', () {
    expect(AppConfig.isOfficialServer('http://api.revoked.link'), isFalse);
    expect(
      AppConfig.isOfficialServer('https://api.revoked.link:8443'),
      isFalse,
    );
    expect(
      AppConfig.isOfficialServer('https://api.revoked.link.evil'),
      isFalse,
    );
    expect(
      AppConfig.isOfficialServer('https://evil.api.revoked.link'),
      isFalse,
    );
    expect(AppConfig.isOfficialServer('https://revoked.link'), isFalse);
    expect(AppConfig.isOfficialServer('http://127.0.0.1:3000'), isFalse);
    expect(AppConfig.isOfficialServer(''), isFalse);
  });
}
