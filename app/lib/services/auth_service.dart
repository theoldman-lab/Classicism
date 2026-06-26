import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../api/auth_api.dart';
import '../core/config.dart';

class AuthService {
  final AuthApi _api;
  final AppConfig _config;

  AuthService({required AuthApi api, required AppConfig config})
      : _api = api,
        _config = config;

  // ============================================================
  // Initialization
  // ============================================================

  Future<void> initialize() async {
    await _config.init();

    if (_config.musicA == null || _config.musicA!.isEmpty) {
      await _api.registerAnonymous();
    }
  }

  // ============================================================
  // QR Login Polling
  // ============================================================

  Stream<QrCheckResult> pollLoginQr(String unikey) async* {
    while (true) {
      final result = await _api.checkLoginQr(unikey);
      yield result;

      if (result.isSuccess || result.isExpired) break;

      await Future.delayed(const Duration(seconds: 2));
    }
  }

  // ============================================================
  // Password Login
  // ============================================================

  Future<LoginResult> loginWithPassword(
    String phone,
    String password, {
    String countryCode = '86',
  }) async {
    final md5Password =
        crypto.md5.convert(utf8.encode(password)).toString();
    return _api.loginCellphone(
      phone: phone,
      md5Password: md5Password,
      countryCode: countryCode,
    );
  }

  // ============================================================
  // Logout
  // ============================================================

  Future<void> logout() async {
    await _config.setMusicU('');
    await _config.setCsrf('');
    await _config.setUid(0);
  }
}
