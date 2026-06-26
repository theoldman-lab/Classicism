import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../core/crypto/constants.dart';
import '../core/crypto/xeapi_helpers.dart';
import '../core/request_engine.dart';
import 'xeapi_proxy.dart';

// ============================================================
// Models
// ============================================================

class XeapiKeyState {
  final String sk;
  final int expireTime;
  final int version;
  final String nonce;

  XeapiKeyState({
    required this.sk,
    required this.expireTime,
    required this.version,
    required this.nonce,
  });

  factory XeapiKeyState.fromJson(Map<String, dynamic> json) {
    return XeapiKeyState(
      sk: json['sk'] as String,
      expireTime: json['expireTime'] as int,
      version: json['version'] as int,
      nonce: json['nonce'] as String? ?? '',
    );
  }
}

class QrCheckResult {
  final int code;
  final String? cookie;

  QrCheckResult({required this.code, this.cookie});

  bool get isExpired => code == 800;
  bool get isWaiting => code == 801;
  bool get isScanned => code == 802;
  bool get isSuccess => code == 803;
}

class LoginResult {
  final int code;
  final String? cookie;
  final Map<String, dynamic>? profile;

  LoginResult({required this.code, this.cookie, this.profile});

  bool get isSuccess => code == 200;
}

// ============================================================
// AuthApi
// ============================================================

class AuthApi {
  final NeteaseRequest _request;
  final Dio _directDio;
  final XeapiProxy? _xeapiProxy;
  final AppConfig _config;

  static const _xorKey = '3go8\u0026\u00248*3*3h0k(2)2';

  static const _androidUa =
      'NeteaseMusic/9.1.65.240927161425(9001065);Dalvik/2.1.0 (Linux; U; Android 14; 23013RK75C Build/UKQ1.230804.001)';

  AuthApi({
    required NeteaseRequest request,
    required Dio directDio,
    required AppConfig config,
    XeapiProxy? xeapiProxy,
  })  : _request = request,
        _directDio = directDio,
        _config = config,
        _xeapiProxy = xeapiProxy;

  // ============================================================
  // Anonymous Registration [xeapi → cloud function]
  // ============================================================

  Future<String> registerAnonymous() async {
    if (_xeapiProxy == null) {
      throw UnimplementedError(
        'XEAPI cloud function URL not configured',
      );
    }

    final deviceId = _config.deviceId;
    final username = buildAnonUsername(deviceId);

    final result = await _xeapiProxy.call(
      '/api/register/anonimous',
      {'username': username},
      'deviceId=${Uri.encodeComponent(deviceId)}',
    );

    if (result.body['code'] != 200) {
      throw Exception('registerAnonymous failed: ${result.body}');
    }

    final cookieStr = result.body['cookie'] as String? ??
        result.cookies.join(';');

    if (cookieStr.isNotEmpty) {
      final parsed = _parseCookies(cookieStr);
      final musicA = parsed['MUSIC_A'];
      if (musicA != null) {
        await _config.setMusicA(musicA);
        return musicA;
      }
    }

    if (result.cookies.isNotEmpty) {
      for (final c in result.cookies) {
        final parsed = _parseCookies(c);
        final musicA = parsed['MUSIC_A'];
        if (musicA != null) {
          await _config.setMusicA(musicA);
          return musicA;
        }
      }
    }

    throw Exception('MUSIC_A not found in registerAnonymous response');
  }

  // ============================================================
  // X25519 Public Key [special direct API]
  // ============================================================

  Future<XeapiKeyState> getXeapiPublicKey({
    String currentKeyVersion = '',
  }) async {
    final nonce = List.generate(16, (_) => Random.secure().nextInt(10)).join();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final deviceId = _config.deviceId;

    final data = {
      'appVersion': '9.1.65',
      'currentKeyVersion': currentKeyVersion,
      'deviceId': deviceId,
      'nonce': nonce,
      'os': 'android',
      'requestType': 'active',
      'signature': xeapiSign(timestamp, nonce),
      't1': '',
      't2': '',
      'timestamp': timestamp,
      'uid': '',
    };

    final response = await _directDio.post(
      '$apiDomain/api/gorilla/anti/crawler/security/key/get',
      data: data,
      options: Options(
        headers: {
          'User-Agent': _androidUa,
          'Cookie': 'deviceId=${Uri.encodeComponent(deviceId)}',
        },
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
      ),
    );

    final body = response.data as Map<String, dynamic>;
    if (body['code'] != 200) {
      throw Exception('getXeapiPublicKey failed: $body');
    }

    final respData = body['data'] as Map<String, dynamic>;
    final encryptedData = respData['encryptedData'] as String;
    final serverSignature = respData['signature'] as String;
    final serverTimestamp = respData['timestamp'].toString();

    final expectedSig = xeapiSign(serverTimestamp, nonce);
    if (expectedSig != serverSignature) {
      throw Exception('xeapi public key response signature mismatch');
    }

    final keyData = xeapiDecryptPublicKey(encryptedData);

    return XeapiKeyState.fromJson({
      ...keyData,
      'nonce': nonce,
    });
  }

  // ============================================================
  // QR Login — Get Key [eapi]
  // ============================================================

  Future<String> getLoginQrKey() async {
    final response = await _request.request(
      '/api/login/qrcode/unikey',
      {'type': 3},
      crypto: Crypto.eapi,
    );

    if (response.isSuccess && response.body is Map) {
      final data = response.body['data'] as Map<String, dynamic>?;
      if (data != null && data['unikey'] != null) {
        return data['unikey'] as String;
      }
    }

    throw Exception('Failed to get QR login key: ${response.body}');
  }

  // ============================================================
  // QR Login — Check Status [eapi]
  // ============================================================

  Future<QrCheckResult> checkLoginQr(String unikey) async {
    final response = await _request.request(
      '/api/login/qrcode/client/login',
      {'key': unikey, 'type': 3},
      crypto: Crypto.eapi,
    );

    final code = response.body is Map
        ? (response.body['code'] as int?) ?? 801
        : 801;

    String? cookie;
    if (code == 803 && response.cookies.isNotEmpty) {
      cookie = response.cookies.join('; ');
      await _persistCookiesFromResponse(cookie);
    }

    return QrCheckResult(code: code, cookie: cookie);
  }

  // ============================================================
  // Phone Login [weapi]
  // ============================================================

  Future<LoginResult> loginCellphone({
    required String phone,
    required String md5Password,
    String? captcha,
    String countryCode = '86',
  }) async {
    final data = <String, dynamic>{
      'type': '1',
      'https': 'true',
      'phone': phone,
      'countrycode': countryCode,
      'remember': 'true',
    };

    if (captcha != null) {
      data['captcha'] = captcha;
    } else {
      data['password'] = md5Password;
    }

    final response = await _request.request(
      '/api/w/login/cellphone',
      data,
      crypto: Crypto.weapi,
    );

    final body = response.body as Map<String, dynamic>? ?? {};
    final code = body['code'] as int? ?? 500;
    String? cookie;

    if (code == 200 && response.cookies.isNotEmpty) {
      cookie = response.cookies.join('; ');
      await _persistCookiesFromResponse(cookie);
    }

    return LoginResult(
      code: code,
      cookie: cookie,
      profile: body['profile'] as Map<String, dynamic>?,
    );
  }

  // ============================================================
  // Login Status [weapi]
  // ============================================================

  Future<Map<String, dynamic>?> loginStatus() async {
    final response = await _request.request(
      '/api/w/nuser/account/get',
      {},
      crypto: Crypto.weapi,
    );

    if (response.isSuccess && response.body is Map) {
      return response.body as Map<String, dynamic>;
    }

    return null;
  }

  // ============================================================
  // Refresh Token [eapi]
  // ============================================================

  Future<String?> refreshToken() async {
    final response = await _request.request(
      '/api/login/token/refresh',
      {},
      crypto: Crypto.eapi,
    );

    if (response.isSuccess && response.cookies.isNotEmpty) {
      final cookie = response.cookies.join('; ');
      await _persistCookiesFromResponse(cookie);
      return cookie;
    }

    return null;
  }

  // ============================================================
  // Visible for Testing
  // ============================================================

  @visibleForTesting
  static String cloudmusicDllEncodeId(String id) {
    final xoredCodes = <int>[];
    for (int i = 0; i < id.length; i++) {
      final charCode =
          id.codeUnitAt(i) ^ _xorKey.codeUnitAt(i % _xorKey.length);
      xoredCodes.add(charCode);
    }
    final xoredString = String.fromCharCodes(xoredCodes);
    final digest = crypto.md5.convert(utf8.encode(xoredString));
    return base64.encode(digest.bytes);
  }

  @visibleForTesting
  static String buildAnonUsername(String deviceId) {
    final encoded = '$deviceId ${cloudmusicDllEncodeId(deviceId)}';
    return base64.encode(utf8.encode(encoded));
  }

  Map<String, String> _parseCookies(String cookieStr) {
    final map = <String, String>{};
    for (final part in cookieStr.split(';')) {
      final eq = part.indexOf('=');
      if (eq > 0) {
        map[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
      }
    }
    return map;
  }

  Future<void> _persistCookiesFromResponse(String cookieStr) async {
    final cookies = _parseCookies(cookieStr);
    final musicU = cookies['MUSIC_U'];
    final csrf = cookies['__csrf'];

    if (musicU != null && musicU.isNotEmpty) {
      await _config.setMusicU(musicU);
    }
    if (csrf != null && csrf.isNotEmpty) {
      await _config.setCsrf(csrf);
    }
  }
}
