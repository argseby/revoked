/// Configuration constants for the API connection.
class AppConfig {
  AppConfig._();

  /// Base URL for the PocketBase API.
  ///
  /// Override at run/build time without editing code:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.178.47:3000
  ///
  /// The default (127.0.0.1) only reaches the backend when the app runs on the
  /// SAME machine as the server (iOS Simulator / macOS desktop). A PHYSICAL
  /// device must use the Mac's LAN IP, because 127.0.0.1 is the phone itself.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );

  /// PocketBase collection names - mirrors Go backend `util/schema.go`.
  static const String usersCollection = 'users';
  static const String workspacesCollection = 'workspaces';
  static const String workspaceMembersCollection = 'workspaceMembers';
  static const String recordsCollection = 'records';
  static const String sectionsCollection = 'sections';
  static const String linksCollection = 'links';
  static const String apiKeysCollection = 'apiKeys';
  static const String templatesCollection = 'templates';
  static const String identitiesCollection = 'identities';
  static const String requestsCollection = 'requests';
  static const String notificationsCollection = 'notifications';
  static const String invitesCollection = 'invites';
}
