import 'dart:math';

import 'config.dart';
import 'crypto/constants.dart';

class CookieManager {
  final AppConfig _config;

  CookieManager(this._config);

  // ============================================================
  // Static Utilities (from util/index.js)
  // ============================================================

  static Map<String, String> cookieToJson(String cookie) {
    final obj = <String, String>{};
    final parts = cookie.split(';');
    for (final item in parts) {
      final eq = item.indexOf('=');
      if (eq > 0) {
        obj[item.substring(0, eq).trim()] = item.substring(eq + 1).trim();
      }
    }
    return obj;
  }

  static String cookieObjToString(Map<String, String> cookie) {
    final parts = <String>[];
    for (final entry in cookie.entries) {
      parts.add('${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}');
    }
    return parts.join('; ');
  }

  static String generateDeviceId() {
    const hexChars = '0123456789ABCDEF';
    final rng = Random.secure();
    return List.generate(52, (_) => hexChars[rng.nextInt(hexChars.length)]).join();
  }

  // ============================================================
  // OS Defaults (from util/request.js osMap)
  // ============================================================

  static const _osDefaults = <String, Map<String, String>>{
    'pc': {
      'os': 'pc',
      'appver': '3.1.17.204416',
      'osver': 'Microsoft-Windows-10-Professional-build-19045-64bit',
      'channel': 'netease',
    },
    'android': {
      'os': 'android',
      'appver': defaultAppver,
      'osver': defaultOsver,
      'channel': defaultChannel,
    },
    'iphone': {
      'os': 'iPhone OS',
      'appver': '9.0.90',
      'osver': '16.2',
      'channel': 'distribution',
    },
    'linux': {
      'os': 'linux',
      'appver': '1.2.1.0428',
      'osver': 'Deepin 20.9',
      'channel': 'netease',
    },
  };

  // ============================================================
  // Random Generators
  // ============================================================

  String _randomHex(int bytes) {
    final rng = Random.secure();
    return List.generate(bytes * 2, (_) => '0123456789abcdef'[rng.nextInt(16)]).join();
  }

  String _generateRequestId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = (Random.secure().nextInt(1000)).toString().padLeft(4, '0');
    return '${ts}_$rand';
  }

  String _buildver() {
    return DateTime.now().millisecondsSinceEpoch.toString().substring(0, 10);
  }

  // ============================================================
  // Cookie Processing (from util/request.js processCookieObject)
  // ============================================================

  Map<String, String> processCookie(Map<String, String> cookie, String uri) {
    final osProfile = _osDefaults[cookie['os']] ?? _osDefaults['pc']!;
    final freshNuid = _randomHex(32);

    final processed = Map<String, String>.from(cookie);
    processed['__remember_me'] = 'true';
    processed['ntes_kaola_ad'] = '1';
    processed.putIfAbsent('_ntes_nuid', () => freshNuid);
    processed.putIfAbsent('_ntes_nnid', () => '$freshNuid,${DateTime.now().millisecondsSinceEpoch}');
    processed.putIfAbsent('WNMCID', () => _config.wnmcid);
    processed.putIfAbsent('WEVNSM', () => '1.0.0');
    processed.putIfAbsent('osver', () => osProfile['osver']!);
    processed.putIfAbsent('deviceId', () => _config.deviceId);
    processed.putIfAbsent('os', () => osProfile['os']!);
    processed.putIfAbsent('channel', () => osProfile['channel']!);
    processed.putIfAbsent('appver', () => osProfile['appver']!);

    if (!uri.contains('login')) {
      processed.putIfAbsent('NMTID', () => _randomHex(16));
    }

    if ((processed['MUSIC_U'] ?? '').isEmpty) {
      if ((processed['MUSIC_A'] ?? '').isEmpty) {
        final a = _config.musicA;
        if (a != null && a.isNotEmpty) {
          processed['MUSIC_A'] = a;
        }
      }
    }

    return processed;
  }

  // ============================================================
  // EAPI/API Header Cookie (from util/request.js eapi branch)
  // ============================================================

  Map<String, String> buildEapiHeader(Map<String, String> cookie, String csrf) {
    final header = <String, String>{
      'osver': cookie['osver'] ?? defaultOsver,
      'deviceId': cookie['deviceId'] ?? _config.deviceId,
      'os': cookie['os'] ?? defaultPlatform,
      'appver': cookie['appver'] ?? defaultAppver,
      'versioncode': cookie['versioncode'] ?? defaultVersioncode,
      'mobilename': cookie['mobilename'] ?? defaultMobileName,
      'buildver': cookie['buildver'] ?? _buildver(),
      'resolution': cookie['resolution'] ?? defaultResolution,
      '__csrf': csrf,
      'channel': cookie['channel'] ?? defaultChannel,
      'requestId': cookie['requestId'] ?? _generateRequestId(),
    };

    final musicU = cookie['MUSIC_U'] ?? _config.musicU;
    if (musicU != null && musicU.isNotEmpty) {
      header['MUSIC_U'] = musicU;
    }
    final musicA = cookie['MUSIC_A'] ?? _config.musicA;
    if (musicA != null && musicA.isNotEmpty) {
      header['MUSIC_A'] = musicA;
    }

    return header;
  }

  // ============================================================
  // Header Cookie Serialization (from util/request.js createHeaderCookie)
  // ============================================================

  static String createHeaderCookie(Map<String, String> header) {
    final parts = <String>[];
    for (final entry in header.entries) {
      parts.add('${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}');
    }
    return parts.join('; ');
  }
}
