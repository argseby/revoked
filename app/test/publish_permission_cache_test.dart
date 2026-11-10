import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'saving membership permissions refreshes the vault publish check in both directions',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      var scopes = ['record:read'];
      await Stores.init(
        httpClient: MockClient((request) async {
          Object data = {};
          switch (request.url.path) {
            case '/api/collections/workspaceMembers/records/member':
              final permissions =
                  jsonDecode(request.body)['permissions'] as List;
              scopes = [
                'record:read',
                if (permissions.contains('vault:publish')) 'record:publish',
              ];
            case '/api/collections/workspaceMembers/records':
              data = {
                'items': [
                  {
                    'id': 'member',
                    'user': 'me',
                    'workspace': 'workspace',
                    'role': 'admin',
                    'permissions': scopes,
                  },
                ],
              };
            case '/api/collections/workspaces/records/workspace':
              data = {
                'id': 'workspace',
                'name': 'Workspace',
                'slug': 'workspace',
              };
            case '/api/workspaces/workspace/members':
              data = {'members': [], 'grantable': [], 'canManage': true};
          }
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      while (!Stores.auth.isInitialized) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      runInAction(
        () => Stores.auth.currentUser = User.fromJson({
          'id': 'me',
          'email': 'me@example.com',
          'activeWorkspace': 'workspace',
        }),
      );
      await Stores.settings.loadWorkspaces('me');
      expect(Stores.settings.canPublishVault, isFalse);
      expect(
        await Stores.invites.updateMemberPermissions('workspace', 'member', [
          'vault:read',
          'vault:publish',
        ]),
        isTrue,
      );
      expect(Stores.settings.canPublishVault, isTrue);
      expect(
        await Stores.invites.updateMemberPermissions('workspace', 'member', [
          'vault:read',
        ]),
        isTrue,
      );
      expect(Stores.settings.canPublishVault, isFalse);
    },
  );
}
