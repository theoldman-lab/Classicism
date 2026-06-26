import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:classicism/core/config.dart';
import 'package:classicism/core/cookie_manager.dart';

void main() {
  // ==========================================================
  // Static Utilities
  // ==========================================================
  group('CookieManager static utilities', () {
    group('cookieToJson', () {
      test('parses simple cookie string', () {
        final result =
            CookieManager.cookieToJson('MUSIC_A=xxx; os=pc; appver=1.0');
        expect(result['MUSIC_A'], 'xxx');
        expect(result['os'], 'pc');
        expect(result['appver'], '1.0');
        expect(result.length, 3);
      });

      test('handles empty string', () {
        final result = CookieManager.cookieToJson('');
        expect(result, isEmpty);
      });

      test('handles spaces around values', () {
        final result =
            CookieManager.cookieToJson(' MUSIC_U = abc ; __csrf = def ');
        expect(result['MUSIC_U'], 'abc');
        expect(result['__csrf'], 'def');
      });

      test('ignores malformed entries without =', () {
        final result = CookieManager.cookieToJson('a=b; malformed; c=d');
        expect(result['a'], 'b');
        expect(result['c'], 'd');
        expect(result.length, 2);
      });
    });

    group('cookieObjToString', () {
      test('serializes map to cookie string', () {
        final result =
            CookieManager.cookieObjToString({'MUSIC_A': 'xxx', 'os': 'pc'});
        expect(result, contains('MUSIC_A=xxx'));
        expect(result, contains('os=pc'));
      });

      test('encodes special characters', () {
        final result =
            CookieManager.cookieObjToString({'key': 'val ue', 'os': 'pc'});
        expect(result, contains('key=val%20ue'));
      });

      test('handles empty map', () {
        final result = CookieManager.cookieObjToString({});
        expect(result, '');
      });
    });

    group('generateDeviceId', () {
      test('returns 52 uppercase hex characters', () {
        final id = CookieManager.generateDeviceId();
        expect(id.length, 52);
        expect(RegExp(r'^[0-9A-F]{52}$').hasMatch(id), isTrue);
      });

      test('generates different values on each call', () {
        final id1 = CookieManager.generateDeviceId();
        final id2 = CookieManager.generateDeviceId();
        expect(id1, isNot(id2));
      });
    });
  });

  // ==========================================================
  // Instance Methods
  // ==========================================================
  group('CookieManager instance methods', () {
    late AppConfig config;
    late CookieManager manager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      config = AppConfig.instance;
      await config.init();
      manager = CookieManager(config);
    });

    group('processCookie', () {
      test('fills defaults for empty input cookie', () {
        final result = manager.processCookie({}, '/api/search/get');
        expect(result['__remember_me'], 'true');
        expect(result['ntes_kaola_ad'], '1');
        expect(result['deviceId'], config.deviceId);
        expect(result['WNMCID'], config.wnmcid);
        expect(result['WEVNSM'], '1.0.0');
        expect(result['os'], 'pc'); // default when os not specified
      });

      test('_ntes_nuid is 64 hex chars', () {
        final result = manager.processCookie({}, '/api/search/get');
        expect(result['_ntes_nuid']!.length, 64);
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(result['_ntes_nuid']!), isTrue);
      });

      test('_ntes_nnid starts with _ntes_nuid', () {
        final result = manager.processCookie({}, '/api/search/get');
        final nuid = result['_ntes_nuid']!;
        final nnid = result['_ntes_nnid']!;
        expect(nnid, startsWith('$nuid,'));
      });

      test('preserves existing cookie values', () {
        final result = manager.processCookie(
          {'os': 'android', 'MUSIC_U': 'my_token', 'MUSIC_A': 'anon_token'},
          '/api/search/get',
        );
        expect(result['os'], 'android');
        expect(result['MUSIC_U'], 'my_token');
        expect(result['MUSIC_A'], 'anon_token'); // preserved since MUSIC_U is present
      });

      test('uses android defaults when os=android', () {
        final result =
            manager.processCookie({'os': 'android'}, '/api/search/get');
        expect(result['os'], 'android');
        expect(result['appver'], '8.20.20.231215173437');
        expect(result['osver'], '14');
        expect(result['channel'], 'xiaomi');
      });

      test('uses iphone defaults when os=iphone', () {
        final result =
            manager.processCookie({'os': 'iphone'}, '/api/search/get');
        expect(result['os'], 'iphone');
        expect(result['appver'], '9.0.90');
        expect(result['osver'], '16.2');
        expect(result['channel'], 'distribution');
      });

      test('adds NMTID for non-login URIs', () {
        final result =
            manager.processCookie({}, '/api/search/get');
        expect(result.containsKey('NMTID'), isTrue);
        expect(result['NMTID']!.length, 32);
        expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(result['NMTID']!), isTrue);
      });

      test('skips NMTID for login URIs', () {
        final result =
            manager.processCookie({}, '/api/login/cellphone');
        expect(result.containsKey('NMTID'), isFalse);
      });

      test('fills MUSIC_A from config when MUSIC_U absent', () async {
        await config.setMusicA('my_anon_token');
        final result = manager.processCookie({}, '/api/search/get');
        expect(result['MUSIC_A'], 'my_anon_token');
      });

      test('does not set MUSIC_A when MUSIC_U is present', () async {
        await config.setMusicA('anon_token');
        final result = manager.processCookie(
          {'MUSIC_U': 'user_token'},
          '/api/search/get',
        );
        expect(result['MUSIC_U'], 'user_token');
        expect(result['MUSIC_A'], isNull); // not added since MUSIC_U exists
      });

      test('preserves existing MUSIC_A even when MUSIC_U absent', () {
        final result = manager.processCookie(
          {'MUSIC_A': 'existing_anon'},
          '/api/search/get',
        );
        expect(result['MUSIC_A'], 'existing_anon');
      });
    });

    group('buildEapiHeader', () {
      test('builds header with android defaults', () {
        final header = manager.buildEapiHeader({}, 'csrf123');
        expect(header['os'], 'android');
        expect(header['appver'], '8.20.20.231215173437');
        expect(header['osver'], '14');
        expect(header['channel'], 'xiaomi');
        expect(header['deviceId'], config.deviceId);
        expect(header['__csrf'], 'csrf123');
        expect(header['resolution'], '1920x1080');
        expect(header['versioncode'], '140');
        expect(header.containsKey('requestId'), isTrue);
        expect(header.containsKey('buildver'), isTrue);
      });

      test('includes MUSIC_U and MUSIC_A when available', () async {
        await config.setMusicU('user123');
        await config.setMusicA('anon456');
        final header = manager.buildEapiHeader({}, 'csrf');
        expect(header['MUSIC_U'], 'user123');
        expect(header['MUSIC_A'], 'anon456');
      });

      test('preserves cookie values', () {
        final header = manager.buildEapiHeader(
          {'os': 'iPhone OS', 'MUSIC_U': 'u', 'MUSIC_A': 'a'},
          'csrf',
        );
        expect(header['os'], 'iPhone OS');
        expect(header['MUSIC_U'], 'u');
        expect(header['MUSIC_A'], 'a');
      });
    });

    group('createHeaderCookie', () {
      test('serializes header map', () {
        final str = CookieManager.createHeaderCookie({
          'os': 'android',
          'deviceId': 'ABC123',
        });
        expect(str, contains('os=android'));
        expect(str, contains('deviceId=ABC123'));
      });

      test('encodes special characters', () {
        final str = CookieManager.createHeaderCookie({'key': 'val ue'});
        expect(str, contains('key=val%20ue'));
      });
    });
  });
}
