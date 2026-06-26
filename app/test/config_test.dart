import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:classicism/core/config.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppConfig.init', () {
    test('generates and persists deviceId on first init', () async {
      final config = AppConfig.instance;
      await config.init();

      expect(config.deviceId, isNotEmpty);
      expect(config.deviceId.length, 52);
      expect(RegExp(r'^[0-9A-F]{52}$').hasMatch(config.deviceId), isTrue);
    });

    test('reuses existing deviceId across inits', () async {
      final config = AppConfig.instance;
      await config.init();
      final id1 = config.deviceId;

      // Re-init
      await config.init();
      final id2 = config.deviceId;

      expect(id1, id2);
    });

    test('reuses deviceId from SharedPreferences across instances', () async {
      SharedPreferences.setMockInitialValues({
        'deviceId': 'ABCD1234ABCD1234ABCD1234ABCD1234ABCD1234ABCD1234ABCD12',
      });
      final config = AppConfig.instance;
      await config.init();

      expect(config.deviceId,
          'ABCD1234ABCD1234ABCD1234ABCD1234ABCD1234ABCD1234ABCD12');
    });

    test('generates wnmcid with correct format', () async {
      final config = AppConfig.instance;
      await config.init();

      expect(config.wnmcid, isNotEmpty);
      // Format: 6 lowercase letters . timestamp . 01.0
      expect(
        RegExp(r'^[a-z]{6}\.\d+\.01\.0$').hasMatch(config.wnmcid),
        isTrue,
      );
    });

    test('loads persisted MUSIC_A', () async {
      SharedPreferences.setMockInitialValues({'MUSIC_A': 'anon_123'});
      final config = AppConfig.instance;
      await config.init();

      expect(config.musicA, 'anon_123');
    });

    test('loads persisted MUSIC_U', () async {
      SharedPreferences.setMockInitialValues({'MUSIC_U': 'user_456'});
      final config = AppConfig.instance;
      await config.init();

      expect(config.musicU, 'user_456');
    });

    test('loads persisted csrf and uid', () async {
      SharedPreferences.setMockInitialValues({
        '__csrf': 'csrf_token',
        'uid': 999,
      });
      final config = AppConfig.instance;
      await config.init();

      expect(config.csrf, 'csrf_token');
      expect(config.uid, 999);
    });

    test('loads all persisted values together', () async {
      SharedPreferences.setMockInitialValues({
        'deviceId': 'DEVICE${'0' * 46}',
        'MUSIC_A': 'a_token',
        'MUSIC_U': 'u_token',
        '__csrf': 'c_token',
        'uid': 42,
      });
      final config = AppConfig.instance;
      await config.init();

      expect(config.deviceId, startsWith('DEVICE'));
      expect(config.musicA, 'a_token');
      expect(config.musicU, 'u_token');
      expect(config.csrf, 'c_token');
      expect(config.uid, 42);
    });
  });

  group('AppConfig getters with pre-seeded values', () {
    test('returns null when no values persisted', () async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      expect(config.musicA, isNull);
      expect(config.musicU, isNull);
      expect(config.csrf, isNull);
      expect(config.uid, isNull);
    });
  });

  group('AppConfig persistence', () {
    test('setMusicA persists and reads back', () async {
      final config = AppConfig.instance;
      await config.init();

      await config.setMusicA('new_anon');
      expect(config.musicA, 'new_anon');

      // Read back after re-init
      await config.init();
      expect(config.musicA, 'new_anon');
    });

    test('setMusicU persists and reads back', () async {
      final config = AppConfig.instance;
      await config.init();

      await config.setMusicU('user_token');
      expect(config.musicU, 'user_token');

      await config.init();
      expect(config.musicU, 'user_token');
    });

    test('setCsrf persists and reads back', () async {
      final config = AppConfig.instance;
      await config.init();

      await config.setCsrf('csrf_123');
      expect(config.csrf, 'csrf_123');

      await config.init();
      expect(config.csrf, 'csrf_123');
    });

    test('setUid persists and reads back', () async {
      final config = AppConfig.instance;
      await config.init();

      await config.setUid(12345);
      expect(config.uid, 12345);

      await config.init();
      expect(config.uid, 12345);
    });

    test('setUid(0) — zero is valid uid', () async {
      final config = AppConfig.instance;
      await config.init();

      await config.setUid(0);
      expect(config.uid, 0);

      await config.init();
      expect(config.uid, 0);
    });

    test('setMusicU empty string persists', () async {
      final config = AppConfig.instance;
      await config.init();
      await config.setMusicU('token');
      await config.setMusicU('');
      expect(config.musicU, '');

      await config.init();
      expect(config.musicU, '');
    });
  });
}
