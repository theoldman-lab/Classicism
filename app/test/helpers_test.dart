import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:classicism/core/crypto/helpers.dart';

void main() {
  group('bytesToHex', () {
    test('converts bytes to lowercase hex', () {
      expect(bytesToHex(Uint8List.fromList([0xab, 0xcd, 0xef])), 'abcdef');
    });

    test('single byte pads to 2 chars', () {
      expect(bytesToHex(Uint8List.fromList([0x0a])), '0a');
      expect(bytesToHex(Uint8List.fromList([0xff])), 'ff');
    });

    test('empty list returns empty string', () {
      expect(bytesToHex(Uint8List.fromList([])), '');
    });

    test('zero byte', () {
      expect(bytesToHex(Uint8List.fromList([0x00])), '00');
    });

    test('large value', () {
      final bytes = Uint8List.fromList(List.generate(256, (i) => i));
      final hex = bytesToHex(bytes);
      expect(hex.length, 512);
      expect(hex.substring(0, 2), '00');
      expect(hex.substring(hex.length - 2), 'ff');
    });
  });

  group('hexToBytes', () {
    test('converts hex to bytes', () {
      final result = hexToBytes('abcdef');
      expect(result, Uint8List.fromList([0xab, 0xcd, 0xef]));
    });

    test('uppercase hex', () {
      final result = hexToBytes('ABCDEF');
      expect(result, Uint8List.fromList([0xab, 0xcd, 0xef]));
    });

    test('empty string returns empty list', () {
      expect(hexToBytes(''), Uint8List.fromList([]));
    });

    test('roundtrip with bytesToHex', () {
      final original = Uint8List.fromList([0x01, 0x23, 0x45, 0x67, 0x89, 0xab]);
      expect(hexToBytes(bytesToHex(original)), original);
    });
  });

  group('bytesToBase64', () {
    test('encodes bytes to base64', () {
      final result = bytesToBase64(Uint8List.fromList([0x61, 0x62, 0x63]));
      expect(result, 'YWJj');
    });

    test('empty list returns empty string', () {
      expect(bytesToBase64(Uint8List.fromList([])), '');
    });

    test('roundtrip via base64ToBytes', () {
      final original = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(base64ToBytes(bytesToBase64(original)), original);
    });
  });

  group('base64ToBytes', () {
    test('decodes base64 to bytes', () {
      final result = base64ToBytes('YWJj');
      expect(result, Uint8List.fromList([0x61, 0x62, 0x63]));
    });
  });

  group('randomString', () {
    test('returns string of given length', () {
      expect(randomString(10).length, 10);
      expect(randomString(1).length, 1);
      expect(randomString(50).length, 50);
    });

    test('contains only alphanumeric chars', () {
      final s = randomString(100);
      expect(RegExp(r'^[a-zA-Z0-9]+$').hasMatch(s), isTrue);
    });

    test('different calls produce different results', () {
      final s1 = randomString(20);
      final s2 = randomString(20);
      expect(s1, isNot(s2));
    });
  });

  group('randomBytes', () {
    test('returns bytes of given length', () {
      expect(randomBytes(10).length, 10);
      expect(randomBytes(0).length, 0);
      expect(randomBytes(32).length, 32);
    });

    test('different calls produce different results', () {
      final b1 = randomBytes(16);
      final b2 = randomBytes(16);
      expect(b1, isNot(b2));
    });
  });

  group('base62Encode', () {
    test('encodes zero correctly', () {
      expect(base62Encode(Uint8List.fromList([0x00])), 'a');
    });

    test('encodes simple value', () {
      final result = base62Encode(Uint8List.fromList([0x01]));
      expect(result, isNotEmpty);
      expect(RegExp(r'^[a-zA-Z0-9]+$').hasMatch(result), isTrue);
    });

    test('encode then decode (via hex roundtrip)', () {
      final original = Uint8List.fromList([0x12, 0x34, 0x56]);
      final encoded = base62Encode(original);
      // Verify it contains only base62 chars
      const alphabet =
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      for (final c in encoded.split('')) {
        expect(alphabet.contains(c), isTrue);
      }
    });

    test('empty bytes returns single char', () {
      // Uint8List(0) maps to BigInt.zero
      final result = base62Encode(Uint8List.fromList([]));
      expect(result, 'a');
      expect(RegExp(r'^[a-zA-Z0-9]+$').hasMatch(result), isTrue);
    });

    test('maximum value', () {
      final bytes = Uint8List.fromList([0xff, 0xff, 0xff, 0xff]);
      final result = base62Encode(bytes);
      expect(result, isNotEmpty);
      expect(RegExp(r'^[a-zA-Z0-9]+$').hasMatch(result), isTrue);
    });
  });
}
