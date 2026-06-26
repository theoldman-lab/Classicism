import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

import 'constants.dart';
import 'helpers.dart';

// ============================================================
// AES-ECB (PKCS7 padding, auto-detects key size: 128/192/256-bit)
// ============================================================

Uint8List aesEcbEncrypt(Uint8List plaintext, Uint8List key) {
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()));
  cipher.init(
      true,
      PaddedBlockCipherParameters<KeyParameter, CipherParameters>(
          KeyParameter(key), null));
  return cipher.process(plaintext);
}

Uint8List aesEcbDecrypt(Uint8List ciphertext, Uint8List key) {
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()));
  cipher.init(
      false,
      PaddedBlockCipherParameters<KeyParameter, CipherParameters>(
          KeyParameter(key), null));
  return cipher.process(ciphertext);
}

// ============================================================
// EAPI — encrypt
// ============================================================

/// Returns `{ params: uppercaseHex }` matching crypto.js eapi() output.
Map<String, String> eapi(String url, Map<String, dynamic> object) {
  final text = jsonEncode(object);
  final message = 'nobody$url${'use'}$text${'md5forencrypt'}';
  final digest = crypto.md5.convert(utf8.encode(message)).toString();
  final data = '$url$eapiDelimiter$text$eapiDelimiter$digest';
  final encrypted =
      aesEcbEncrypt(utf8.encode(data), utf8.encode(eapiKey));
  return {'params': bytesToHex(encrypted).toUpperCase()};
}

// ============================================================
// EAPI — decrypt server response
// ============================================================

/// Decrypts an eapi-encrypted hex response.
/// Set [aeapi] to true if the response is gzip-compressed.
dynamic eapiResDecrypt(String hexParams, {bool aeapi = false}) {
  try {
    final ciphertext = hexToBytes(hexParams);
    final decrypted = aesEcbDecrypt(ciphertext, utf8.encode(eapiKey));

    if (aeapi) {
      final decompressed = gzip.decode(decrypted);
      return jsonDecode(utf8.decode(decompressed));
    } else {
      return jsonDecode(utf8.decode(decrypted));
    }
  } catch (_) {
    return null;
  }
}
