import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'constants.dart';
import 'helpers.dart';

// ============================================================
// AES-128-CBC (PKCS7 padding) → returns raw encrypted bytes
// ============================================================

Uint8List _aesCbcEncryptRaw(Uint8List plaintext, Uint8List key, Uint8List iv) {
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
  final cbcParams = ParametersWithIV<KeyParameter>(
      KeyParameter(key), Uint8List.fromList(iv));
  cipher.init(true,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, CipherParameters>(cbcParams, null));
  return cipher.process(plaintext);
}

String _aesCbcEncrypt(String plaintext, String key, String iv) {
  final encrypted = _aesCbcEncryptRaw(
      utf8.encode(plaintext), utf8.encode(key), utf8.encode(iv));
  return base64.encode(encrypted);
}

// ============================================================
// RSA-1024 (NONE / raw RSA padding) → lowercase hex output
// ============================================================

RSAPublicKey _parsePublicKey(String pem) {
  final b64 = pem
      .replaceAll('-----BEGIN PUBLIC KEY-----', '')
      .replaceAll('-----END PUBLIC KEY-----', '')
      .replaceAll(RegExp(r'\s'), '');
  final der = Uint8List.fromList(base64.decode(b64));

  int pos = 0;

  int readTag() => der[pos++];

  int readLength() {
    int b = der[pos++];
    if (b < 0x80) return b;
    int numBytes = b & 0x7f;
    int len = 0;
    for (int i = 0; i < numBytes; i++) {
      len = (len << 8) | der[pos++];
    }
    return len;
  }

  Uint8List readBytes(int len) {
    final bytes = der.sublist(pos, pos + len);
    pos += len;
    return bytes;
  }

  void expectTag(int actual, int expected) {
    if (actual != expected) {
      throw FormatException(
          'ASN.1 parse: expected 0x${expected.toRadixString(16)}, got 0x${actual.toRadixString(16)}');
    }
  }

  // Outer SEQUENCE
  expectTag(readTag(), 0x30);
  readLength();

  // AlgorithmIdentifier SEQUENCE → skip
  expectTag(readTag(), 0x30);
  int algLen = readLength();
  pos += algLen;

  // BIT STRING wrapping the RSA key
  expectTag(readTag(), 0x03);
  readLength();
  pos++; // skip unusedBits byte (always 0x00)

  // Inner SEQUENCE { INTEGER n, INTEGER e }
  expectTag(readTag(), 0x30);
  readLength();

  // INTEGER n (modulus)
  expectTag(readTag(), 0x02);
  int nLen = readLength();
  Uint8List nBytes = readBytes(nLen);

  // INTEGER e (public exponent)
  expectTag(readTag(), 0x02);
  int eLen = readLength();
  Uint8List eBytes = readBytes(eLen);

  BigInt bytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (int i = 0; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  return RSAPublicKey(bytesToBigInt(nBytes), bytesToBigInt(eBytes));
}

String _rsaEncrypt(String text, RSAPublicKey publicKey) {
  final engine = RSAEngine();
  engine.init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

  final inputBytes = utf8.encode(text);
  // RSA-1024: output is always 128 bytes. Left-pad with zeros.
  // RSAEngine.processBlock will convert to BigInt → m^e mod n → 128 bytes
  final outLen = 128;
  final padded = Uint8List(outLen);
  padded.setAll(outLen - inputBytes.length, inputBytes);

  final output = Uint8List(engine.outputBlockSize);
  engine.processBlock(padded, 0, outLen, output, 0);
  return bytesToHex(output);
}

// ============================================================
// WEAPI — full encryption chain
// ============================================================

/// Returns `{ params: base64<string>, encSecKey: hex<256 chars> }`.
///
/// For testing, pass [secretKey] to get deterministic output matching
/// golden vectors. In production, a random 16-char key is generated.
Map<String, String> weapi(Map<String, dynamic> object, {String? secretKey}) {
  final text = jsonEncode(object);

  // Layer 1: AES-128-CBC(presetKey, iv) → base64 string
  final layer1 = _aesCbcEncrypt(text, presetKey, iv);

  // 16 random chars from base62 alphabet (or overridden for testing)
  secretKey ??= randomString(16);

  // Layer 2: AES-128-CBC(secretKey, iv) → encrypts the layer1 base64 string
  final params = _aesCbcEncrypt(layer1, secretKey, iv);

  // RSA encrypt the reversed secretKey
  final reversedKey = secretKey.split('').reversed.join();
  final pubKey = _rsaPublicKey ??= _parsePublicKey(rsaPublicKeyPem);
  final encSecKey = _rsaEncrypt(reversedKey, pubKey);

  return {
    'params': params,
    'encSecKey': encSecKey,
  };
}

// Lazy-loaded parsed RSA public key
RSAPublicKey? _rsaPublicKey;
