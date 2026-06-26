import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';

import 'package:classicism/core/crypto/constants.dart';
import 'package:classicism/core/crypto/eapi.dart';
import 'package:classicism/core/crypto/xeapi_helpers.dart';

void main() {
  group('xeapiSign', () {
    test('returns valid base64 string', () {
      final result = xeapiSign('1234567890123', '0123456789012345');
      expect(result, isNotEmpty);
      // base64 regex: letters, digits, +, /, = at end
      expect(
        RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(result),
        isTrue,
      );
    });

    test('is deterministic — same input gives same output', () {
      final r1 = xeapiSign('abc', '123');
      final r2 = xeapiSign('abc', '123');
      expect(r1, r2);
    });

    test('different timestamp gives different result', () {
      final r1 = xeapiSign('111', 'test');
      final r2 = xeapiSign('222', 'test');
      expect(r1, isNot(r2));
    });

    test('different nonce gives different result', () {
      final r1 = xeapiSign('test', '111');
      final r2 = xeapiSign('test', '222');
      expect(r1, isNot(r2));
    });

    test('HMAC-SHA256 produces 44-char base64', () {
      final result = xeapiSign('1234567890123', '0123456789012345');
      expect(result.length, 44);
    });

    test('uses xeapiSignKey as raw string (UTF-8 bytes)', () {
      // The upstream passes xeapiSignKey as a raw string to createHmac.
      // We verify by comparing with manual HMAC computation.
      const prefix = '';
      final message = '12345678901230123456789012345';
      final keyBytes = utf8.encode(xeapiSignKey);
      final hmac = crypto.Hmac(crypto.sha256, keyBytes);
      final digest = hmac.convert(utf8.encode('$prefix$message'));
      final expected = base64.encode(digest.bytes);

      final actual = xeapiSign('1234567890123', '0123456789012345');
      expect(actual, expected);
    });
  });

  group('xeapiDecryptPublicKey', () {
    test('decrypts AES-256-ECB encrypted base64', () {
      final plaintext = utf8.encode(
        '{"sk":"test_public_key","expireTime":1234567890,"version":1,"nonce":"abc"}',
      );
      final encrypted = aesEcbEncrypt(
        Uint8List.fromList(plaintext),
        xeapiStaticKey,
      );
      final encryptedBase64 = base64.encode(encrypted);

      final result = xeapiDecryptPublicKey(encryptedBase64);

      expect(result['sk'], 'test_public_key');
      expect(result['expireTime'], 1234567890);
      expect(result['version'], 1);
      expect(result['nonce'], 'abc');
    });

    test('decrypts with correct key length (AES-256)', () {
      // xeapiStaticKey is 32 bytes → AES-256
      final plaintext = utf8.encode('{"ok":true}');
      final encrypted = aesEcbEncrypt(
        Uint8List.fromList(plaintext),
        xeapiStaticKey,
      );
      final encryptedBase64 = base64.encode(encrypted);

      final result = xeapiDecryptPublicKey(encryptedBase64);
      expect(result['ok'], true);
    });

    test('roundtrip with various data', () {
      final testCases = [
        {'sk': 'abc', 'expireTime': 1, 'version': 0, 'nonce': ''},
        {'sk': 'x' * 100, 'expireTime': 9999999999, 'version': 999, 'nonce': 'test'},
      ];

      for (final data in testCases) {
        final plaintext = utf8.encode(jsonEncode(data));
        final encrypted = aesEcbEncrypt(
          Uint8List.fromList(plaintext),
          xeapiStaticKey,
        );
        final b64 = base64.encode(encrypted);
        final decrypted = xeapiDecryptPublicKey(b64);
        expect(decrypted['sk'], data['sk']);
        expect(decrypted['expireTime'], data['expireTime']);
        expect(decrypted['version'], data['version']);
        expect(decrypted['nonce'], data['nonce']);
      }
    });
  });
}
