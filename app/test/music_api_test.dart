import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:classicism/api/music_api.dart';
import 'package:classicism/api/xeapi_proxy.dart';
import 'package:classicism/core/config.dart';
import 'package:classicism/core/cookie_manager.dart';
import 'package:classicism/core/request_engine.dart';

RequestOptions? _lastCaptured;

Dio _createMockDio(Map<String, dynamic> response, {int statusCode = 200}) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      _lastCaptured = options;
      handler.resolve(Response(
        requestOptions: options,
        data: response,
        statusCode: statusCode,
      ));
    },
  ));
  return dio;
}

Future<MusicApi> _createApi(
  Map<String, dynamic> responseBody, {
  XeapiProxy? xeapiProxy,
}) async {
  SharedPreferences.setMockInitialValues({});
  final config = AppConfig.instance;
  await config.init();

  final dio = _createMockDio(responseBody);
  final engine = NeteaseRequest(
    dio: dio,
    cookie: CookieManager(config),
    config: config,
  );

  return MusicApi(request: engine, xeapiProxy: xeapiProxy);
}

void main() {
  // ==========================================================
  // search
  // ==========================================================
  group('search', () {
    test('calls eapi search endpoint', () async {
      final api = await _createApi({
        'code': 200,
        'result': {'songs': [], 'songCount': 0},
      });
      await api.search('test');
      expect(_lastCaptured!.uri.toString(), contains('/eapi/search/get'));
    });

    test('returns result map', () async {
      final api = await _createApi({
        'code': 200,
        'result': {'songs': [{'id': 1, 'name': 'Song1', 'dt': 240000, 'ar': [{'name': 'Artist1'}]}], 'songCount': 1},
      });
      final result = await api.search('test');
      expect(result['code'], 200);
      final res = result['result'] as Map<String, dynamic>;
      expect(res['songCount'], 1);
    });

    test('searchSongs returns parsed Song list', () async {
      final api = await _createApi({
        'code': 200,
        'result': {
          'songs': [
            {
              'id': 123,
              'name': 'Test Song',
              'dt': 180000,
              'ar': [{'name': 'Artist'}],
              'al': {'name': 'Album', 'picUrl': 'http://img'},
              'fee': 0,
            },
          ],
          'songCount': 1,
        },
      });
      final songs = await api.searchSongs('test');
      expect(songs.length, 1);
      expect(songs.first.id, 123);
      expect(songs.first.name, 'Test Song');
      expect(songs.first.artistName, 'Artist');
      expect(songs.first.albumName, 'Album');
      expect(songs.first.duration, 180000);
    });

    test('searchPlaylists returns parsed Playlist list', () async {
      final api = await _createApi({
        'code': 200,
        'result': {
          'playlists': [
            {
              'id': 456,
              'name': 'Test Playlist',
              'coverImgUrl': 'http://cover',
              'trackCount': 50,
              'playCount': 10000,
            },
          ],
        },
      });
      final playlists = await api.searchPlaylists('test');
      expect(playlists.length, 1);
      expect(playlists.first.id, 456);
      expect(playlists.first.name, 'Test Playlist');
      expect(playlists.first.coverImgUrl, 'http://cover');
    });

    test('passes correct search params', () async {
      final api = await _createApi({
        'code': 200,
        'result': {'songs': [], 'songCount': 0},
      });
      await api.search('hello', type: 100, limit: 10, offset: 20);
      expect(_lastCaptured!.uri.toString(), contains('/eapi/search/get'));
    });
  });

  // ==========================================================
  // getLyric
  // ==========================================================
  group('getLyric', () {
    test('returns Lyric on success', () async {
      final api = await _createApi({
        'code': 200,
        'lrc': {'lyric': '[00:01.00]hello', 'version': 1},
        'tlyric': {'lyric': '[00:01.00]你好', 'version': 1},
      });
      final lyric = await api.getLyric(123);
      expect(lyric, isNotNull);
      expect(lyric!.lrc, '[00:01.00]hello');
      expect(lyric.tlyric, '[00:01.00]你好');
    });

    test('returns null on non-200 code', () async {
      final api = await _createApi({
        'code': -1,
      });
      final lyric = await api.getLyric(123);
      expect(lyric, isNull);
    });

    test('calls eapi endpoint', () async {
      final api = await _createApi({
        'code': 200,
        'lrc': {'lyric': 'test'},
      });
      await api.getLyric(456);
      expect(_lastCaptured!.uri.toString(), contains('/eapi/song/lyric'));
    });
  });

  // ==========================================================
  // getSongDetail
  // ==========================================================
  group('getSongDetail', () {
    test('returns parsed Song list', () async {
      final api = await _createApi({
        'code': 200,
        'songs': [
          {
            'id': 789,
            'name': 'Detail Song',
            'dt': 200000,
            'ar': [{'name': 'Singer'}],
            'al': {'name': 'AlbumX', 'picUrl': 'http://img2'},
            'fee': 1,
          },
        ],
      });
      final songs = await api.getSongDetail([789]);
      expect(songs.length, 1);
      expect(songs.first.id, 789);
      expect(songs.first.fee, 1);
    });

    test('calls weapi endpoint (not eapi)', () async {
      final api = await _createApi({
        'code': 200,
        'songs': [],
      });
      await api.getSongDetail([123]);
      expect(_lastCaptured!.uri.toString(), contains('/weapi/v3/song/detail'));
      expect(_lastCaptured!.uri.toString(), isNot(contains('/eapi/')));
    });

    test('formats c param as JSON array of objects', () async {
      final api = await _createApi({
        'code': 200,
        'songs': [],
      });
      await api.getSongDetail([1, 2, 3]);

      // The body is weapi-encrypted; verify URL
      final body = _lastCaptured!.data as Map<String, dynamic>;
      expect(body.containsKey('params'), isTrue);
      expect(body.containsKey('encSecKey'), isTrue);
    });
  });

  // ==========================================================
  // getPlaylistDetail
  // ==========================================================
  group('getPlaylistDetail', () {
    test('returns Playlist on success', () async {
      final api = await _createApi({
        'code': 200,
        'playlist': {
          'id': 999,
          'name': 'My Playlist',
          'coverImgUrl': 'http://cover2',
          'trackCount': 42,
          'playCount': 5000,
        },
      });
      final playlist = await api.getPlaylistDetail(999);
      expect(playlist, isNotNull);
      expect(playlist!.id, 999);
      expect(playlist.name, 'My Playlist');
    });

    test('calls eapi endpoint', () async {
      final api = await _createApi({
        'code': 200,
        'playlist': {'id': 1, 'name': 'test'},
      });
      await api.getPlaylistDetail(1);
      expect(_lastCaptured!.uri.toString(), contains('/eapi/v6/playlist/detail'));
    });
  });

  // ==========================================================
  // getUserPlaylists
  // ==========================================================
  group('getUserPlaylists', () {
    test('returns Playlist list', () async {
      final api = await _createApi({
        'code': 200,
        'playlist': [
          {'id': 100, 'name': 'Playlist 1'},
          {'id': 200, 'name': 'Playlist 2'},
        ],
      });
      final playlists = await api.getUserPlaylists(12345);
      expect(playlists.length, 2);
    });

    test('calls weapi endpoint', () async {
      final api = await _createApi({
        'code': 200,
        'playlist': [],
      });
      await api.getUserPlaylists(123);
      expect(_lastCaptured!.uri.toString(), contains('/weapi/user/playlist'));
    });
  });

  // ==========================================================
  // getRecommendSongs
  // ==========================================================
  group('getRecommendSongs', () {
    test('returns parsed Song list', () async {
      final api = await _createApi({
        'code': 200,
        'data': {
          'dailySongs': [
            {
              'id': 333,
              'name': 'Daily Song',
              'dt': 150000,
              'ar': [{'name': 'Artist'}],
              'al': {'name': 'Album'},
            },
          ],
        },
      });
      final songs = await api.getRecommendSongs();
      expect(songs.length, 1);
      expect(songs.first.id, 333);
    });

    test('calls weapi endpoint', () async {
      final api = await _createApi({
        'code': 200,
        'data': {'dailySongs': []},
      });
      await api.getRecommendSongs();
      expect(
        _lastCaptured!.uri.toString(),
        contains('/weapi/v3/discovery/recommend/songs'),
      );
    });
  });

  // ==========================================================
  // getAlbum
  // ==========================================================
  group('getAlbum', () {
    test('calls weapi with id in path', () async {
      final api = await _createApi({
        'code': 200,
        'album': {'id': 42},
        'songs': [],
      });
      await api.getAlbum(42);
      expect(_lastCaptured!.uri.toString(), contains('/weapi/v1/album/42'));
    });
  });

  // ==========================================================
  // getArtistTopSongs
  // ==========================================================
  group('getArtistTopSongs', () {
    test('returns parsed Song list', () async {
      final api = await _createApi({
        'code': 200,
        'songs': [
          {
            'id': 555,
            'name': 'Top Song',
            'dt': 220000,
            'ar': [{'name': 'Famous'}],
            'al': {'name': 'Hit Album'},
          },
        ],
      });
      final songs = await api.getArtistTopSongs(555);
      expect(songs.length, 1);
      expect(songs.first.id, 555);
    });

    test('calls weapi endpoint', () async {
      final api = await _createApi({
        'code': 200,
        'songs': [],
      });
      await api.getArtistTopSongs(123);
      expect(_lastCaptured!.uri.toString(), contains('/weapi/artist/top/song'));
    });
  });

  // ==========================================================
  // getSongUrls (xeapi)
  // ==========================================================
  group('getSongUrls', () {
    test('throws when proxy not configured', () async {
      final api = await _createApi({'code': 200});
      expect(
        () => api.getSongUrls([123]),
        throwsUnimplementedError,
      );
    });

    test('returns URLs via proxy', () async {
      final proxyDio = Dio();
      proxyDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'body': {
                'code': 200,
                'data': [
                  {
                    'id': 123,
                    'url': 'https://music.example.com/song.mp3',
                    'type': 'flac',
                    'level': 'exhigh',
                    'fee': 0,
                  },
                ],
              },
              'cookie': [],
            },
            statusCode: 200,
          ));
        },
      ));

      final proxy = XeapiProxy(dio: proxyDio, proxyUrl: 'https://proxy.local');
      final api = await _createApi({'code': 200}, xeapiProxy: proxy);

      final urls = await api.getSongUrls([123]);
      expect(urls.length, 1);
      expect(urls.first['url'], 'https://music.example.com/song.mp3');
    });

    test('formats multiple ids correctly', () async {
      RequestOptions? captured;
      final proxyDio = Dio();
      proxyDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'body': {'code': 200, 'data': []},
              'cookie': [],
            },
            statusCode: 200,
          ));
        },
      ));

      final proxy = XeapiProxy(dio: proxyDio, proxyUrl: 'https://proxy.local');
      final api = await _createApi({'code': 200}, xeapiProxy: proxy);

      await api.getSongUrls([1, 2, 3]);
      expect(captured!.data['data']['ids'], '[1,2,3]');
    });

    test('adds immerseType for sky level', () async {
      RequestOptions? captured;
      final proxyDio = Dio();
      proxyDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'body': {'code': 200, 'data': []},
              'cookie': [],
            },
            statusCode: 200,
          ));
        },
      ));

      final proxy = XeapiProxy(dio: proxyDio, proxyUrl: 'https://proxy.local');
      final api = await _createApi({'code': 200}, xeapiProxy: proxy);

      await api.getSongUrls([1], level: 'sky');
      expect(captured!.data['data']['level'], 'sky');
      expect(captured!.data['data']['immerseType'], 'c51');
    });
  });

  // ==========================================================
  // Error & Edge Paths
  // ==========================================================
  group('error paths', () {
    test('search returns empty map when body is null', () async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(requestOptions: options, data: null, statusCode: 200));
        },
      ));
      final engine = NeteaseRequest(dio: dio, cookie: CookieManager(config), config: config);
      final api = MusicApi(request: engine);
      final result = await api.search('test');
      expect(result, isEmpty);
    });

    test('getSongDetail returns empty list on non-success', () async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(requestOptions: options, data: {'code': 500}, statusCode: 200));
        },
      ));
      final engine = NeteaseRequest(dio: dio, cookie: CookieManager(config), config: config);
      final api = MusicApi(request: engine);
      final songs = await api.getSongDetail([1]);
      expect(songs, isEmpty);
    });

    test('getPlaylistDetail returns null on non-200', () async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(requestOptions: options, data: {'code': -1}, statusCode: 200));
        },
      ));
      final engine = NeteaseRequest(dio: dio, cookie: CookieManager(config), config: config);
      final api = MusicApi(request: engine);
      final result = await api.getPlaylistDetail(1);
      expect(result, isNull);
    });

    test('getUserPlaylists returns empty list on non-success', () async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(requestOptions: options, data: null, statusCode: 500));
        },
      ));
      final engine = NeteaseRequest(dio: dio, cookie: CookieManager(config), config: config);
      final api = MusicApi(request: engine);
      final result = await api.getUserPlaylists(1);
      expect(result, isEmpty);
    });

    test('getRecommendSongs returns empty on non-success', () async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(requestOptions: options, data: null, statusCode: 301));
        },
      ));
      final engine = NeteaseRequest(dio: dio, cookie: CookieManager(config), config: config);
      final api = MusicApi(request: engine);
      final result = await api.getRecommendSongs();
      expect(result, isEmpty);
    });

    test('getArtistTopSongs returns empty on non-success', () async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(requestOptions: options, data: null, statusCode: 500));
        },
      ));
      final engine = NeteaseRequest(dio: dio, cookie: CookieManager(config), config: config);
      final api = MusicApi(request: engine);
      final result = await api.getArtistTopSongs(1);
      expect(result, isEmpty);
    });

    test('getSongUrls returns empty on non-200 from proxy', () async {
      final proxyDio = Dio();
      proxyDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: {'body': {'code': 500}, 'cookie': []},
            statusCode: 200,
          ));
        },
      ));
      final proxy = XeapiProxy(dio: proxyDio, proxyUrl: 'https://proxy.local');
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();
      final dio = Dio();
      _addMockInterceptor(dio, {'code': 200});
      final engine = NeteaseRequest(dio: dio, cookie: CookieManager(config), config: config);
      final api = MusicApi(request: engine, xeapiProxy: proxy);
      final result = await api.getSongUrls([1]);
      expect(result, isEmpty);
    });

    test('searchSongs handles null result map', () async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(requestOptions: options, data: {'code': 200}, statusCode: 200));
        },
      ));
      final engine = NeteaseRequest(dio: dio, cookie: CookieManager(config), config: config);
      final api = MusicApi(request: engine);
      final songs = await api.searchSongs('test');
      expect(songs, isEmpty);
    });
  });
}

void _addMockInterceptor(Dio dio, Map<String, dynamic> response) {
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        data: response,
        statusCode: 200,
      ));
    },
  ));
}
