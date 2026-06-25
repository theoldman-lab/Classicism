import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

import 'package:classicism/core/crypto/weapi.dart';
import 'package:classicism/core/crypto/constants.dart';

Map<String, dynamic> _readGolden() {
  final file = File('test/golden_vectors.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  // ==========================================================
  // AES-CBC low-level
  // ==========================================================
  group('AES-CBC', () {
    final golden = _readGolden();
    final tests = (golden['aes'] as Map<String, dynamic>);
    for (final entry in tests.entries) {
      final t = entry.value as Map<String, dynamic>;
      if (t['mode'] != 'CBC') continue;

      test('encrypt - ${entry.key}', () {
        final plaintext = t['plaintext'] as String;
        final key = t['key'] as String;
        final iv = t['iv'] as String;
        final expectedBase64 = t['ciphertextBase64'] as String;

        final cipher = PaddedBlockCipherImpl(
            PKCS7Padding(), CBCBlockCipher(AESEngine()));
        final cbcParams = ParametersWithIV<KeyParameter>(
            KeyParameter(utf8.encode(key)), utf8.encode(iv));
        cipher.init(
            true,
            PaddedBlockCipherParameters<
                    ParametersWithIV<KeyParameter>, CipherParameters>(
                cbcParams, null));
        final result = cipher.process(utf8.encode(plaintext));
        final actualBase64 = base64.encode(result);

        expect(actualBase64, equals(expectedBase64));
      });
    }
  });

  // ==========================================================
  // RSA standalone
  // ==========================================================
  group('RSA', () {
    final golden = _readGolden();
    final tests = (golden['rsa'] as Map<String, dynamic>);
    for (final entry in tests.entries) {
      final t = entry.value as Map<String, dynamic>;
      test(entry.key, () {
        final input = t['input'] as String;
        final expectedHex = t['encryptedHex'] as String;

        // Use the same parse logic as weapi.dart by verifying through weapi:
        // Create a minimal weapi call with a known secretKey = input.reversed
        // encSecKey = RSA(input) → compare against expected
        final secretKey = input.split('').reversed.join();
        final result = weapi({'test': 'rsa'}, secretKey: secretKey);

        expect(result['encSecKey'], equals(expectedHex),
            reason: 'RSA encrypt must match golden vector');
        expect(result['encSecKey']!.length, equals(256));
      });
    }
  });

  // ==========================================================
  // WEAPI — golden vectors (deterministic secretKey)
  // ==========================================================
  group('WEAPI golden', () {
    final golden = _readGolden();
    final tests = (golden['weapi'] as Map<String, dynamic>);
    for (final entry in tests.entries) {
      final t = entry.value as Map<String, dynamic>;
      test(entry.key, () {
        final data = Map<String, dynamic>.from(t['data'] as Map);
        final expectedParams = t['params'] as String;
        final expectedEncSecKey = t['encSecKey'] as String;
        final secretKey = t['secretKey'] as String;

        final result = weapi(data, secretKey: secretKey);

        expect(result['params'], equals(expectedParams),
            reason: 'weapi params base64 must match');
        expect(result['encSecKey'], equals(expectedEncSecKey),
            reason: 'weapi encSecKey hex must match');
        expect(result['encSecKey']!.length, equals(256));
      });
    }
  });

  // ==========================================================
  // WEAPI — intermediate layer verification
  // ==========================================================
  group('WEAPI layers', () {
    final golden = _readGolden();
    final tests = (golden['weapi'] as Map<String, dynamic>);
    for (final entry in tests.entries) {
      final t = entry.value as Map<String, dynamic>;
      test('layer1 - ${entry.key}', () {
        final plaintext = t['plaintext'] as String;
        final expectedLayer1 = t['layer1_base64'] as String;

        final cipher = PaddedBlockCipherImpl(
            PKCS7Padding(), CBCBlockCipher(AESEngine()));
        final cbcParams = ParametersWithIV<KeyParameter>(
            KeyParameter(utf8.encode(presetKey)), utf8.encode(iv));
        cipher.init(
            true,
            PaddedBlockCipherParameters<
                    ParametersWithIV<KeyParameter>, CipherParameters>(
                cbcParams, null));
        final result = cipher.process(utf8.encode(plaintext));
        final actualBase64 = base64.encode(result);

        expect(actualBase64, equals(expectedLayer1));
      });

      test('layer2 - ${entry.key}', () {
        final layer1Base64 = t['layer1_base64'] as String;
        final secretKey = t['secretKey'] as String;
        final expectedLayer2 = t['layer2_base64'] as String;

        final cipher = PaddedBlockCipherImpl(
            PKCS7Padding(), CBCBlockCipher(AESEngine()));
        final cbcParams = ParametersWithIV<KeyParameter>(
            KeyParameter(utf8.encode(secretKey)), utf8.encode(iv));
        cipher.init(
            true,
            PaddedBlockCipherParameters<
                    ParametersWithIV<KeyParameter>, CipherParameters>(
                cbcParams, null));
        // Layer 2 encrypts the base64 string as UTF-8
        final result = cipher.process(utf8.encode(layer1Base64));
        final actualBase64 = base64.encode(result);

        expect(actualBase64, equals(expectedLayer2));
      });
    }
  });
}
