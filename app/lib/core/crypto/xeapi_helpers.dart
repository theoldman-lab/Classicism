import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'constants.dart';
import 'eapi.dart';

String xeapiSign(String timestamp, String nonce) {
  final keyBytes = utf8.encode(xeapiSignKey);
  final hmac = crypto.Hmac(crypto.sha256, keyBytes);
  final digest = hmac.convert(utf8.encode('$timestamp$nonce'));
  return base64.encode(digest.bytes);
}

Map<String, dynamic> xeapiDecryptPublicKey(String encryptedBase64) {
  final ciphertext = Uint8List.fromList(base64.decode(encryptedBase64));
  final plaintext = aesEcbDecrypt(ciphertext, xeapiStaticKey);
  return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
}
