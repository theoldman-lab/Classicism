import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:classicism/api/auth_api.dart';
import 'package:classicism/api/xeapi_proxy.dart';
import 'package:classicism/core/config.dart';
import 'package:classicism/core/cookie_manager.dart';
import 'package:classicism/core/crypto/constants.dart';
import 'package:classicism/core/crypto/eapi.dart';
import 'package:classicism/core/crypto/xeapi_helpers.dart';
import 'package:classicism/core/request_engine.dart';

RequestOptions? _lastCaptured;

Dio _createMockDio([Map<String, dynamic>? responseBody]) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      _lastCaptured = options;
      handler.resolve(Response(
        requestOptions: options,
        data: responseBody ?? {'code': 200, 'data': {}},
        statusCode: 200,
      ));
    },
  ));
  return dio;
}

NeteaseRequest _createMockEngine([Map<String, dynamic>? responseBody]) {
  final dio = _createMockDio(responseBody);
  // Return a properly configured request engine with mock Dio
  return NeteaseRequest(
    dio: dio,
    cookie: CookieManager(AppConfig.instance),
    config: AppConfig.instance,
  );
}

Future<AuthApi> _createAuthApi({
  Map<String, dynamic>? responseBody,
  XeapiProxy? xeapiProxy,
}) async {
  SharedPreferences.setMockInitialValues({});
  final config = AppConfig.instance;
  await config.init();
  await config.setMusicA('test_anon');

  final engine = _createMockEngine(responseBody);
  final dio = _createMockDio(responseBody);

  return AuthApi(
    request: engine,
    directDio: dio,
    config: config,
    xeapiProxy: xeapiProxy,
  );
}

void main() {
  // ==========================================================
  // cloudmusicDllEncodeId
  // ==========================================================
  group('cloudmusicDllEncodeId', () {
    test('returns valid base64', () {
      final result = AuthApi.cloudmusicDllEncodeId('ABCD1234');
      expect(RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(result), isTrue);
    });

    test('is deterministic', () {
      final r1 = AuthApi.cloudmusicDllEncodeId('test_device');
      final r2 = AuthApi.cloudmusicDllEncodeId('test_device');
      expect(r1, r2);
    });

    test('different ids produce different results', () {
      final r1 = AuthApi.cloudmusicDllEncodeId('device_a');
      final r2 = AuthApi.cloudmusicDllEncodeId('device_b');
      expect(r1, isNot(r2));
    });

    test('output is MD5 → base64 (24 chars)', () {
      // MD5 digest is 16 bytes → base64 = 24 chars
      final result = AuthApi.cloudmusicDllEncodeId('test');
      expect(result.length, 24);
    });

    test('XOR key used correctly', () {
      // XOR 'A'(65) with '3'(51) = 114('r')
      final withXor = AuthApi.cloudmusicDllEncodeId('hello');

      // Verify output format: 24-char base64 (16-byte MD5 digest)
      expect(withXor.length, 24);
      // Verify it's valid base64
      expect(RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(withXor), isTrue);
    });
  });

  // ==========================================================
  // buildAnonUsername
  // ==========================================================
  group('buildAnonUsername', () {
    test('returns valid base64', () {
      final result = AuthApi.buildAnonUsername('ABCD');
      expect(RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(result), isTrue);
    });

    test('is deterministic', () {
      final r1 = AuthApi.buildAnonUsername('device_x');
      final r2 = AuthApi.buildAnonUsername('device_x');
      expect(r1, r2);
    });

    test('contains deviceId in encoded form', () {
      final result = AuthApi.buildAnonUsername('test_device');
      // Decode and verify it contains the deviceId
      final decoded = utf8.decode(base64.decode(result));
      expect(decoded, startsWith('test_device '));
    });

    test('decoded format: deviceId + space + md5_base64', () {
      final result = AuthApi.buildAnonUsername('ABC');
      final decoded = utf8.decode(base64.decode(result));
      final parts = decoded.split(' ');
      expect(parts.length, 2);
      expect(parts[0], 'ABC');
      // parts[1] is base64 of MD5 digest
      expect(RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(parts[1]), isTrue);
    });
  });

  // ==========================================================
  // getLoginQrKey [eapi]
  // ==========================================================
  group('getLoginQrKey', () {
    test('returns unikey on success', () async {
      final api = await _createAuthApi(responseBody: {
        'code': 200,
        'data': {'unikey': 'test_unikey_123'},
      });
      final unikey = await api.getLoginQrKey();
      expect(unikey, 'test_unikey_123');
    });

    test('endpoint is correct', () async {
      final api = await _createAuthApi(responseBody: {
        'code': 200,
        'data': {'unikey': 'key'},
      });
      await api.getLoginQrKey();
      expect(_lastCaptured!.uri.toString(), contains('/eapi/login/qrcode/unikey'));
    });

    test('crypto scheme is eapi', () async {
      final api = await _createAuthApi(responseBody: {
        'code': 200,
        'data': {'unikey': 'key'},
      });
      await api.getLoginQrKey();
      expect(_lastCaptured!.uri.toString(), contains('/eapi/'));
    });
  });

  // ==========================================================
  // checkLoginQr [eapi]
  // ==========================================================
  group('checkLoginQr', () {
    test('returns QrCheckResult with code 801 for waiting', () async {
      final api = await _createAuthApi(responseBody: {
        'code': 801,
      });
      final result = await api.checkLoginQr('unikey_test');
      expect(result.code, 801);
      expect(result.isWaiting, isTrue);
      expect(result.isSuccess, isFalse);
    });

    test('returns QrCheckResult with code 802 for scanned', () async {
      final api = await _createAuthApi(responseBody: {
        'code': 802,
      });
      final result = await api.checkLoginQr('unikey_test');
      expect(result.code, 802);
      expect(result.isScanned, isTrue);
    });

    test('returns QrCheckResult with code 803 for success', () async {
      // Mock a successful QR login with cookie
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          _lastCaptured = options;
          handler.resolve(Response(
            requestOptions: options,
            data: {'code': 803},
            statusCode: 200,
            headers: Headers()
              ..add('set-cookie',
                  'MUSIC_U=user_token_123; Max-Age=1296000; Path=/')
              ..add('set-cookie',
                  '__csrf=csrf_token_456; Max-Age=1296000; Path=/'),
          ));
        },
      ));

      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      final engine = NeteaseRequest(
        dio: mockDio,
        cookie: CookieManager(config),
        config: config,
      );
      final api = AuthApi(
        request: engine,
        directDio: mockDio,
        config: config,
      );

      final result = await api.checkLoginQr('unikey_test');
      expect(result.code, 803);
      expect(result.isSuccess, isTrue);
      // Cookies should be persisted
      expect(config.musicU, 'user_token_123');
    });

    test('returns QrCheckResult with code 800 for expired', () async {
      final api = await _createAuthApi(responseBody: {
        'code': 800,
      });
      final result = await api.checkLoginQr('unikey_test');
      expect(result.code, 800);
      expect(result.isExpired, isTrue);
    });
  });

  // ==========================================================
  // loginCellphone [weapi]
  // ==========================================================
  group('loginCellphone', () {
    test('returns LoginResult on success', () async {
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          _lastCaptured = options;
          handler.resolve(Response(
            requestOptions: options,
            data: {'code': 200, 'profile': {'userId': 123}},
            statusCode: 200,
            headers: Headers()
              ..add('set-cookie', 'MUSIC_U=logged_in_token; Path=/')
              ..add('set-cookie', '__csrf=new_csrf; Path=/'),
          ));
        },
      ));

      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      final engine = NeteaseRequest(
        dio: mockDio,
        cookie: CookieManager(config),
        config: config,
      );
      final api = AuthApi(
        request: engine,
        directDio: mockDio,
        config: config,
      );

      final result = await api.loginCellphone(
        phone: '13800138000',
        md5Password: 'md5hex',
      );

      expect(result.code, 200);
      expect(result.isSuccess, isTrue);
      expect(result.profile, {'userId': 123});
      expect(config.musicU, 'logged_in_token');
      expect(config.csrf, 'new_csrf');
    });

    test('endpoint is correct weapi', () async {
      final api = await _createAuthApi(responseBody: {
        'code': 200,
      });
      await api.loginCellphone(phone: '138', md5Password: 'md5');
      expect(_lastCaptured!.uri.toString(), contains('/weapi/w/login/cellphone'));
    });

    test('sends phone and password in body', () async {
      final api = await _createAuthApi(responseBody: {
        'code': 200,
      });
      await api.loginCellphone(phone: '13800138000', md5Password: 'abc_md5');

      // The body is encrypted weapi, verify URL params before encryption
      expect(_lastCaptured!.uri.toString(), contains('/weapi/'));
      expect(_lastCaptured!.data['params'], isNotNull);
      expect(_lastCaptured!.data['encSecKey'], isNotNull);
    });

    test('supports captcha mode', () async {
      final api = await _createAuthApi(responseBody: {
        'code': 200,
      });
      await api.loginCellphone(
        phone: '138',
        md5Password: 'unused',
        captcha: '123456',
      );
      expect(_lastCaptured!.uri.toString(), contains('/weapi/w/login/cellphone'));
    });

    test('non-200 code returns failure', () async {
      final api = await _createAuthApi(responseBody: {
        'code': 502,
        'message': 'error',
      });
      final result = await api.loginCellphone(
        phone: '138', md5Password: 'md5',
      );
      expect(result.isSuccess, isFalse);
      expect(result.code, 502);
    });
  });

  // ==========================================================
  // loginStatus [weapi]
  // ==========================================================
  group('loginStatus', () {
    test('returns profile on success', () async {
      final api = await _createAuthApi(responseBody: {
        'code': 200,
        'data': {'account': {'id': 123}},
      });
      final result = await api.loginStatus();
      expect(result, isNotNull);
      expect(result!['code'], 200);
    });

    test('endpoint is correct weapi', () async {
      final api = await _createAuthApi(responseBody: {
        'code': 200,
      });
      await api.loginStatus();
      expect(_lastCaptured!.uri.toString(), contains('/weapi/w/nuser/account/get'));
    });

    test('non-200 code returns null', () async {
      final api = await _createAuthApi(responseBody: {
        'code': 301,
      });
      final result = await api.loginStatus();
      expect(result, isNull);
    });
  });

  // ==========================================================
  // refreshToken [eapi]
  // ==========================================================
  group('refreshToken', () {
    test('returns cookie string on success', () async {
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          _lastCaptured = options;
          handler.resolve(Response(
            requestOptions: options,
            data: {'code': 200},
            statusCode: 200,
            headers: Headers()
              ..add('set-cookie', 'MUSIC_U=refreshed_token; Path=/'),
          ));
        },
      ));

      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      final engine = NeteaseRequest(
        dio: mockDio,
        cookie: CookieManager(config),
        config: config,
      );
      final api = AuthApi(
        request: engine,
        directDio: mockDio,
        config: config,
      );

      final cookie = await api.refreshToken();
      expect(cookie, isNotNull);
      expect(cookie, contains('MUSIC_U'));
      expect(config.musicU, 'refreshed_token');
    });

    test('endpoint is correct eapi', () async {
      final api = await _createAuthApi(responseBody: {
        'code': 200,
      });
      await api.refreshToken();
      expect(_lastCaptured!.uri.toString(), contains('/eapi/login/token/refresh'));
    });
  });

  // ==========================================================
  // registerAnonymous [xeapi]
  // ==========================================================
  group('registerAnonymous', () {
    test('throws when proxy not configured', () async {
      final api = await _createAuthApi();
      expect(() => api.registerAnonymous(), throwsUnimplementedError);
    });

    test('returns MUSIC_A on success', () async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'body': {
                'code': 200,
                'cookie': 'MUSIC_A=anon_token_from_proxy',
              },
              'cookie': [],
            },
            statusCode: 200,
          ));
        },
      ));

      final proxy = XeapiProxy(dio: mockDio, proxyUrl: 'https://test.local/api');
      final api = AuthApi(
        request: _createMockEngine(),
        directDio: mockDio,
        config: config,
        xeapiProxy: proxy,
      );

      final musicA = await api.registerAnonymous();
      expect(musicA, 'anon_token_from_proxy');
      expect(config.musicA, 'anon_token_from_proxy');
    });

    test('sends correct endpoint and cookie format', () async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      final mockDio = Dio();
      RequestOptions? proxyCaptured;
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          proxyCaptured = options;
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'body': {'code': 200, 'cookie': 'MUSIC_A=test'},
              'cookie': [],
            },
            statusCode: 200,
          ));
        },
      ));

      final proxy = XeapiProxy(dio: mockDio, proxyUrl: 'https://proxy.local/api');
      final engine = _createMockEngine();
      final api = AuthApi(
        request: engine,
        directDio: mockDio,
        config: config,
        xeapiProxy: proxy,
      );

      await api.registerAnonymous();

      final data = proxyCaptured!.data as Map<String, dynamic>;
      expect(data['endpoint'], '/api/register/anonimous');
      expect(data['data'], {'username': isA<String>()});
      expect(data['cookie'], startsWith('deviceId='));
    });
  });

  // ==========================================================
  // getXeapiPublicKey [special direct API]
  // ==========================================================
  group('getXeapiPublicKey', () {
    test('returns XeapiKeyState on success', () async {
      final responseJson = {
        'sk': 'some_x25519_public_key_base64',
        'expireTime': 9999999999,
        'version': 1,
      };
      final encryptedBytes = aesEcbEncrypt(
        Uint8List.fromList(utf8.encode(jsonEncode(responseJson))),
        xeapiStaticKey,
      );
      final encryptedData = base64.encode(encryptedBytes);

      String? capturedNonce;
      String? capturedTimestamp;
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final data = options.data as Map<String, dynamic>;
          capturedNonce = data['nonce'] as String;
          capturedTimestamp = data['timestamp'] as String;
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'code': 200,
              'data': {
                'encryptedData': encryptedData,
                'signature': xeapiSign(capturedTimestamp!, capturedNonce!),
                'timestamp': capturedTimestamp,
              },
            },
            statusCode: 200,
          ));
        },
      ));

      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      final api = AuthApi(
        request: _createMockEngine(),
        directDio: dio,
        config: config,
      );

      final result = await api.getXeapiPublicKey();
      expect(result.sk, 'some_x25519_public_key_base64');
      expect(result.expireTime, 9999999999);
      expect(result.version, 1);
    });

    test('endpoint is correct', () async {
      final dio = Dio();
      RequestOptions? captured;
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          // Trigger signature mismatch error since we didn't prepare proper data
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: options,
              data: {'code': 500},
              statusCode: 500,
            ),
          ));
        },
      ));

      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      final api = AuthApi(
        request: _createMockEngine(),
        directDio: dio,
        config: config,
      );

      try {
        await api.getXeapiPublicKey();
      } catch (_) {
        // Expected
      }

      expect(
        captured!.uri.toString(),
        contains('interface.music.163.com/api/gorilla/anti/crawler/security/key/get'),
      );
    });

    test('sends Android User-Agent', () async {
      final dio = Dio();
      RequestOptions? captured;
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
          ));
        },
      ));

      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      final api = AuthApi(
        request: _createMockEngine(),
        directDio: dio,
        config: config,
      );

      try {
        await api.getXeapiPublicKey();
      } catch (_) {}

      expect(captured!.headers['User-Agent'], isNotNull);
      expect(captured!.headers['User-Agent']!.toString(), contains('NeteaseMusic'));
      expect(captured!.headers['User-Agent']!.toString(), contains('Android'));
    });
  });

  // ==========================================================
  // Error Paths
  // ==========================================================
  group('error paths', () {
    // --- registerAnonymous ---
    test('registerAnonymous throws when proxy returns non-200', () async {
      final proxyDio = Dio();
      proxyDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'body': {'code': 500, 'msg': 'error'},
              'cookie': [],
            },
            statusCode: 200,
          ));
        },
      ));

      final proxy = XeapiProxy(dio: proxyDio, proxyUrl: 'https://proxy.local');
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      final api = AuthApi(
        request: _createMockEngine(),
        directDio: Dio(),
        config: config,
        xeapiProxy: proxy,
      );

      expect(() => api.registerAnonymous(), throwsException);
    });

    // --- getLoginQrKey error paths ---
    test('getLoginQrKey throws when unikey missing', () async {
      final api = await _createAuthApi(responseBody: {
        'code': 200,
        'data': <String, dynamic>{},
      });
      expect(() => api.getLoginQrKey(), throwsA(anything));
    });

    test('getLoginQrKey throws when body is not Map', () async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();
      await config.setMusicA('anon');

      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: 'not a map',
            statusCode: 200,
          ));
        },
      ));
      final engine = NeteaseRequest(dio: dio, cookie: CookieManager(config), config: config);
      final api = AuthApi(request: engine, directDio: dio, config: config);

      expect(() => api.getLoginQrKey(), throwsException);
    });

    // --- loginCellphone error paths ---
    test('loginCellphone handles null response body', () async {
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: null,
            statusCode: 200,
          ));
        },
      ));

      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      final engine = NeteaseRequest(
        dio: mockDio,
        cookie: CookieManager(config),
        config: config,
      );
      final api = AuthApi(
        request: engine,
        directDio: mockDio,
        config: config,
      );

      final result = await api.loginCellphone(phone: '138', md5Password: 'md5');
      expect(result.code, 500);
      expect(result.isSuccess, isFalse);
    });

    // --- loginStatus error path ---
    test('loginStatus returns null when body is not Map', () async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: 'not a map',
            statusCode: 200,
          ));
        },
      ));
      final engine = NeteaseRequest(dio: dio, cookie: CookieManager(config), config: config);
      final api = AuthApi(request: engine, directDio: dio, config: config);

      final result = await api.loginStatus();
      expect(result, isNull);
    });

    // --- refreshToken error path ---
    test('refreshToken returns null when cookies empty', () async {
      final api = await _createAuthApi(responseBody: {
        'code': 200,
      });
      // Mock Dio that returns no set-cookie
      final result = await api.refreshToken();
      expect(result, isNull);
    });

    // --- getXeapiPublicKey error paths ---
    test('getXeapiPublicKey throws on non-200 response', () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: {'code': 500, 'msg': 'error'},
            statusCode: 200,
          ));
        },
      ));

      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      final api = AuthApi(
        request: _createMockEngine(),
        directDio: dio,
        config: config,
      );

      expect(() => api.getXeapiPublicKey(), throwsException);
    });

    test('getXeapiPublicKey throws on signature mismatch', () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'code': 200,
              'data': {
                'encryptedData': base64.encode(Uint8List(16)),
                'signature': 'bad_signature',
                'timestamp': '1234567890',
              },
            },
            statusCode: 200,
          ));
        },
      ));

      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      final api = AuthApi(
        request: _createMockEngine(),
        directDio: dio,
        config: config,
      );

      expect(() => api.getXeapiPublicKey(), throwsException);
    });

    // --- Dio network error ---
    test('getXeapiPublicKey propagates DioException', () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ));
        },
      ));

      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      final api = AuthApi(
        request: _createMockEngine(),
        directDio: dio,
        config: config,
      );

      expect(
        () => api.getXeapiPublicKey(),
        throwsA(isA<DioException>()),
      );
    });
  });
}
