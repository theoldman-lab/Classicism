import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'config.dart';
import 'cookie_manager.dart';
import 'crypto/constants.dart';
import 'crypto/eapi.dart';
import 'crypto/helpers.dart';
import 'crypto/weapi.dart';

// ============================================================
// API Response
// ============================================================

class ApiResponse {
  final int status;
  final dynamic body;
  final List<String> cookies;

  ApiResponse({required this.status, required this.body, this.cookies = const []});

  bool get isSuccess => status == 200;
}

// ============================================================
// User-Agent Strings (from util/request.js userAgentMap)
// ============================================================

const _uaWeapi =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0';
const _uaApiIphone =
    'NeteaseMusic 9.0.90/5038 (iPhone; iOS 16.2; zh_CN)';

// ============================================================
// NeteaseRequest — Central Request Dispatcher
// ============================================================

class NeteaseRequest {
  final Dio _dio;
  final CookieManager _cookie;
  final AppConfig _config;
  final String? _xeapiProxyUrl;

  static const _specialStatusCodes = {201, 302, 400, 502, 800, 801, 802, 803};

  NeteaseRequest({
    required Dio dio,
    required CookieManager cookie,
    required AppConfig config,
    String? xeapiProxyUrl,
  })  : _dio = dio,
        _cookie = cookie,
        _config = config,
        _xeapiProxyUrl = xeapiProxyUrl;

  // ============================================================
  // Main Request Method
  // ============================================================

  Future<ApiResponse> request(
    String endpoint,
    Map<String, dynamic> data, {
    Crypto crypto = Crypto.eapi,
    bool encryptResponse = false,
    String? ua,
    String? overrideDomain,
  }) async {
    final reqData = Map<String, dynamic>.from(data);

    if (crypto == Crypto.eapi || crypto == Crypto.weapi) {
      reqData.putIfAbsent('e_r', () => encryptResponse);
    }

    final initialCookie = <String, String>{};
    final musicU = _config.musicU;
    if (musicU != null && musicU.isNotEmpty) {
      initialCookie['MUSIC_U'] = musicU;
    }
    final musicA = _config.musicA;
    if (musicA != null && musicA.isNotEmpty) {
      initialCookie['MUSIC_A'] = musicA;
    }
    final csrf = _config.csrf;
    if (csrf != null && csrf.isNotEmpty) {
      initialCookie['__csrf'] = csrf;
    }
    final cookieMap = _cookie.processCookie(initialCookie, endpoint);
    final csrfToken = _config.csrf ?? cookieMap['__csrf'] ?? '';

    String url;
    Object? postData;
    Map<String, String> headers = {};
    bool needsBytesResponse = false;

    switch (crypto) {
      // ============================================================
      // WEAPI — AES-128-CBC × 2 + RSA-1024
      // ============================================================
      case Crypto.weapi:
        headers['Referer'] = overrideDomain ?? domain;
        headers['User-Agent'] = ua ?? _uaWeapi;
        reqData['csrf_token'] = csrfToken;

        final encrypted = weapi(reqData);
        postData = encrypted;
        url = '${overrideDomain ?? domain}/weapi/${endpoint.substring(5)}';
        headers['Cookie'] = CookieManager.cookieObjToString(cookieMap);

        needsBytesResponse = encryptResponse;
        break;

      // ============================================================
      // EAPI — MD5 + AES-128-ECB
      // ============================================================
      case Crypto.eapi:
        final header = _cookie.buildEapiHeader(cookieMap, csrfToken);
        reqData['header'] = header;

        headers['Cookie'] = CookieManager.createHeaderCookie(header);
        headers['User-Agent'] = ua ?? _uaApiIphone;

        final encrypted = eapi(endpoint, reqData);
        postData = encrypted;
        url = '${overrideDomain ?? apiDomain}/eapi/${endpoint.substring(5)}';

        needsBytesResponse = encryptResponse;
        break;

      // ============================================================
      // XEAPI — Cloud Function Proxy
      // ============================================================
      case Crypto.xeapi:
        final proxyUrl = _xeapiProxyUrl;
        if (proxyUrl == null) {
          throw UnimplementedError(
            'XEAPI cloud function URL not configured. '
            'Set xeapiProxyUrl in NeteaseRequest constructor.',
          );
        }

        final proxyResp = await _dio.post(
          proxyUrl,
          data: {
            'endpoint': endpoint,
            'data': reqData,
            'cookie': CookieManager.cookieObjToString(cookieMap),
            'deviceId': _config.deviceId,
          },
          options: Options(responseType: ResponseType.json),
        );

        final proxyBody = proxyResp.data as Map<String, dynamic>;
        final cookies = (proxyBody['cookie'] as List<dynamic>?)
                ?.cast<String>() ??
            [];
        return ApiResponse(
          status: 200,
          body: proxyBody['body'],
          cookies: cookies,
        );

      // ============================================================
      // API — Plain (no encryption)
      // ============================================================
      case Crypto.api:
        final header = _cookie.buildEapiHeader(cookieMap, csrfToken);
        headers['Cookie'] = CookieManager.createHeaderCookie(header);
        headers['User-Agent'] = ua ?? _uaApiIphone;

        url = '${overrideDomain ?? apiDomain}$endpoint';
        postData = reqData.map((k, v) => MapEntry(k, v.toString()));
        break;

      // ============================================================
      // LINUXAPI — Not implemented
      // ============================================================
      case Crypto.linuxapi:
        throw UnimplementedError('linuxapi is not supported');
    }

    // ============================================================
    // Send Request
    // ============================================================
    final responseType = needsBytesResponse ? ResponseType.bytes : ResponseType.json;

    final response = await _dio.post(
      url,
      data: postData,
      options: Options(
        headers: headers,
        responseType: responseType,
        contentType: Headers.formUrlEncodedContentType,
      ),
    );

    // ============================================================
    // Decrypt Response
    // ============================================================
    dynamic body;
    if (needsBytesResponse) {
      final hex = bytesToHex(Uint8List.fromList(response.data as List<int>));
      body = eapiResDecrypt(hex.toUpperCase());
    } else {
      body = response.data;
    }

    // ============================================================
    // Status Code Handling
    // ============================================================
    int status = response.statusCode ?? 500;
    if (body is Map && body['code'] != null) {
      final code = int.tryParse(body['code'].toString());
      if (code != null) {
        if (_specialStatusCodes.contains(code)) {
          status = 200;
        } else {
          status = code;
        }
      }
    }

    status = (status > 100 && status < 600) ? status : 400;

    return ApiResponse(
      status: status,
      body: body,
      cookies: _extractCookies(response),
    );
  }

  // ============================================================
  // Cookie Extraction (strips Domain attribute)
  // ============================================================

  List<String> _extractCookies(Response response) {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) return [];

    return setCookie
        .map((c) => c.replaceAll(RegExp(r'\s*Domain=[^(;|$)]+;*'), ''))
        .toList();
  }
}
