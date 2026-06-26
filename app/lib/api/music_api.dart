import '../core/crypto/constants.dart';
import '../core/request_engine.dart';
import '../models/lyric.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import 'xeapi_proxy.dart';

class MusicApi {
  final NeteaseRequest _request;
  final XeapiProxy? _xeapiProxy;

  MusicApi({required NeteaseRequest request, XeapiProxy? xeapiProxy})
      : _request = request,
        _xeapiProxy = xeapiProxy;

  // ============================================================
  // Search [eapi]
  // ============================================================

  Future<Map<String, dynamic>> search(
    String keywords, {
    int type = 1,
    int limit = 30,
    int offset = 0,
  }) async {
    final response = await _request.request(
      '/api/search/get',
      {
        's': keywords,
        'type': type,
        'limit': limit,
        'offset': offset,
      },
      crypto: Crypto.eapi,
    );

    return response.body as Map<String, dynamic>? ?? {};
  }

  // ============================================================
  // Search Songs (convenience)
  // ============================================================

  Future<List<Song>> searchSongs(
    String keywords, {
    int limit = 30,
    int offset = 0,
  }) async {
    final body = await search(keywords, type: 1, limit: limit, offset: offset);
    final result = body['result'] as Map<String, dynamic>?;
    final songsJson = result?['songs'] as List<dynamic>? ?? [];
    return songsJson
        .map((s) => Song.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  // ============================================================
  // Search Playlists (convenience)
  // ============================================================

  Future<List<Playlist>> searchPlaylists(
    String keywords, {
    int limit = 30,
    int offset = 0,
  }) async {
    final body =
        await search(keywords, type: 1000, limit: limit, offset: offset);
    final result = body['result'] as Map<String, dynamic>?;
    final playlistsJson = result?['playlists'] as List<dynamic>? ?? [];
    return playlistsJson
        .map((p) => Playlist.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  // ============================================================
  // Song URLs [xeapi → cloud function]
  // ============================================================

  Future<List<Map<String, dynamic>>> getSongUrls(
    List<int> ids, {
    String level = 'exhigh',
  }) async {
    final proxy = _xeapiProxy;
    if (proxy == null) {
      throw UnimplementedError(
        'XEAPI cloud function URL not configured',
      );
    }

    final data = <String, dynamic>{
      'ids': '[${ids.join(',')}]',
      'level': level,
      'encodeType': 'flac',
    };

    if (level == 'sky') {
      data['immerseType'] = 'c51';
    }

    final result = await proxy.call(
      '/api/song/enhance/player/url/v1',
      data,
      '', // cookie handled by cloud function
    );

    final body = result.body;
    if (body['code'] != 200) {
      return [];
    }

    return (body['data'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
  }

  // ============================================================
  // Lyric [eapi]
  // ============================================================

  Future<Lyric?> getLyric(int songId) async {
    final response = await _request.request(
      '/api/song/lyric',
      {
        'id': songId,
        'tv': -1,
        'lv': -1,
        'rv': -1,
        'kv': -1,
        '_nmclfl': 1,
      },
      crypto: Crypto.eapi,
    );

    if (!response.isSuccess || response.body is! Map) return null;

    final body = response.body as Map<String, dynamic>;
    if (body['code'] != 200) return null;

    return Lyric.fromJson(body);
  }

  // ============================================================
  // Song Detail [weapi]
  // ============================================================

  Future<List<Song>> getSongDetail(List<int> ids) async {
    final c = '[${ids.map((id) => '{"id":$id}').join(',')}]';

    final response = await _request.request(
      '/api/v3/song/detail',
      {'c': c},
      crypto: Crypto.weapi,
    );

    if (!response.isSuccess || response.body is! Map) return [];

    final body = response.body as Map<String, dynamic>;
    final songsJson = body['songs'] as List<dynamic>? ?? [];
    return songsJson
        .map((s) => Song.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  // ============================================================
  // Playlist Detail [eapi]
  // ============================================================

  Future<Playlist?> getPlaylistDetail(int playlistId, {int s = 8}) async {
    final response = await _request.request(
      '/api/v6/playlist/detail',
      {
        'id': playlistId,
        'n': 100000,
        's': s,
      },
      crypto: Crypto.eapi,
    );

    if (!response.isSuccess || response.body is! Map) return null;

    final body = response.body as Map<String, dynamic>;
    if (body['code'] != 200) return null;

    final playlistJson = body['playlist'] as Map<String, dynamic>?;
    if (playlistJson == null) return null;

    return Playlist.fromJson(playlistJson);
  }

  // ============================================================
  // User Playlists [weapi]
  // ============================================================

  Future<List<Playlist>> getUserPlaylists(
    int userId, {
    int limit = 30,
    int offset = 0,
  }) async {
    final response = await _request.request(
      '/api/user/playlist',
      {
        'uid': userId,
        'limit': limit,
        'offset': offset,
        'includeVideo': true,
      },
      crypto: Crypto.weapi,
    );

    if (!response.isSuccess || response.body is! Map) return [];

    final body = response.body as Map<String, dynamic>;
    final playlistsJson = body['playlist'] as List<dynamic>? ?? [];
    return playlistsJson
        .map((p) => Playlist.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  // ============================================================
  // Daily Recommend Songs [weapi] — requires login
  // ============================================================

  Future<List<Song>> getRecommendSongs() async {
    final response = await _request.request(
      '/api/v3/discovery/recommend/songs',
      {},
      crypto: Crypto.weapi,
    );

    if (!response.isSuccess || response.body is! Map) return [];

    final body = response.body as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>?;
    final songsJson = data?['dailySongs'] as List<dynamic>? ?? [];
    return songsJson
        .map((s) => Song.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  // ============================================================
  // Album [weapi]
  // ============================================================

  Future<Map<String, dynamic>> getAlbum(int albumId) async {
    final response = await _request.request(
      '/api/v1/album/$albumId',
      {},
      crypto: Crypto.weapi,
    );

    return response.body as Map<String, dynamic>? ?? {};
  }

  // ============================================================
  // Artist Top Songs [weapi]
  // ============================================================

  Future<List<Song>> getArtistTopSongs(int artistId) async {
    final response = await _request.request(
      '/api/artist/top/song',
      {'id': artistId},
      crypto: Crypto.weapi,
    );

    if (!response.isSuccess || response.body is! Map) return [];

    final body = response.body as Map<String, dynamic>;
    final songsJson = body['songs'] as List<dynamic>? ?? [];
    return songsJson
        .map((s) => Song.fromJson(s as Map<String, dynamic>))
        .toList();
  }
}
