import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:classicism/api/auth_api.dart';
import 'package:classicism/api/music_api.dart';
import 'package:classicism/core/config.dart';
import 'package:classicism/core/cookie_manager.dart';
import 'package:classicism/core/request_engine.dart';
import 'package:classicism/models/lyric.dart';
import 'package:classicism/models/playlist.dart';
import 'package:classicism/models/song.dart';
import 'package:classicism/services/auth_service.dart';
import 'package:classicism/services/player_service.dart';
import 'package:classicism/state/providers.dart';

// ============================================================
// Test Data
// ============================================================

Song testSong = const Song(
  id: 12345,
  name: 'Test Song',
  artistName: 'Test Artist',
  albumName: 'Test Album',
  coverUrl: 'https://example.com/cover.jpg',
  duration: 240000,
  fee: 0,
);

Song testSong2 = const Song(
  id: 67890,
  name: 'Second Song',
  artistName: 'Another Artist',
  duration: 200000,
);

Playlist testPlaylist = Playlist(
  id: 100,
  name: 'Test Playlist',
  coverImgUrl: 'https://example.com/pl_cover.jpg',
  trackCount: 42,
  playCount: 12345,
  creatorName: 'Test Creator',
);

Lyric testLyric = const Lyric(
  lrc: '[00:01.00]Hello\n[00:02.00]World',
  tlyric: null,
);

// ============================================================
// Mock MusicApi — returns fake data for methods called by UI
// ============================================================

class MockMusicApi extends MusicApi {
  MockMusicApi() : super(request: _dummyRequestEngine());

  @override
  Future<List<Song>> getRecommendSongs() async => [testSong, testSong2];

  @override
  Future<List<Song>> searchSongs(String keywords,
          {int limit = 30, int offset = 0}) async =>
      [testSong];

  @override
  Future<List<Playlist>> searchPlaylists(String keywords,
          {int limit = 30, int offset = 0}) async =>
      [testPlaylist];

  @override
  Future<Playlist?> getPlaylistDetail(int playlistId, {int s = 8}) async =>
      testPlaylist;

  @override
  Future<Lyric?> getLyric(int songId) async => testLyric;

  @override
  Future<List<Map<String, dynamic>>> getSongUrls(List<int> ids,
          {String level = 'exhigh'}) async =>
      ids
          .map((id) => {
                'id': id,
                'url': 'https://example.com/song/$id.mp3',
                'type': 'mp3',
                'level': level,
                'fee': 0,
              })
          .toList();

  @override
  Future<List<Song>> getSongDetail(List<int> ids) async => [testSong];

  @override
  Future<Map<String, dynamic>> search(String keywords,
          {int type = 1, int limit = 30, int offset = 0}) async =>
      {'result': {'songs': [{'id': 1, 'name': 'x'}]}};
}

NeteaseRequest _dummyRequestEngine() {
  final config = AppConfig.instance;
  return NeteaseRequest(
    dio: Dio(),
    cookie: CookieManager(config),
    config: config,
  );
}

// ============================================================
// Mock AuthService
// ============================================================

class MockAuthService extends AuthService {
  bool initCalled = false;
  bool loginCalled = false;
  bool logoutCalled = false;

  MockAuthService()
      : super(
          api: AuthApi(
            request: _dummyRequestEngine(),
            directDio: Dio(),
            config: AppConfig.instance,
          ),
          config: AppConfig.instance,
        );

  @override
  Future<void> initialize() async {
    initCalled = true;
  }

  @override
  Future<LoginResult> loginWithPassword(String phone, String password,
      {String countryCode = '86'}) async {
    loginCalled = true;
    return LoginResult(code: 200);
  }

  @override
  Future<void> logout() async {
    logoutCalled = true;
  }
}

// ============================================================
// Test App Builder
// ============================================================

Future<Widget> buildTestApp({
  Widget? home,
  bool overrideAuth = false,
  bool overridePlayer = false,
  bool overrideSearch = false,
}) async {
  SharedPreferences.setMockInitialValues({});

  final config = AppConfig.instance;
  await config.init();

  final musicApi = MockMusicApi();
  final authService = MockAuthService();
  final playerService = PlayerService(api: musicApi);

  final overrides = <Override>[];

  overrides.add(musicApiProvider.overrideWithValue(musicApi));

  if (overrideAuth) {
    overrides.add(authServiceProvider.overrideWithValue(authService));
  }
  if (overridePlayer) {
    overrides.add(playerServiceProvider.overrideWithValue(playerService));
  }
  if (overrideSearch) {
    overrides.add(musicApiProvider.overrideWithValue(musicApi));
  }

  overrides.add(recommendSongsProvider.overrideWith((_) async => []));

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: home ?? const Scaffold(),
    ),
  );
}

// ============================================================
// Build a full test app with all pages routed
// ============================================================

Future<Widget> buildFullTestApp() async {
  SharedPreferences.setMockInitialValues({});

  final config = AppConfig.instance;
  await config.init();

  final musicApi = MockMusicApi();
  final requestEngine = _dummyRequestEngine();
  final authApi = AuthApi(
    request: requestEngine,
    directDio: Dio(),
    config: config,
  );
  final authService = AuthService(api: authApi, config: config);
  final playerService = PlayerService(api: musicApi);

  return ProviderScope(
    overrides: [
      musicApiProvider.overrideWithValue(musicApi),
      authServiceProvider.overrideWithValue(authService),
      playerServiceProvider.overrideWithValue(playerService),
      recommendSongsProvider.overrideWith((_) async => []),
    ],
    child: const MaterialApp(
      home: Scaffold(),
    ),
  );
}
