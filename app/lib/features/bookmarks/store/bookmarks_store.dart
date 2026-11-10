import 'dart:typed_data';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/features/bookmarks/store/saved_link_state.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/bookmark.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/state/load_state.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';

part 'bookmarks_store.g.dart';

// ignore: library_private_types_in_public_api
class BookmarksStore = _BookmarksStore with _$BookmarksStore;

/// Share links the signed-in user saved to their account. Personal, not
/// workspace data: the collection rules admit the owning user alone.
abstract class _BookmarksStore with Store {
  final ApiClient _api;

  _BookmarksStore(this._api);
  final SavedLinkState _saved = SavedLinkState();

  String _address(String origin, String slug) => SavedLinkState.address(
    Stores.auth.userId,
    _api.baseUrl.toLowerCase(),
    origin.toLowerCase(),
    slug,
  );

  Future<Uint8List?> keyFor(Bookmark bookmark) async {
    if (bookmark.kind != BookmarkKind.share) return null;
    if (bookmark.sealedKey.isNotEmpty) {
      await Stores.keys.ensureLoaded();
      return Stores.keys.openBookmarkKey(
        wrap: bookmark.sealedKey,
        epoch: bookmark.keyEpoch,
        server: _api.baseUrl.toLowerCase(),
        origin: bookmark.origin.toLowerCase(),
        slug: bookmark.slug,
      );
    }
    return _saved.key(_address(bookmark.origin, bookmark.slug));
  }

  Future<Map<String, dynamic>> checkRead(
    String origin,
    String slug,
    Map<String, dynamic> served,
    Map<String, dynamic> opened,
  ) => _saved.checkRead(_address(origin, slug), served, opened);

  /// Stores only a wrapped key on the server. Without account encryption it
  /// stays in this device's secure storage, including across app restarts.
  Future<bool> rememberKey(Bookmark bookmark, Uint8List key) async {
    final address = _address(bookmark.origin, bookmark.slug);
    final user = Stores.auth.userId;
    final existing = await keyFor(bookmark);
    if (bookmark.sealedKey.isNotEmpty &&
        existing != null &&
        SealedFormats.linkKeyText(existing) == SealedFormats.linkKeyText(key)) {
      return true;
    }
    await Stores.keys.ensureLoaded();
    final ready = await Stores.keys.ensureAccountKey();
    final wrapped = ready
        ? Stores.keys.sealBookmarkKey(
            linkKey: key,
            server: _api.baseUrl.toLowerCase(),
            origin: bookmark.origin.toLowerCase(),
            slug: bookmark.slug,
          )
        : null;
    if (user != Stores.auth.userId) return false;
    if (wrapped != null) {
      if (!await _patch(bookmark.id, {
        'sealedKey': wrapped.wrap,
        'keyEpoch': wrapped.epoch,
      })) {
        return false;
      }
      await _saved.deleteKey(address);
    } else {
      if (bookmark.sealedKey.isNotEmpty) {
        // An unreadable synced key must not silently be replaced with a local
        // one while other devices keep the previous address.
        return false;
      }
      await _saved.saveKey(address, key);
    }
    return true;
  }

  String get _basePath =>
      '/api/collections/${AppConfig.bookmarksCollection}/records';

  String get _groupsPath =>
      '/api/collections/${AppConfig.bookmarkGroupsCollection}/records';

  String get _blocksPath =>
      '/api/collections/${AppConfig.contactBlocksCollection}/records';

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
  Bookmark? find({
    required String origin,
    required String slug,
    BookmarkKind kind = BookmarkKind.share,
  }) {
    for (final b in bookmarks) {
      if (b.slug == slug &&
          b.kind == kind &&
          b.origin.toLowerCase() == origin.toLowerCase()) {
        return b;
      }
    }
    return null;
  }

  /// Tracks this list for the cache and the first-load skeleton.
  final LoadState loadState = LoadState();

  /// [load], unless what's here is still fresh.
  Future<void> loadIfDue() async {
    if (loadState.isDue) await load();
  }

  @action
  Future<void> load() async {
    isLoading = true;
    error = null;
    final ticket = loadState.begin();
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
      if (!loadState.isCurrent(ticket)) return;
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
      loadState.succeed(ticket);
    } catch (e) {
      if (!loadState.isCurrent(ticket)) return;
      error = AppErrorMessage.fromException(e);
      loadState.fail(ticket, error!.description);
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
    BookmarkKind kind = BookmarkKind.share,
    Uint8List? linkKey,
  }) async {
    isSaving = true;
    error = null;
    try {
      final address = _address(origin, slug);
      ({String wrap, int epoch})? wrapped;
      if (linkKey != null && kind == BookmarkKind.share) {
        await Stores.keys.ensureLoaded();
        if (await Stores.keys.ensureAccountKey()) {
          wrapped = Stores.keys.sealBookmarkKey(
            linkKey: linkKey,
            server: _api.baseUrl.toLowerCase(),
            origin: origin.toLowerCase(),
            slug: slug,
          );
        }
        if (wrapped == null) await _saved.saveKey(address, linkKey);
      }
      if (user != Stores.auth.userId) {
        throw const FormatException('The signed-in account changed.');
      }
      final data = await _api.post(
        _basePath,
        body: {
          'user': user,
          'origin': origin,
          'slug': slug,
          'kind': kind.wire,
          'label': label,
          if (wrapped != null) 'sealedKey': wrapped.wrap,
          if (wrapped != null) 'keyEpoch': wrapped.epoch,
        },
      );
      final bookmark = Bookmark.fromJson(data as Map<String, dynamic>);
      if (wrapped != null &&
          (bookmark.sealedKey != wrapped.wrap ||
              bookmark.keyEpoch != wrapped.epoch)) {
        // Older servers may ignore fields they do not know. The key remains
        // usable on this device, and the save confirmation says so.
        if (bookmark.sealedKey.isNotEmpty) {
          throw const FormatException(
            'The server did not retain the saved link key.',
          );
        }
        await _saved.saveKey(address, linkKey!);
      }
      bookmarks.insert(0, bookmark);
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
            kind: b.kind,
            sender: b.sender,
            sealedKey: b.sealedKey,
            keyEpoch: b.keyEpoch,
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
      if (body.containsKey('sealedKey') &&
          (data['sealedKey'] != body['sealedKey'] ||
              data['keyEpoch'] != body['keyEpoch'])) {
        throw const FormatException(
          'The server did not retain the saved link key.',
        );
      }
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

  /// Refuses everything this account sends from now on. The bookmarks it
  /// already left stay where they are — removing them is a separate choice,
  /// and one of them is how the sender was named in the first place.
  ///
  /// The sender is never told. They see what an unconfirmed contact sees,
  /// so a block does not read as an invitation to come back under another
  /// account.
  @action
  Future<bool> blockSender({
    required String user,
    required String sender,
  }) async {
    isSaving = true;
    error = null;
    try {
      await _api.post(_blocksPath, body: {'user': user, 'blockedUser': sender});
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    } finally {
      isSaving = false;
    }
  }

  @action
  Future<bool> remove(String id) async {
    isSaving = true;
    error = null;
    try {
      await _api.delete('$_basePath/$id');
      final bookmark = bookmarks.where((b) => b.id == id).firstOrNull;
      if (bookmark != null) {
        await _saved.deleteKey(_address(bookmark.origin, bookmark.slug));
      }
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
