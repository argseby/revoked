import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/bookmark.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';

part 'bookmarks_store.g.dart';

// ignore: library_private_types_in_public_api
class BookmarksStore = _BookmarksStore with _$BookmarksStore;

/// Share links the signed-in user saved to their account. Personal, not
/// workspace data: the collection rules admit the owning user alone.
abstract class _BookmarksStore with Store {
  final ApiClient _api;

  _BookmarksStore(this._api);

  String get _basePath =>
      '/api/collections/${AppConfig.bookmarksCollection}/records';

  String get _groupsPath =>
      '/api/collections/${AppConfig.bookmarkGroupsCollection}/records';

  final ObservableTextController renameLabel = ObservableTextController();
  final ObservableTextController groupName = ObservableTextController();

  @observable
  ObservableList<Bookmark> bookmarks = ObservableList<Bookmark>();

  @observable
  ObservableList<BookmarkGroup> groups = ObservableList<BookmarkGroup>();

  @observable
  bool isCreatingGroup = false;

  List<Bookmark> inGroup(String groupId) =>
      bookmarks.where((b) => b.groups.contains(groupId)).toList();

  @computed
  List<Bookmark> get ungrouped =>
      bookmarks.where((b) => b.groups.isEmpty).toList();

  @observable
  bool isLoading = false;

  @observable
  bool isSaving = false;

  @observable
  AppErrorMessage? error;

  /// The bookmark for a link, matched the way the server's unique index is.
  Bookmark? find({required String origin, required String slug}) {
    for (final b in bookmarks) {
      if (b.slug == slug && b.origin.toLowerCase() == origin.toLowerCase()) {
        return b;
      }
    }
    return null;
  }

  @action
  Future<void> load() async {
    isLoading = true;
    error = null;
    try {
      final results = await Future.wait([
        _api.get(
          _basePath,
          queryParams: {'perPage': '200', 'sort': '-created'},
        ),
        _api.get(_groupsPath, queryParams: {'perPage': '200', 'sort': 'name'}),
      ]);
      List<dynamic> items(dynamic data) =>
          (data['items'] as List<dynamic>?) ?? const [];
      bookmarks = ObservableList.of(
        items(
          results[0],
        ).map((e) => Bookmark.fromJson(e as Map<String, dynamic>)),
      );
      groups = ObservableList.of(
        items(
          results[1],
        ).map((e) => BookmarkGroup.fromJson(e as Map<String, dynamic>)),
      );
    } catch (e) {
      error = AppErrorMessage.fromException(e);
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> add({
    required String user,
    required String origin,
    required String slug,
    required String label,
  }) async {
    isSaving = true;
    error = null;
    try {
      final data = await _api.post(
        _basePath,
        body: {'user': user, 'origin': origin, 'slug': slug, 'label': label},
      );
      bookmarks.insert(0, Bookmark.fromJson(data as Map<String, dynamic>));
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    } finally {
      isSaving = false;
    }
  }

  @action
  Future<bool> rename(String id) =>
      _patch(id, {'label': renameLabel.text.trim()});

  /// Files the bookmark into [groupId], or takes it out.
  @action
  Future<bool> setInGroup(String bookmarkId, String groupId, bool on) async {
    final idx = bookmarks.indexWhere((b) => b.id == bookmarkId);
    if (idx == -1) return false;
    final next = {...bookmarks[idx].groups};
    on ? next.add(groupId) : next.remove(groupId);
    return _patch(bookmarkId, {'groups': next.toList()});
  }

  /// Creates a group named by [groupName]; files [bookmarkId] into it too
  /// when given, the way "New playlist" does from a video's save menu.
  @action
  Future<bool> createGroup({required String user, String? bookmarkId}) async {
    final name = groupName.text.trim();
    if (name.isEmpty) return false;
    isCreatingGroup = true;
    error = null;
    try {
      final data = await _api.post(
        _groupsPath,
        body: {'user': user, 'name': name},
      );
      final group = BookmarkGroup.fromJson(data as Map<String, dynamic>);
      groups.add(group);
      groupName.clear();
      if (bookmarkId != null) {
        return await setInGroup(bookmarkId, group.id, true);
      }
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    } finally {
      isCreatingGroup = false;
    }
  }

  @action
  Future<bool> renameGroup(String id) async {
    final name = groupName.text.trim();
    if (name.isEmpty) return false;
    error = null;
    try {
      final data = await _api.patch('$_groupsPath/$id', body: {'name': name});
      final idx = groups.indexWhere((g) => g.id == id);
      if (idx != -1) {
        groups[idx] = BookmarkGroup.fromJson(data as Map<String, dynamic>);
      }
      groupName.clear();
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    }
  }

  /// The server unlinks the group from its bookmarks; mirrored here so the
  /// list does not wait on a reload to show them as ungrouped.
  @action
  Future<bool> deleteGroup(String id) async {
    error = null;
    try {
      await _api.delete('$_groupsPath/$id');
      groups.removeWhere((g) => g.id == id);
      for (var i = 0; i < bookmarks.length; i++) {
        final b = bookmarks[i];
        if (b.groups.contains(id)) {
          bookmarks[i] = Bookmark(
            id: b.id,
            origin: b.origin,
            slug: b.slug,
            label: b.label,
            groups: b.groups.where((g) => g != id).toList(),
            created: b.created,
          );
        }
      }
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    }
  }

  Future<bool> _patch(String id, Map<String, dynamic> body) async {
    error = null;
    try {
      final data = await _api.patch('$_basePath/$id', body: body);
      final idx = bookmarks.indexWhere((b) => b.id == id);
      if (idx != -1) {
        bookmarks[idx] = Bookmark.fromJson(data as Map<String, dynamic>);
      }
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    }
  }

  @action
  Future<bool> remove(String id) async {
    isSaving = true;
    error = null;
    try {
      await _api.delete('$_basePath/$id');
      bookmarks.removeWhere((b) => b.id == id);
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    } finally {
      isSaving = false;
    }
  }
}
