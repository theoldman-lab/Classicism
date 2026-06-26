import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

String bytesToHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Uint8List hexToBytes(String hex) {
  final result = <int>[];
  for (int i = 0; i < hex.length; i += 2) {
    result.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(result);
}

String bytesToBase64(Uint8List bytes) => base64.encode(bytes);

Uint8List base64ToBytes(String str) => Uint8List.fromList(base64.decode(str));

String randomString(int length) {
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final rng = Random.secure();
  return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
}

Uint8List randomBytes(int length) {
  final rng = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
}

String base62Encode(Uint8List bytes) {
  if (bytes.isEmpty) return 'a';
  const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  var value = BigInt.parse(bytesToHex(bytes), radix: 16);
  if (value == BigInt.zero) return alphabet[0];
  final result = StringBuffer();
  while (value > BigInt.zero) {
    result.write(alphabet[(value % BigInt.from(62)).toInt()]);
    value = value ~/ BigInt.from(62);
  }
  return result.toString().split('').reversed.join();
}
