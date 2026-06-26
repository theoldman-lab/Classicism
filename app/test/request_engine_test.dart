import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:classicism/core/config.dart';
import 'package:classicism/core/cookie_manager.dart';
import 'package:classicism/core/crypto/constants.dart';
import 'package:classicism/core/crypto/eapi.dart';
import 'package:classicism/core/crypto/helpers.dart';
import 'package:classicism/core/request_engine.dart';

void main() {
  group('NeteaseRequest', () {
    late Dio dio;
    late AppConfig config;
    late CookieManager cookie;
    late RequestOptions? captured;

    Future<NeteaseRequest> createEngine({String? xeapiProxyUrl}) async {
      SharedPreferences.setMockInitialValues({});
      config = AppConfig.instance;
      await config.init();
      cookie = CookieManager(config);

      dio = Dio();
      captured = null;
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(Response(
            requestOptions: options,
            data: {'code': 200, 'data': 'mock'},
            statusCode: 200,
          ));
        },
      ));

      return NeteaseRequest(
        dio: dio,
        cookie: cookie,
        config: config,
        xeapiProxyUrl: xeapiProxyUrl,
      );
    }

    // ==========================================================
    // WEAPI
    // ==========================================================
    group('weapi', () {
      test('constructs correct URL', () async {
        final engine = await createEngine();
        await engine.request(
          '/api/w/login/cellphone',
          {'phone': '13800138000', 'password': 'md5hex'},
          crypto: Crypto.weapi,
        );

        expect(captured!.uri.toString(),
            contains('music.163.com/weapi/w/login/cellphone'));
      });

      test('sets Referer and User-Agent headers', () async {
        final engine = await createEngine();
        await engine.request(
          '/api/w/login/cellphone',
          {'phone': '13800138000', 'password': 'md5hex'},
          crypto: Crypto.weapi,
        );

        expect(captured!.headers['Referer'], contains('music.163.com'));
        expect(captured!.headers['User-Agent'], contains('Chrome/124'));
      });

      test('sends form-urlencoded body with params and encSecKey', () async {
        final engine = await createEngine();
        await engine.request(
          '/api/w/login/cellphone',
          {'phone': '13800138000', 'password': 'md5hex'},
          crypto: Crypto.weapi,
        );

        final body = captured!.data as Map<String, dynamic>;
        expect(body.containsKey('params'), isTrue);
        expect(body.containsKey('encSecKey'), isTrue);
        expect(body['encSecKey']!.toString().length, 256); // RSA 1024-bit
      });

      test('uses custom domain', () async {
        final engine = await createEngine();
        await engine.request(
          '/api/w/login/cellphone',
          {'phone': '13800138000'},
          crypto: Crypto.weapi,
          overrideDomain: 'https://custom.example.com',
        );

        expect(captured!.uri.toString(),
            contains('custom.example.com/weapi/'));
      });
    });

    // ==========================================================
    // EAPI
    // ==========================================================
    group('eapi', () {
      test('constructs correct URL', () async {
        final engine = await createEngine();
        await engine.request(
          '/api/search/get',
          {'s': 'test', 'type': 1, 'limit': 30},
          crypto: Crypto.eapi,
        );

        expect(captured!.uri.toString(),
            contains('interface.music.163.com/eapi/search/get'));
      });

      test('sends form-urlencoded body with params', () async {
        final engine = await createEngine();
        await engine.request(
          '/api/search/get',
          {'s': 'test', 'type': 1},
          crypto: Crypto.eapi,
        );

        final body = captured!.data as Map<String, dynamic>;
        expect(body.containsKey('params'), isTrue);
        // params should be uppercase hex (from AES-ECB encrypt)
        expect(RegExp(r'^[0-9A-F]+$').hasMatch(body['params'] as String), isTrue);
      });

      test('sets iPhone User-Agent by default', () async {
        final engine = await createEngine();
        await engine.request(
          '/api/search/get',
          {'s': 'test'},
          crypto: Crypto.eapi,
        );

        expect(captured!.headers['User-Agent'], contains('NeteaseMusic'));
        expect(captured!.headers['User-Agent'], contains('iPhone'));
      });

      test('uses custom User-Agent when provided', () async {
        final engine = await createEngine();
        await engine.request(
          '/api/search/get',
          {'s': 'test'},
          crypto: Crypto.eapi,
          ua: 'MyCustomApp/1.0',
        );

        expect(captured!.headers['User-Agent'], 'MyCustomApp/1.0');
      });
    });

    // ==========================================================
    // XEAPI (Cloud Function Proxy)
    // ==========================================================
    group('xeapi', () {
      test('forwards to cloud function', () async {
        final engine = await createEngine(
          xeapiProxyUrl: 'https://proxy.example.com/api/xeapi',
        );
        await engine.request(
          '/api/register/anonimous',
          {},
          crypto: Crypto.xeapi,
        );

        expect(captured!.uri.toString(),
            'https://proxy.example.com/api/xeapi');
      });

      test('sends endpoint, data, cookie to proxy', () async {
        final engine = await createEngine(
          xeapiProxyUrl: 'https://proxy.example.com/api/xeapi',
        );
        await engine.request(
          '/api/register/anonimous',
          {'key': 'value'},
          crypto: Crypto.xeapi,
        );

        final body = captured!.data as Map<String, dynamic>;
        expect(body['endpoint'], '/api/register/anonimous');
        expect(body['data'], {'key': 'value'});
        expect(body['cookie'], isA<String>());
      });

      test('throws when proxy URL not configured', () async {
        final engine = await createEngine();
        expect(
          () => engine.request(
            '/api/register/anonimous',
            {},
            crypto: Crypto.xeapi,
          ),
          throwsUnimplementedError,
        );
      });
    });

    // ==========================================================
    // API (Plain)
    // ==========================================================
    group('api', () {
      test('constructs URL without crypto prefix', () async {
        final engine = await createEngine();
        await engine.request(
          '/api/test/endpoint',
          {'key': 'value'},
          crypto: Crypto.api,
        );

        expect(captured!.uri.toString(),
            contains('interface.music.163.com/api/test/endpoint'));
        expect(captured!.uri.toString(), isNot(contains('/eapi/')));
        expect(captured!.uri.toString(), isNot(contains('/weapi/')));
      });

      test('sends plain data as form-urlencoded', () async {
        final engine = await createEngine();
        await engine.request(
          '/api/test',
          {'key': 'value', 'num': 123},
          crypto: Crypto.api,
        );

        final body = captured!.data as Map<String, dynamic>;
        expect(body['key'], 'value');
        expect(body['num'], '123');
      });
    });

    // ==========================================================
    // Response Handling
    // ==========================================================
    group('response', () {
      test('returns ApiResponse with status and body', () async {
        final engine = await createEngine();
        final response = await engine.request(
          '/api/search/get',
          {'s': 'test'},
          crypto: Crypto.eapi,
        );

        expect(response.isSuccess, isTrue);
        expect(response.status, 200);
        expect(response.body, {'code': 200, 'data': 'mock'});
      });

      test('returns cookies list', () async {
        final engine = await createEngine();
        final response = await engine.request(
          '/api/search/get',
          {'s': 'test'},
          crypto: Crypto.eapi,
        );

        expect(response.cookies, isA<List<String>>());
      });

      test('encryptResponse=true requests byte response', () async {
        final engine = await createEngine();
        try {
          await engine.request(
            '/api/search/get',
            {'s': 'test'},
            crypto: Crypto.eapi,
            encryptResponse: true,
          );
        } catch (_) {
          // Mock returns JSON not bytes, decryption fails — expected
        }
        expect(captured!.responseType, ResponseType.bytes);
      });

      test('encryptResponse=false requests JSON response', () async {
        final engine = await createEngine();
        await engine.request(
          '/api/search/get',
          {'s': 'test'},
          crypto: Crypto.eapi,
          encryptResponse: false,
        );

        expect(captured!.responseType, ResponseType.json);
      });
    });

    // ==========================================================
    // Special Status Codes
    // ==========================================================
    group('special status codes', () {
      test('maps 803 to 200', () async {
        final engine = await createEngine();
        dio.interceptors.clear();
        dio.interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.resolve(Response(
              requestOptions: options,
              data: {'code': 803, 'message': 'authorized'},
              statusCode: 200,
            ));
          },
        ));

        final response = await engine.request(
          '/api/login/qrcode/client/login',
          {'key': 'testkey'},
          crypto: Crypto.eapi,
        );

        expect(response.status, 200);
      });

      test('maps 801 to 200', () async {
        final engine = await createEngine();
        dio.interceptors.clear();
        dio.interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.resolve(Response(
              requestOptions: options,
              data: {'code': 801},
              statusCode: 200,
            ));
          },
        ));

        final response = await engine.request(
          '/api/login/qrcode/client/login',
          {'key': 'testkey'},
          crypto: Crypto.eapi,
        );

        expect(response.status, 200);
      });
    });

    // ==========================================================
    // linuxapi
    // ==========================================================
    group('linuxapi', () {
      test('throws UnimplementedError', () async {
        final engine = await createEngine();
        expect(
          () => engine.request('/api/test', {}, crypto: Crypto.linuxapi),
          throwsUnimplementedError,
        );
      });
    });

    // ==========================================================
    // Network Errors
    // ==========================================================
    group('network errors', () {
      test('propagates DioException on connection error', () async {
        final engine = await createEngine();
        dio.interceptors.clear();
        dio.interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.reject(DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              message: 'Connection refused',
            ));
          },
        ));

        expect(
          () => engine.request('/api/search/get', {'s': 'test'}),
          throwsA(isA<DioException>()),
        );
      });

      test('handles HTTP 500 response', () async {
        final engine = await createEngine();
        dio.interceptors.clear();
        dio.interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.resolve(Response(
              requestOptions: options,
              data: {'code': 502},
              statusCode: 502,
            ));
          },
        ));

        final response =
            await engine.request('/api/search/get', {'s': 'test'});
        // 502 is in special codes → mapped to 200
        expect(response.status, 200);
      });
    });

    // ==========================================================
    // Special Status Codes (complete coverage)
    // ==========================================================
    group('special status codes', () {
      test('maps 201 to 200', () async {
        final response = await _makeRequest({'code': 201});
        expect(response.status, 200);
      });

      test('maps 302 to 200', () async {
        final response = await _makeRequest({'code': 302});
        expect(response.status, 200);
      });

      test('maps 400 to 200', () async {
        final response = await _makeRequest({'code': 400});
        expect(response.status, 200);
      });

      test('maps 502 to 200', () async {
        final response = await _makeRequest({'code': 502});
        expect(response.status, 200);
      });

      test('maps 800 to 200', () async {
        final response = await _makeRequest({'code': 800});
        expect(response.status, 200);
      });

      test('maps 802 to 200', () async {
        final response = await _makeRequest({'code': 802});
        expect(response.status, 200);
      });

      test('non-special code passes through', () async {
        final engine = await createEngine();
        dio.interceptors.clear();
        dio.interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(Response(
              requestOptions: options,
              data: {'code': 301},
              statusCode: 200,
            ));
          },
        ));
        final response =
            await engine.request('/api/search/get', {'s': 'test'});
        expect(response.status, 301);
      });
    });

    // ==========================================================
    // encryptResponse=true with bytes
    // ==========================================================
    group('encryptResponse bytes', () {
      test('weapi encryptResponse sets bytes responseType', () async {
        final engine = await createEngine();
        try {
          await engine.request(
            '/api/w/login/cellphone',
            {'phone': '138'},
            crypto: Crypto.weapi,
            encryptResponse: true,
          );
        } catch (_) {
          // Expected — mock returns JSON not bytes
        }

        expect(captured!.responseType, ResponseType.bytes);
      });

      test('eapi encryptResponse decrypts bytes correctly', () async {
        final engine = await createEngine();
        dio.interceptors.clear();

        // Prepare valid encrypted response
        final plaintext = utf8.encode('{"code":200,"data":"secret"}');
        final encrypted = aesEcbEncrypt(plaintext, utf8.encode(eapiKey));
        final hex = bytesToHex(encrypted).toUpperCase();

        dio.interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.resolve(Response(
              requestOptions: options,
              data: Uint8List.fromList(hexToBytes(hex)),
              statusCode: 200,
            ));
          },
        ));

        final response = await engine.request(
          '/api/search/get',
          {'s': 'test'},
          crypto: Crypto.eapi,
          encryptResponse: true,
        );

        expect(response.status, 200);
        expect(response.body, {'code': 200, 'data': 'secret'});
      });
    });

    // ==========================================================
    // overrideDomain for EAPI
    // ==========================================================
    group('overrideDomain eapi', () {
      test('uses custom domain for eapi', () async {
        final engine = await createEngine();
        await engine.request(
          '/api/search/get',
          {'s': 'test'},
          crypto: Crypto.eapi,
          overrideDomain: 'https://custom.api.com',
        );

        expect(captured!.uri.toString(), contains('custom.api.com'));
      });
    });
  });
}

Future<ApiResponse> _makeRequest(Map<String, dynamic> responseBody) async {
  final mockDio = Dio();
  mockDio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        data: responseBody,
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
  return engine.request('/api/search/get', {'s': 'test'});
}
