import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:classicism/api/auth_api.dart';
import 'package:classicism/api/xeapi_proxy.dart';
import 'package:classicism/core/config.dart';
import 'package:classicism/core/cookie_manager.dart';
import 'package:classicism/core/request_engine.dart';
import 'package:classicism/services/auth_service.dart';

Future<void> _setupMockPrefs() async {
  SharedPreferences.setMockInitialValues({});
  final config = AppConfig.instance;
  await config.init();
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

AuthApi _createAuthApiWithConfig(AppConfig config) {
  final engineDio = Dio();
  _addMockInterceptor(engineDio, {'code': 200, 'data': {}});

  final directDio = Dio();
  _addMockInterceptor(directDio, {'code': 200, 'data': {}});

  final engine = NeteaseRequest(
    dio: engineDio,
    cookie: CookieManager(config),
    config: config,
  );

  return AuthApi(
    request: engine,
    directDio: directDio,
    config: config,
  );
}

void main() {
  // ==========================================================
  // loginWithPassword
  // ==========================================================
  group('loginWithPassword', () {
    test('MD5 hashes the password before login', () async {
      await _setupMockPrefs();
      final config = AppConfig.instance;

      final dio = Dio();
      var capturedBody = <String, dynamic>{};
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedBody = options.data as Map<String, dynamic>;
          handler.resolve(Response(
            requestOptions: options,
            data: {'code': 200, 'profile': {'userId': 1}},
            statusCode: 200,
            headers: Headers()
              ..add('set-cookie', 'MUSIC_U=token; Path=/'),
          ));
        },
      ));

      final engine = NeteaseRequest(
        dio: dio,
        cookie: CookieManager(config),
        config: config,
      );
      final api = AuthApi(
        request: engine,
        directDio: dio,
        config: config,
      );
      final service = AuthService(api: api, config: config);

      await service.loginWithPassword('13800138000', 'mypassword');

      // Body is weapi-encrypted; params should be present
      expect(capturedBody.containsKey('params'), isTrue);
      expect(capturedBody.containsKey('encSecKey'), isTrue);
    });
  });

  // ==========================================================
  // logout
  // ==========================================================
  group('logout', () {
    test('clears MUSIC_U, __csrf, and uid', () async {
      await _setupMockPrefs();
      final config = AppConfig.instance;
      await config.setMusicU('user_token');
      await config.setCsrf('csrf_token');
      await config.setUid(12345);

      final api = _createAuthApiWithConfig(config);
      final service = AuthService(api: api, config: config);

      await service.logout();

      expect(config.musicU, '');
      expect(config.csrf, '');
      expect(config.uid, 0);
    });
  });

  // ==========================================================
  // initialize
  // ==========================================================
  group('initialize', () {
    test('registers anonymous when MUSIC_A is missing', () async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      final proxyDio = Dio();
      proxyDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'body': {
                'code': 200,
                'cookie': 'MUSIC_A=new_anon_token',
              },
              'cookie': [],
            },
            statusCode: 200,
          ));
        },
      ));

      final proxy = XeapiProxy(dio: proxyDio, proxyUrl: 'https://proxy.test');
      final engineDio = Dio();
      _addMockInterceptor(engineDio, {'code': 200, 'data': {}});

      final engine = NeteaseRequest(
        dio: engineDio,
        cookie: CookieManager(config),
        config: config,
      );

      final api = AuthApi(
        request: engine,
        directDio: Dio(),
        config: config,
        xeapiProxy: proxy,
      );
      final service = AuthService(api: api, config: config);

      expect(config.musicA, isNull);
      await service.initialize();
      expect(config.musicA, 'new_anon_token');
    });

    test('skips register when MUSIC_A already exists', () async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();
      await config.setMusicA('existing_anon');

      var proxyCalled = false;
      final proxyDio = Dio();
      proxyDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          proxyCalled = true;
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'body': {'code': 200, 'cookie': 'MUSIC_A=should_not'},
              'cookie': [],
            },
            statusCode: 200,
          ));
        },
      ));

      final proxy = XeapiProxy(dio: proxyDio, proxyUrl: 'https://proxy.test');
      final engineDio = Dio();
      _addMockInterceptor(engineDio, {'code': 200, 'data': {}});

      final engine = NeteaseRequest(
        dio: engineDio,
        cookie: CookieManager(config),
        config: config,
      );

      final api = AuthApi(
        request: engine,
        directDio: Dio(),
        config: config,
        xeapiProxy: proxy,
      );
      final service = AuthService(api: api, config: config);

      await service.initialize();

      expect(proxyCalled, isFalse);
      expect(config.musicA, 'existing_anon');
    });
  });

  // ==========================================================
  // pollLoginQr
  // ==========================================================
  group('pollLoginQr', () {
    test('emits waiting then success and stops', () async {
      await _setupMockPrefs();
      final config = AppConfig.instance;

      var callCount = 0;
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          callCount++;
          final Map<String, dynamic> response;
          if (callCount == 1) {
            response = {'code': 801}; // waiting
          } else {
            response = {'code': 803}; // success
            handler.resolve(Response(
              requestOptions: options,
              data: response,
              statusCode: 200,
              headers: Headers()
                ..add('set-cookie', 'MUSIC_U=qr_user_token; Path=/')
                ..add('set-cookie', '__csrf=qr_csrf; Path=/'),
            ));
            return;
          }
          handler.resolve(Response(
            requestOptions: options,
            data: response,
            statusCode: 200,
          ));
        },
      ));

      final engine = NeteaseRequest(
        dio: dio,
        cookie: CookieManager(config),
        config: config,
      );
      final api = AuthApi(
        request: engine,
        directDio: dio,
        config: config,
      );
      final service = AuthService(api: api, config: config);

      final results = <QrCheckResult>[];
      await for (final r in service.pollLoginQr('test_unikey')) {
        results.add(r);
      }

      expect(results.length, 2);
      expect(results[0].isWaiting, isTrue);
      expect(results[1].isSuccess, isTrue);
    });

    test('stops when expired', () async {
      await _setupMockPrefs();
      final config = AppConfig.instance;

      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: {'code': 800},
            statusCode: 200,
          ));
        },
      ));

      final engine = NeteaseRequest(
        dio: dio,
        cookie: CookieManager(config),
        config: config,
      );
      final api = AuthApi(
        request: engine,
        directDio: dio,
        config: config,
      );
      final service = AuthService(api: api, config: config);

      final results = <QrCheckResult>[];
      await for (final r in service.pollLoginQr('test_unikey')) {
        results.add(r);
      }

      expect(results.length, 1);
      expect(results[0].isExpired, isTrue);
    });

    test('propagates error when checkLoginQr throws', () async {
      await _setupMockPrefs();
      final config = AppConfig.instance;

      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ));
        },
      ));

      final engine = NeteaseRequest(
        dio: dio,
        cookie: CookieManager(config),
        config: config,
      );
      final api = AuthApi(
        request: engine,
        directDio: dio,
        config: config,
      );
      final service = AuthService(api: api, config: config);

      expect(
        service.pollLoginQr('test_unikey').first,
        throwsA(isA<DioException>()),
      );
    });
  });

  // ==========================================================
  // initialize error path
  // ==========================================================
  group('initialize errors', () {
    test('propagates error when registerAnonymous fails', () async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig.instance;
      await config.init();

      final proxyDio = Dio();
      proxyDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: {
              'body': {'code': 500},
              'cookie': [],
            },
            statusCode: 200,
          ));
        },
      ));

      final proxy = XeapiProxy(dio: proxyDio, proxyUrl: 'https://proxy.test');
      final engineDio = Dio();
      _addMockInterceptor(engineDio, {'code': 200});

      final engine = NeteaseRequest(
        dio: engineDio,
        cookie: CookieManager(config),
        config: config,
      );
      final api = AuthApi(
        request: engine,
        directDio: Dio(),
        config: config,
        xeapiProxy: proxy,
      );
      final service = AuthService(api: api, config: config);

      expect(service.initialize(), throwsException);
    });
  });
}
