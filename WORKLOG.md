# Worklog — Classicism

## 2026-06-25

### Phase 0: Project Scaffolding & Constants → COMPLETED

**0.1 Flutter Project Initialization**
- Created `app/` via `flutter create --org com.classicism --platforms android`
- Flutter 3.41.6, Dart SDK ^3.11.4

**0.2 Dependencies (`pubspec.yaml`)**
```
dio 5.9.2              — HTTP client
pointycastle 3.9.1     — AES / RSA
crypto 3.0.7           — MD5 / HMAC-SHA256
shared_preferences     — cookie persistence
just_audio             — audio playback
qr_flutter             — QR code generation
flutter_riverpod       — state management
json_annotation / json_serializable / build_runner — models
```
All `flutter pub get` — no conflicts.

**0.3 Constants (`lib/core/crypto/constants.dart`)**
- Extracted all from `util/crypto.js`, `util/config.json`, `util/request.js`:
  - AES keys: iv, presetKey, eapiKey, linuxapiKey
  - RSA public key (1024-bit PEM) — verified byte-level match with upstream
  - XEAPI: xeapiStaticKey (32B), xeapiSignKey, x25519SpkiPrefix (12B)
  - Base62 alphabet, eapi delimiter (`-36cd479b6b5-`)
  - API domains ×5, resourceTypeMap, clientSign, checkToken
  - Eapi header defaults: platform/android/osver/appver/versioncode/resolution/channel

**0.4 Helpers (`lib/core/crypto/helpers.dart`)**
- `hex↔bytes`, `base64↔bytes`, `randomString`, `randomBytes`, `base62Encode`

**0.5 Directory Skeleton**
```
app/lib/
├── main.dart                       ← Material3 + Riverpod entry
├── core/
│   ├── crypto/ [constants, helpers, weapi, eapi]
│   ├── cookie_manager.dart
│   ├── request_engine.dart
│   └── config.dart
├── api/ [auth_api, music_api, xeapi_proxy]
├── models/ [song, playlist, lyric, user, search_result]
├── services/ [auth_service, player_service]
└── state/ [providers]
```

**0.6 Verification**
- `flutter analyze` → No issues
- `flutter test` → All tests passed
- Reviewed: 4 bugs found & fixed (linuxapiKey, defaultAppver, defaultResolution, missing eapiDelimiter)
- Cross-referenced every constant against upstream source

---

### Phase 1: Dart Crypto Layer → COMPLETED

**1.0 Golden Vector Generation**
- Script: `scripts/gen_golden_vectors.js` (252 lines)
  - Deterministic PRNG for mocking `Math.random` in weapi (seed=12345)
  - Exports 17 test vectors to `test/golden_vectors.json`
  - Copied to `app/test/golden_vectors.json` for Dart consumption
- Vector coverage:
  - MD5 ×4  — empty, hello, eapi_digest_search (English), eapi_digest_chinese
  - EAPI ×8  — search (EN/CN), qr_key, qr_check, song_detail, playlist_detail, lyric, empty_object
  - WEAPI ×4 — login_cellphone, login_status, user_playlist, recommend_songs
  - AES ECB ×4 — ecb_hello, ecb_json, ecb_16bytes, ecb_eapi_data
  - AES CBC ×3 — cbc_hello, cbc_json, cbc_double
  - RSA ×2   — fixed key `0123456789abcdef` and `abcdefghijklmnop`
- All weapi golden vectors verified: `paramsMatchLayer2: true` (manual layer2 = crypto.weapi output)
- Critical discovery: weapi layer2 encrypts the layer1 **base64 string** (as UTF-8), NOT raw ciphertext bytes

**1.1 eapi.dart** (`lib/core/crypto/eapi.dart`, 54 lines)
- Functions ported:
  - `_aesEcbEncrypt(Uint8List, Uint8List)` → pointycastle `PaddedBlockCipherImpl(PKCS7Padding, ECBBlockCipher(AESEngine))`
  - `_aesEcbDecrypt(Uint8List, Uint8List)` — same, reverse mode
  - `eapi(url, Map)` → `{ params: uppercaseHex }` — MD5 digest generation, ECB encrypt
  - `eapiResDecrypt(hex, {aeapi})` → parsed JSON | null — AES-ECB decrypt + optional gzip
- pointycastle 3.9 API change: `PaddedBlockCipherImpl.init()` requires `PaddedBlockCipherParameters<KeyParameter, CipherParameters>(KeyParameter(key), null)`
- Tests (28 of 46):
  - MD5 ×4: all match CryptoJS output byte-for-byte
  - AES-ECB encrypt ×4: plaintext → hex matches CryptoJS
  - AES-ECB decrypt ×4: hex → plaintext roundtrip
  - EAPI encrypt ×8: params hex matches Node.js output exactly (including Chinese characters)
  - EAPI decrypt structure ×8: decrypt hex → verify `url-delimiter-data-delimiter-digest` format

**1.2 weapi.dart** (`lib/core/crypto/weapi.dart`, 147 lines)
- Functions ported:
  - `_aesCbcEncryptRaw(Uint8List, Uint8List, Uint8List)` → pointycastle `PaddedBlockCipherImpl` + `ParametersWithIV<KeyParameter>` + `CBCBlockCipher(AESEngine)` → returns raw encrypted bytes
  - `_aesCbcEncrypt(String, String, String)` → `_aesCbcEncryptRaw` + base64.encode → returns base64 string (matches CryptoJS `encrypted.toString()`)
  - `_parsePublicKey(String pem)` → `RSAPublicKey(BigInt n, BigInt e)` — manual ASN.1 DER parser
    - Strips PEM armor → base64 decode → parse DER (SEQUENCE → SEQUENCE → BIT STRING → SEQUENCE → INTEGER n | INTEGER e)
    - Tag-length-value parsing with multi-byte length support
    - BigInt constructed via `(result << 8) | byte`
  - `_rsaEncrypt(String, RSAPublicKey)` → lowercase hex — `RSAEngine.init(PublicKeyParameter)` + left-pad 128 bytes + `processBlock`
  - `weapi(Map, {secretKey?})` → `{ params: base64, encSecKey: hex256 }`
    - Layer 1: `AES-CBC(jsonText, presetKey, iv)` → base64 string
    - Layer 2: `AES-CBC(layer1Base64String, secretKey, iv)` → base64 string (KEY: encrypts base64 STRING as UTF-8, not raw ciphertext)
    - RSA: `secretKey.reversed` → `_rsaEncrypt(reversedKey, pubKey)`
  - Optional `secretKey` parameter for deterministic testing

- RSA `processBlock` detail:
  - `inputBlockSize` for encryption = 127 (RSAEngine reserves 1 byte)
  - Our 16-byte input left-padded to 128 bytes: `padded.setAll(128 - 16, inputBytes)`
  - `outputBlockSize` = 128 bytes → hex = 256 chars
  - Zero-padding on the LEFT ensures BigInt interpretation matches node-forge's raw RSA

- Tests (18 of 46):
  - AES-CBC encrypt ×3: plaintext → base64 matches CryptoJS
  - RSA ×2: fixed secretKey → encSecKey matches golden vectors (256 hex chars)
  - WEAPI golden ×4: full chain with deterministic secretKey, params + encSecKey match
  - WEAPI layer1 ×4: first-layer CBC output verified independently
  - WEAPI layer2 ×4: second-layer CBC output verified (base64 string → UTF-8 → encrypt)

**1.3 Test Architecture**
- `test/eapi_test.dart` (110 lines) — 28 tests
- `test/weapi_test.dart` (130 lines) — 18 tests
- Both read `test/golden_vectors.json` at group-scope (not via setUpAll, avoids late initialization in for-loops)
- Golden vector structure:
```json
{
  "md5": { "name": { "input": "...", "digest": "..." } },
  "aes": { "name": { "mode": "ECB|CBC", "key": "...", "plaintext": "...", "ciphertextHex|Base64": "..." } },
  "eapi": { "name": { "url": "...", "data": {...}, "params": "...", "decryptedStructure": "..." } },
  "weapi": { "name": { "data": {...}, "layer1_base64": "...", "layer2_base64": "...", "params": "...", "encSecKey": "...", "secretKey": "...", "secretKeyReversed": "..." } },
  "rsa": { "name": { "input": "...", "encryptedHex": "..." } }
}
```

**Final verification**
- `flutter analyze` → No issues (only intentional warnings for unused vars)
- `flutter test` → 46/46 passed (28 eapi + 18 weapi)
- Cross-reference: all golden vectors generated from verified `crypto.js` → Dart output matches byte-for-byte

## Next → Phase 2: Request Engine + Cookie Manager
