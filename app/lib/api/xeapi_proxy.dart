import 'package:dio/dio.dart';

class XeapiProxyResponse {
  final Map<String, dynamic> body;
  final List<String> cookies;

  XeapiProxyResponse({required this.body, required this.cookies});
}

class XeapiProxy {
  final Dio _dio;
  final String _proxyUrl;

  XeapiProxy({required Dio dio, required String proxyUrl})
      : _dio = dio,
        _proxyUrl = proxyUrl;

  Future<XeapiProxyResponse> call(
    String endpoint,
    Map<String, dynamic> data,
    String cookie,
  ) async {
    final response = await _dio.post(
      _proxyUrl,
      data: {
        'endpoint': endpoint,
        'data': data,
        'cookie': cookie,
      },
      options: Options(
        responseType: ResponseType.json,
        contentType: Headers.jsonContentType,
      ),
    );

    final body =
        Map<String, dynamic>.from(response.data['body'] as Map);
    final cookies = (response.data['cookie'] as List<dynamic>?)
            ?.cast<String>() ??
        [];

    return XeapiProxyResponse(body: body, cookies: cookies);
  }
}
