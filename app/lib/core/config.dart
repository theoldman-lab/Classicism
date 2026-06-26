import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  AppConfig._();

  static final AppConfig instance = AppConfig._();

  SharedPreferences? _prefs;

  // Persistent keys
  static const _keyDeviceId = 'deviceId';
  static const _keyMusicA = 'MUSIC_A';
  static const _keyMusicU = 'MUSIC_U';
  static const _keyCsrf = '__csrf';
  static const _keyUid = 'uid';

  // Generated per init() call
  late String wnmcid;

  String? _deviceId;
  String? _musicA;
  String? _musicU;
  String? _csrf;
  int? _uid;

  bool get _isReady => _prefs != null;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    _deviceId = _prefs!.getString(_keyDeviceId);
    if (_deviceId == null) {
      _deviceId = _generateDeviceId();
      await _prefs!.setString(_keyDeviceId, _deviceId!);
    }

    _musicA = _prefs!.getString(_keyMusicA);
    _musicU = _prefs!.getString(_keyMusicU);
    _csrf = _prefs!.getString(_keyCsrf);
    _uid = _prefs!.getInt(_keyUid);

    wnmcid = _generateWnmcid();
  }

  String get deviceId {
    _ensureReady();
    return _deviceId!;
  }

  String? get musicA {
    _ensureReady();
    return _musicA;
  }

  String? get musicU {
    _ensureReady();
    return _musicU;
  }

  String? get csrf {
    _ensureReady();
    return _csrf;
  }

  int? get uid {
    _ensureReady();
    return _uid;
  }

  Future<void> setMusicA(String value) async {
    _ensureReady();
    _musicA = value;
    await _prefs!.setString(_keyMusicA, value);
  }

  Future<void> setMusicU(String value) async {
    _ensureReady();
    _musicU = value;
    await _prefs!.setString(_keyMusicU, value);
  }

  Future<void> setCsrf(String value) async {
    _ensureReady();
    _csrf = value;
    await _prefs!.setString(_keyCsrf, value);
  }

  Future<void> setUid(int value) async {
    _ensureReady();
    _uid = value;
    await _prefs!.setInt(_keyUid, value);
  }

  void _ensureReady() {
    if (!_isReady) {
      throw StateError('AppConfig not initialized. Call init() first.');
    }
  }

  static String _generateDeviceId() {
    const hexChars = '0123456789ABCDEF';
    final rng = Random.secure();
    final chars = List.generate(52, (_) => hexChars[rng.nextInt(hexChars.length)]);
    return chars.join();
  }

  static String _generateWnmcid() {
    const chars = 'abcdefghijklmnopqrstuvwxyz';
    final rng = Random.secure();
    final randomPart = List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '$randomPart.$ts.01.0';
  }
}
