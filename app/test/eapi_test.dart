import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

import 'package:classicism/core/crypto/eapi.dart';
import 'package:classicism/core/crypto/constants.dart';
import 'package:classicism/core/crypto/helpers.dart';

Map<String, dynamic> _readGolden() {
  final file = File('test/golden_vectors.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  // ==========================================================
  // MD5
  // ==========================================================
  group('MD5', () {
    final golden = _readGolden();
    final tests = (golden['md5'] as Map<String, dynamic>);
    for (final entry in tests.entries) {
      final t = entry.value as Map<String, dynamic>;
      test(entry.key, () {
        final input = t['input'] as String;
        final expected = t['digest'] as String;
        final actual = crypto.md5.convert(utf8.encode(input)).toString();
        expect(actual, equals(expected));
      });
    }
  });

  // ==========================================================
  // AES-ECB low-level
  // ==========================================================
  group('AES-ECB', () {
    final golden = _readGolden();
    final tests = (golden['aes'] as Map<String, dynamic>);
    for (final entry in tests.entries) {
      final t = entry.value as Map<String, dynamic>;
      if (t['mode'] != 'ECB') continue;

      test('encrypt - ${entry.key}', () {
        final plaintext = utf8.encode(t['plaintext'] as String);
        final key = utf8.encode(t['key'] as String);
        final expectedHex = t['ciphertextHex'] as String;

        final cipher = PaddedBlockCipherImpl(
            PKCS7Padding(), ECBBlockCipher(AESEngine()));
        cipher.init(
            true,
            PaddedBlockCipherParameters<KeyParameter, CipherParameters>(
                KeyParameter(key), null));
        final result = cipher.process(Uint8List.fromList(plaintext));
        final actualHex = bytesToHex(result).toUpperCase();

        expect(actualHex, equals(expectedHex));
      });

      test('decrypt - ${entry.key}', () {
        final expectedPlaintext = t['plaintext'] as String;
        final key = utf8.encode(t['key'] as String);
        final ciphertext = hexToBytes(t['ciphertextHex'] as String);

        final cipher = PaddedBlockCipherImpl(
            PKCS7Padding(), ECBBlockCipher(AESEngine()));
        cipher.init(
            false,
            PaddedBlockCipherParameters<KeyParameter, CipherParameters>(
                KeyParameter(key), null));
        final result = cipher.process(ciphertext);
        final actualPlaintext = utf8.decode(result);

        expect(actualPlaintext, equals(expectedPlaintext));
      });
    }
  });

  // ==========================================================
  // EAPI — golden vectors
  // ==========================================================
  group('EAPI encrypt', () {
    final golden = _readGolden();
    final tests = (golden['eapi'] as Map<String, dynamic>);
    for (final entry in tests.entries) {
      final t = entry.value as Map<String, dynamic>;
      test(entry.key, () {
        final url = t['url'] as String;
        final data = Map<String, dynamic>.from(t['data'] as Map);
        final expectedParams = t['params'] as String;

        final result = eapi(url, data);

        expect(result['params'], equals(expectedParams),
            reason: 'params hex must match Node.js output byte-for-byte');
        expect(result['params']!.length, equals(t['paramsLength']));
      });
    }
  });

  // ==========================================================
  // EAPI — decrypt structure
  // ==========================================================
  group('EAPI decrypt structure', () {
    final golden = _readGolden();
    final tests = (golden['eapi'] as Map<String, dynamic>);
    for (final entry in tests.entries) {
      final t = entry.value as Map<String, dynamic>;
      test(entry.key, () {
        final url = t['url'] as String;
        final data = Map<String, dynamic>.from(t['data'] as Map);
        final expectedDecrypted = t['decryptedStructure'] as String;

        final result = eapi(url, data);
        final hex = result['params']!;

        final cipher = PaddedBlockCipherImpl(
            PKCS7Padding(), ECBBlockCipher(AESEngine()));
        cipher.init(
            false,
            PaddedBlockCipherParameters<KeyParameter, CipherParameters>(
                KeyParameter(utf8.encode(eapiKey)), null));
        final decrypted = cipher.process(hexToBytes(hex));
        final decryptedStr = utf8.decode(decrypted);

        expect(decryptedStr, equals(expectedDecrypted));
      });
    }
  });

  // ==========================================================
  // eapiResDecrypt — response decryption
  // ==========================================================
  group('eapiResDecrypt', () {
    test('decrypts RSA-encrypted hex to JSON', () {
      // Encrypt a simple JSON, then decrypt it
      final plaintext = utf8.encode('{"code":200,"data":"test"}');
      final encrypted = aesEcbEncrypt(
        plaintext,
        utf8.encode(eapiKey),
      );
      final hex = bytesToHex(encrypted).toUpperCase();

      final result = eapiResDecrypt(hex);
      expect(result, {'code': 200, 'data': 'test'});
    });

    test('decrypts gzip-compressed response (aeapi: true)', () async {
      final json = '{"code":200,"data":"compressed_test"}';
      final gzipBytes = Uint8List.fromList(gzip.encode(utf8.encode(json)));
      final encrypted = aesEcbEncrypt(gzipBytes, utf8.encode(eapiKey));
      final hex = bytesToHex(encrypted).toUpperCase();

      final result = eapiResDecrypt(hex, aeapi: true);
      expect(result, {'code': 200, 'data': 'compressed_test'});
    });

    test('returns null for invalid hex', () {
      final result = eapiResDecrypt('not_valid_hex');
      expect(result, isNull);
    });

    test('returns null for empty string', () {
      final result = eapiResDecrypt('');
      expect(result, isNull);
    });

    test('returns null for garbled ciphertext', () {
      final result = eapiResDecrypt('DEADBEEF');
      expect(result, isNull);
    });

    test('returns null for non-JSON decrypted data', () {
      final plaintext = utf8.encode('not json');
      final encrypted = aesEcbEncrypt(plaintext, utf8.encode(eapiKey));
      final hex = bytesToHex(encrypted).toUpperCase();
      final result = eapiResDecrypt(hex);
      expect(result, isNull);
    });
  });
}
