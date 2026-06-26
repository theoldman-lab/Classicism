import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:classicism/api/xeapi_proxy.dart';

void main() {
  group('XeapiProxy', () {
    test('call returns body and cookies on success', () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: <String, dynamic>{
              'body': <String, dynamic>{'code': 200, 'data': {'key': 'value'}},
              'cookie': ['MUSIC_A=test_token', '__csrf=test_csrf'],
            },
            statusCode: 200,
          ));
        },
      ));

      final proxy = XeapiProxy(dio: dio, proxyUrl: 'https://test.proxy/api');
      final result = await proxy.call('/api/test', {'param': 'val'}, 'cookie_str');

      expect(result.body, {'code': 200, 'data': {'key': 'value'}});
      expect(result.cookies, ['MUSIC_A=test_token', '__csrf=test_csrf']);
    });

    test('sends endpoint, data, and cookie to proxy', () async {
      RequestOptions? captured;
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(Response(
            requestOptions: options,
            data: <String, dynamic>{'body': <String, dynamic>{}, 'cookie': <String>[]},
            statusCode: 200,
          ));
        },
      ));

      final proxy = XeapiProxy(dio: dio, proxyUrl: 'https://test.proxy/api');
      await proxy.call('/api/endpoint', {'key': 'val'}, 'MY_COOKIE');

      expect(captured!.uri.toString(), 'https://test.proxy/api');
      final body = captured!.data as Map<String, dynamic>;
      expect(body['endpoint'], '/api/endpoint');
      expect(body['data'], {'key': 'val'});
      expect(body['cookie'], 'MY_COOKIE');
    });

    test('handles missing cookie field in response', () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: <String, dynamic>{'body': {'code': 200}},
            statusCode: 200,
          ));
        },
      ));

      final proxy = XeapiProxy(dio: dio, proxyUrl: 'https://test.proxy/api');
      final result = await proxy.call('/api/test', {}, '');

      expect(result.cookies, isEmpty);
    });

    test('cookie field is null defaults to empty list', () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: <String, dynamic>{'body': <String, dynamic>{}, 'cookie': null},
            statusCode: 200,
          ));
        },
      ));

      final proxy = XeapiProxy(dio: dio, proxyUrl: 'https://test.proxy/api');
      final result = await proxy.call('/api/test', {}, '');

      expect(result.cookies, isEmpty);
    });

    test('uses JSON content type', () async {
      RequestOptions? captured;
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(Response(
            requestOptions: options,
            data: <String, dynamic>{'body': <String, dynamic>{}, 'cookie': <String>[]},
            statusCode: 200,
          ));
        },
      ));

      final proxy = XeapiProxy(dio: dio, proxyUrl: 'https://test.proxy/api');
      await proxy.call('/api/test', {}, '');

      expect(captured!.contentType, contains('application/json'));
    });

    test('propagates DioException on network error', () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            message: 'Connection refused',
          ));
        },
      ));

      final proxy = XeapiProxy(dio: dio, proxyUrl: 'https://test.proxy/api');

      expect(
        () => proxy.call('/api/test', {}, ''),
        throwsA(isA<DioException>()),
      );
    });

    test('propagates on HTTP 500 error', () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: {'error': 'Internal Server Error'},
            statusCode: 500,
          ));
        },
      ));

      final proxy = XeapiProxy(dio: dio, proxyUrl: 'https://test.proxy/api');

      // body would be missing, causing cast error
      expect(
        () => proxy.call('/api/test', {}, ''),
        throwsA(isA<TypeError>()),
      );
    });

    test('XeapiProxyResponse direct construction', () {
      final resp = XeapiProxyResponse(
        body: {'code': 200},
        cookies: ['A=1', 'B=2'],
      );
      expect(resp.body['code'], 200);
      expect(resp.cookies.length, 2);
    });
  });
}
