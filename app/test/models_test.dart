import 'package:flutter_test/flutter_test.dart';

import 'package:classicism/models/song.dart';
import 'package:classicism/models/lyric.dart';
import 'package:classicism/models/playlist.dart';
import 'package:classicism/models/search_result.dart';
import 'package:classicism/models/user.dart';

void main() {
  // ==========================================================
  // Song
  // ==========================================================
  group('Song.fromJson', () {
    test('parses complete song', () {
      final song = Song.fromJson({
        'id': 123,
        'name': 'Test Song',
        'dt': 240000,
        'fee': 1,
        'ar': [
          {'id': 1, 'name': 'Artist1'},
          {'id': 2, 'name': 'Artist2'},
        ],
        'al': {'id': 10, 'name': 'Album', 'picUrl': 'http://img.url'},
      });
      expect(song.id, 123);
      expect(song.name, 'Test Song');
      expect(song.duration, 240000);
      expect(song.fee, 1);
      expect(song.artistName, 'Artist1'); // first artist
      expect(song.albumName, 'Album');
      expect(song.coverUrl, 'http://img.url');
    });

    test('name null falls to empty string', () {
      final song = Song.fromJson({'id': 1, 'dt': 100});
      expect(song.name, '');
    });

    test('empty ar array produces null artistName', () {
      final song = Song.fromJson({'id': 1, 'name': 'x', 'dt': 100, 'ar': []});
      expect(song.artistName, isNull);
    });

    test('ar absent produces null artistName', () {
      final song = Song.fromJson({'id': 1, 'name': 'x', 'dt': 100});
      expect(song.artistName, isNull);
    });

    test('ar first item missing name', () {
      final song = Song.fromJson({
        'id': 1,
        'name': 'x',
        'dt': 100,
        'ar': [{'id': 1}],
      });
      expect(song.artistName, isNull);
    });

    test('al null produces null album fields', () {
      final song = Song.fromJson({'id': 1, 'name': 'x', 'dt': 100});
      expect(song.albumName, isNull);
      expect(song.coverUrl, isNull);
    });

    test('al without picUrl produces null coverUrl', () {
      final song = Song.fromJson({
        'id': 1,
        'name': 'x',
        'dt': 100,
        'al': {'name': 'AlbumOnly'},
      });
      expect(song.albumName, 'AlbumOnly');
      expect(song.coverUrl, isNull);
    });

    test('duration null defaults to 0', () {
      final song = Song.fromJson({'id': 1, 'name': 'x'});
      expect(song.duration, 0);
    });

    test('fee null defaults to 0', () {
      final song = Song.fromJson({'id': 1, 'name': 'x', 'dt': 100});
      expect(song.fee, 0);
    });

    test('direct constructor', () {
      final song = Song(id: 1, name: 'Direct', duration: 100);
      expect(song.id, 1);
      expect(song.fee, 0);
      expect(song.artistName, isNull);
    });
  });

  // ==========================================================
  // Lyric
  // ==========================================================
  group('Lyric.fromJson', () {
    test('parses complete lyric with translation', () {
      final lyric = Lyric.fromJson({
        'lrc': {'version': 1, 'lyric': '[00:01.00]hello'},
        'tlyric': {'version': 1, 'lyric': '[00:01.00]你好'},
      });
      expect(lyric.lrc, '[00:01.00]hello');
      expect(lyric.tlyric, '[00:01.00]你好');
    });

    test('missing lrc key defaults to empty string', () {
      final lyric = Lyric.fromJson({});
      expect(lyric.lrc, '');
      expect(lyric.tlyric, isNull);
    });

    test('lrc present but lyric string is null', () {
      final lyric = Lyric.fromJson({
        'lrc': <String, dynamic>{},
      });
      expect(lyric.lrc, '');
    });

    test('missing tlyric returns null', () {
      final lyric = Lyric.fromJson({
        'lrc': {'lyric': 'test'},
      });
      expect(lyric.lrc, 'test');
      expect(lyric.tlyric, isNull);
    });

    test('tlyric present but lyric string is null', () {
      final lyric = Lyric.fromJson({
        'lrc': <String, dynamic>{'lyric': 'test'},
        'tlyric': <String, dynamic>{},
      });
      expect(lyric.tlyric, isNull);
    });

    test('direct constructor', () {
      final lyric = Lyric(lrc: 'hello', tlyric: 'trans');
      expect(lyric.lrc, 'hello');
      expect(lyric.tlyric, 'trans');
    });
  });

  // ==========================================================
  // Playlist
  // ==========================================================
  group('Playlist.fromJson', () {
    test('parses complete playlist', () {
      final playlist = Playlist.fromJson({
        'id': 456,
        'name': 'My Playlist',
        'coverImgUrl': 'http://cover.img',
        'trackCount': 99,
        'playCount': 10000,
        'creator': {'userId': 1, 'nickname': 'CreatorX'},
      });
      expect(playlist.id, 456);
      expect(playlist.name, 'My Playlist');
      expect(playlist.coverImgUrl, 'http://cover.img');
      expect(playlist.trackCount, 99);
      expect(playlist.playCount, 10000);
      expect(playlist.creatorName, 'CreatorX');
    });

    test('name null falls to empty string', () {
      final playlist = Playlist.fromJson({'id': 1});
      expect(playlist.name, '');
    });

    test('missing creator produces null creatorName', () {
      final playlist = Playlist.fromJson({'id': 1, 'name': 'x'});
      expect(playlist.creatorName, isNull);
    });

    test('creator without nickname', () {
      final playlist = Playlist.fromJson({
        'id': 1,
        'name': 'x',
        'creator': {'userId': 1},
      });
      expect(playlist.creatorName, isNull);
    });

    test('trackCount and playCount null default to 0', () {
      final playlist = Playlist.fromJson({'id': 1, 'name': 'x'});
      expect(playlist.trackCount, 0);
      expect(playlist.playCount, 0);
    });

    test('coverImgUrl null', () {
      final playlist = Playlist.fromJson({'id': 1, 'name': 'x'});
      expect(playlist.coverImgUrl, isNull);
    });

    test('direct constructor', () {
      final playlist = Playlist(id: 1, name: 'Direct', trackCount: 5);
      expect(playlist.trackCount, 5);
      expect(playlist.playCount, 0);
    });
  });

  // ==========================================================
  // User
  // ==========================================================
  group('User', () {
    test('direct constructor', () {
      final user = User(userId: 1, nickname: 'Test');
      expect(user.userId, 1);
      expect(user.nickname, 'Test');
    });
  });

  // ==========================================================
  // SearchResult
  // ==========================================================
  group('SearchResult', () {
    test('direct constructor', () {
      final result = SearchResult(songs: [1, 2, 3], songCount: 3);
      expect(result.songs.length, 3);
      expect(result.songCount, 3);
    });

    test('empty result', () {
      final result = SearchResult(songs: [], songCount: 0);
      expect(result.songs, isEmpty);
      expect(result.songCount, 0);
    });
  });
}
