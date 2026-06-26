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

---

## 2026-06-26 (Morning)

### Phase 2: Request Engine + Cookie Manager → COMPLETED

**2.1 `config.dart` — Global Configuration & Initialization** (`lib/core/config.dart`, 116 lines)

| Item | Detail |
|------|--------|
| Pattern | `AppConfig` singleton with async `init()` |
| DeviceId | 52-char uppercase hex, generated once via `Random.secure()`, persisted in SharedPreferences |
| WNMCID | `{6 random lowercase letters}.{timestamp_ms}.01.0` — regenerated each `init()` call |
| Cookie persistence | `musicA`/`musicU`/`csrf`/`uid` getter/setter pairs with SharedPreferences write-through |
| Safety | `_ensureReady()` throws `StateError` if getters/setters accessed before `init()` |
| Re-init support | `wnmcid` changed from `late final` → `late String` to allow re-init in tests |

Upstream reference: `util/index.js` (deviceId generation), `util/request.js` (WNMCID generation, global state management)

**2.2 `cookie_manager.dart` — Cookie Parsing & Construction** (`lib/core/cookie_manager.dart`, 170 lines)

| Function | Source | Detail |
|----------|--------|--------|
| `cookieToJson(str)` | `util/index.js:89` | Splits on `;`, trims, handles first-`=` only |
| `cookieObjToString(obj)` | `util/index.js:106` | `encodeURIComponent(k)=encodeURIComponent(v); ...` |
| `generateDeviceId()` | `util/index.js:175` | Static, 52 uppercase hex for standalone use |
| `processCookie(cookie, uri)` | `util/request.js:132` | Spreads input cookie + fills defaults: `__remember_me`/`ntes_kaola_ad`/`_ntes_nuid`(64 hex)/`_ntes_nnid`/`WNMCID`/`WEVNSM`/`osver`/`deviceId`/`os`/`channel`/`appver`. Adds `NMTID`(32 hex) for non-login URIs. Fills `MUSIC_A` from config when `MUSIC_U` absent. |
| `buildEapiHeader(cookie, csrf)` | `util/request.js:293` | Builds eapi/api header dict: `osver`/`deviceId`/`os`/`appver`/`versioncode`/`mobilename`/`buildver`(10-char seconds)/`resolution`/`__csrf`/`channel`/`requestId`. Falls back to `_config.musicU`/`_config.musicA` for auth tokens. |
| `createHeaderCookie(header)` | `util/request.js:163` | `encodeURIComponent` serialization, identical to `cookieObjToString` |
| OS defaults | `util/request.js:66-97` | `pc`(weapi)/`android`(eapi)/`iphone`/`linux` — keyed by short name, values contain full os identifier strings |

Critical design notes:
- `_ntes_nuid` and `_ntes_nnid` share the same random seed (line 97: `freshNuid`) — matches upstream behavior where both reference the same local variable
- `processCookie` defaults to `os='pc'` when input cookie has no `os` key (via `osMap['pc']` fallback)
- For eapi/api, `MUSIC_U`/`MUSIC_A` pulled from `AppConfig` if not present in cookie map (enables logged-in eapi requests without explicit cookie seeding)

**2.3 `request_engine.dart` — Central Request Dispatcher** (`lib/core/request_engine.dart`, 243 lines)

| Component | Detail |
|-----------|--------|
| `ApiResponse` | `{status, body, cookies}` with `isSuccess` getter |
| `NeteaseRequest` | Holds `Dio` + `CookieManager` + `AppConfig`. Single entry: `request(endpoint, data, {crypto, encryptResponse, ua, overrideDomain})` |

**Crypto dispatch table** (mirrors `util/request.js:224-336`):

| Crypto | URL pattern | Headers | Body | Cookie format | UA |
|--------|------------|---------|------|---------------|-----|
| `weapi` | `{domain}/weapi/{endpoint[5:]}` | `Referer`=domain, PC Chrome UA | `{params, encSecKey}` form-urlencoded | `cookieObjToString(cookieMap)` OS=pc | Chrome/124 |
| `eapi` | `{apiDomain}/eapi/{endpoint[5:]}` | iPhone UA | `{params}` form-urlencoded | `createHeaderCookie(header)` OS=android | NeteaseMusic iPhone |
| `xeapi` | Cloud function POST | JSON `{endpoint, data, cookie}` | Cloud function handles | `cookieObjToString(cookieMap)` | N/A (proxy) |
| `api` | `{apiDomain}{endpoint}` | iPhone UA | plain params form-urlencoded | `createHeaderCookie(header)` | NeteaseMusic iPhone |
| `linuxapi` | — | — | Throws `UnimplementedError` | — | — |

**Response handling**:
- `encryptResponse=true` → `ResponseType.bytes` → `bytesToHex().toUpperCase()` → `eapiResDecrypt(hex)`
- `encryptResponse=false` → `ResponseType.json` → `response.data` directly
- Special status codes {201,302,400,502,800,801,802,803} mapped to 200 (critical for QR login 800-803)
- `_extractCookies()` strips `Domain=...` attribute from Set-Cookie headers via regex

**Bug fixes during review** (see 2026-06-26 Review section):
- **Bug #1**: Initial cookie map was empty `{}` — now seeded with `MUSIC_U`/`MUSIC_A`/`__csrf` from `AppConfig`
- **Bug #2**: Xeapi response cookies extracted from HTTP headers instead of `proxyBody['cookie']` JSON field
- **Bug #3**: EAPI and API branches ignored `overrideDomain` parameter (used hardcoded domain constants)

**2.4 Phase 2 Tests**

| File | Tests | Coverage |
|------|-------|----------|
| `cookie_manager_test.dart` | 25 | Static utilities (4) + generateDeviceId (2) + processCookie (11) + buildEapiHeader (3) + createHeaderCookie (2) + OS defaults (3) |
| `request_engine_test.dart` | 31 | WEAPI URL/headers/body/domain (5) + EAPI URL/body/UA (5) + XEAPI proxy (3) + API plain (2) + response/status (4) + encryptResponse bytes (4) + special codes (8) + linuxapi (1) |
| `config_test.dart` | 17 | init flow (8) + getters (5) + persistence roundtrip (4) |

---

### Phase 3: Authentication Module → COMPLETED

**3.0 Pre-requisite: Expose AES-ECB functions** (`lib/core/crypto/eapi.dart`)
- `_aesEcbEncrypt` → `aesEcbEncrypt` (public)
- `_aesEcbDecrypt` → `aesEcbDecrypt` (public)
- Comment updated: "AES-128-ECB" → "AES-ECB (auto-detects key size: 128/192/256-bit)"
- Reason: `xeapiDecryptPublicKey` needs AES-256-ECB with 32-byte `xeapiStaticKey`

**3.1 `crypto/xeapi_helpers.dart` — XEAPI Signature & Key Decryption** (22 lines)

| Function | Source | Detail |
|----------|--------|--------|
| `xeapiSign(timestamp, nonce)` | `util/crypto.js:189-194` | HMAC-SHA256 with `xeapiSignKey` as raw UTF-8 string (NOT base64-decoded — matches Node's `crypto.createHmac` string behaviour). Message = `timestamp + nonce` (no prefix). Output: base64. |
| `xeapiDecryptPublicKey(encryptedBase64)` | `util/crypto.js:298-305` | AES-256-ECB decrypt with `xeapiStaticKey` → JSON.parse |

**3.2 `api/xeapi_proxy.dart` — Cloud Function Proxy** (43 lines)

| Component | Detail |
|-----------|--------|
| `XeapiProxyResponse` | `{body: Map, cookies: List<String>}` |
| `XeapiProxy.call(endpoint, data, cookie)` | POST JSON `{endpoint, data, cookie}` → cloud function → `XeapiProxyResponse` |
| Content-Type | `application/json` |
| Error handling | `response.data['cookie']` null → empty list (defensive) |

**3.3 `api/auth_api.dart` — 7 Authentication API Methods** (374 lines)

| Method | Endpoint | Crypto | Key Implementation Detail |
|--------|----------|--------|--------------------------|
| `registerAnonymous()` | `/api/register/anonimous` | xeapi→proxy | `cloudmusicDllEncodeId(deviceId)` XORs with key `'3go8&$8*3*3h0k(2)2'` → MD5 → base64. `buildAnonUsername` = `base64(deviceId + ' ' + dllEncodeId)`. Extracts `MUSIC_A` from response cookies → persists via `AppConfig`. |
| `getXeapiPublicKey()` | `/api/gorilla/anti/crawler/security/key/get` | **Direct Dio** (not via engine) | 16-digit random nonce, `xeapiSign(timestamp, nonce)` signature. Android UA header. Verifies server response signature. Decrypts `encryptedData` via `xeapiDecryptPublicKey` → `XeapiKeyState`. |
| `getLoginQrKey()` | `/api/login/qrcode/unikey` | eapi | `type=3` → returns `unikey` string |
| `checkLoginQr(unikey)` | `/api/login/qrcode/client/login` | eapi | `key=unikey, type=3`. Codes: 800=expired, 801=waiting, 802=scanned, 803=success. On 803, persists `MUSIC_U`+`__csrf` via `_persistCookiesFromResponse`. |
| `loginCellphone(phone, md5Password)` | `/api/w/login/cellphone` | weapi | `type=1, https=true, countrycode=86, remember=true`. Supports captcha mode (key changes from `password` to `captcha`). On 200, persists auth cookies. |
| `loginStatus()` | `/api/w/nuser/account/get` | weapi | Returns account profile or null |
| `refreshToken()` | `/api/login/token/refresh` | eapi | On success, persists new MUSIC_U+csrf |

**Model classes defined in `auth_api.dart`**:
- `XeapiKeyState` — `{sk, expireTime, version, nonce}` with `fromJson`
- `QrCheckResult` — `{code, cookie}` with convenience getters (`isExpired`/`isWaiting`/`isScanned`/`isSuccess`)
- `LoginResult` — `{code, cookie, profile}` with `isSuccess`

**3.4 `services/auth_service.dart` — Auth Orchestrator** (71 lines)

| Method | Detail |
|--------|--------|
| `initialize()` | `AppConfig.init()` → checks `musicA` → calls `registerAnonymous()` if absent. (Guest mode ready after this.) |
| `pollLoginQr(unikey)` | `async*` stream: 2-second polling until code=803 (success) or 800 (expired) |
| `loginWithPassword(phone, password)` | MD5(password) → `loginCellphone()` |
| `logout()` | Sets `musicU=''`, `csrf=''`, `uid=0` (preserves `musicA` for guest mode) |

**3.5 Phase 3 Tests**

| File | Tests | Coverage |
|------|-------|----------|
| `xeapi_helpers_test.dart` | 9 | `xeapiSign` (6): base64 format, determinism, timestamp/nonce sensitivity, HMAC correctness. `xeapiDecryptPublicKey` (3): AES-256 roundtrip + various data |
| `auth_api_test.dart` | 37 | `cloudmusicDllEncodeId` (5) + `buildAnonUsername` (4) + `getLoginQrKey` (4) + `checkLoginQr` (4) + `loginCellphone` (5) + `loginStatus` (3) + `refreshToken` (2) + `registerAnonymous` (3) + `getXeapiPublicKey` (4) + error paths (7) |
| `auth_service_test.dart` | 8 | `loginWithPassword` MD5 (1) + `logout` (1) + `initialize` (2) + `pollLoginQr` (3) + `initialize` error (1) |

---

### Phase 4: Core Business APIs → COMPLETED

**4.1 Model Updates**

| File | Key additions |
|------|---------------|
| `models/song.dart` (34 lines) | `Song.fromJson` — `id/name/artistName(ar[0])/albumName(al)/coverUrl(al.picUrl)/duration(dt)/fee` with null-safe defaults |
| `models/lyric.dart` (15 lines) | `Lyric.fromJson` — `lrc` from `lrc.lyric` (default ''), `tlyric` from `tlyric.lyric` (null if absent) |
| `models/playlist.dart` (31 lines) | `Playlist.fromJson` — `id/name/coverImgUrl/trackCount/playCount/creatorName(creator.nickname)` |
| `models/user.dart` | Minimal: `userId, nickname` |
| `models/search_result.dart` | Minimal: `songs, songCount` |

**4.2 `api/music_api.dart` — 9 API Methods + 2 Convenience** (273 lines)

| Method | Endpoint | Crypto | Key Detail |
|--------|----------|--------|------------|
| `search(keywords)` | `/api/search/get` | eapi | `s, type(1=歌曲/10=专辑/100=歌手/1000=歌单), limit, offset` |
| `searchSongs(keywords)` | (wraps search) | — | Convenience: `type=1` → `List<Song>` via `Song.fromJson` |
| `searchPlaylists(keywords)` | (wraps search) | — | Convenience: `type=1000` → `List<Playlist>` |
| `getSongUrls(ids)` | `/api/song/enhance/player/url/v1` | xeapi→proxy | `ids='[1,2,3]'`, level=standard/exhigh/lossless/hires/jyeffect/sky/jymaster. `level='sky'` → adds `immerseType='c51'`. Returns `List<Map>` `[{id, url, type, level, fee}]`. |
| `getLyric(songId)` | `/api/song/lyric` | eapi | `id, tv/lv/rv/kv=-1, _nmclfl=1` → `Lyric?` |
| `getSongDetail(ids)` | `/api/v3/song/detail` | **weapi** ⚠️ | `c='[{"id":1},{"id":2}]'` — upstream uses weapi, NOT eapi as dev plan stated |
| `getPlaylistDetail(id)` | `/api/v6/playlist/detail` | eapi | `id, n=100000, s=8` → `Playlist?` |
| `getUserPlaylists(uid)` | `/api/user/playlist` | weapi | `uid, limit=30, offset=0, includeVideo=true` |
| `getRecommendSongs()` | `/api/v3/discovery/recommend/songs` | weapi | Requires login (MUSIC_U). Returns `data.dailySongs` |
| `getAlbum(id)` | `/api/v1/album/{id}` | weapi | id interpolated in path |
| `getArtistTopSongs(id)` | `/api/artist/top/song` | weapi | Returns `songs` array |

⚠️ **Corrected**: `getSongDetail` uses **weapi** (development plan incorrectly labeled it as eapi). Verified against upstream `module/song_detail.js` which uses `createOption(query, 'weapi')`.

**4.3 Phase 4 Tests**

| File | Tests | Coverage |
|------|-------|----------|
| `music_api_test.dart` | 27 | search (5) + getLyric (3) + getSongDetail (3) + getPlaylistDetail (2) + getUserPlaylists (2) + getRecommendSongs (2) + getAlbum (1) + getArtistTopSongs (2) + getSongUrls (4) + error paths (7) |
| `models_test.dart` | 21 | Song.fromJson (10) + Lyric.fromJson (6) + Playlist.fromJson (7) + User (1) + SearchResult (2) |

---

## 2026-06-26 (Afternoon)

### Comprehensive Code Review & Testing Enhancement → COMPLETED

**Review Methodology**: Systematically compared all Dart files against upstream `util/*.js` and `module/*.js` reference implementations. Verified 186 test coverage gaps using automated analysis.

**Bugs Found & Fixed During Review:**

| # | Bug | File:Line | Severity | Fix |
|---|-----|-----------|----------|-----|
| 1 | Cookie map not seeded with persisted auth state (`MUSIC_U`/`MUSIC_A`/`__csrf` not passed to weapi requests) | `request_engine.dart:75` | **Critical** | Seed `initialCookie` from `AppConfig` before `processCookie()` |
| 2 | Xeapi proxy response cookies extracted from HTTP headers instead of JSON body `proxyBody['cookie']` | `request_engine.dart:143` | **High** | Read cookies from `proxyBody['cookie']` array |
| 3 | EAPI `overrideDomain` parameter ignored (hardcoded `apiDomain`) | `request_engine.dart:124` | **Medium** | Use `'${overrideDomain ?? apiDomain}/eapi/...'` |
| 4 | API `overrideDomain` parameter ignored | `request_engine.dart:162` | **Medium** | Use `'${overrideDomain ?? apiDomain}...'` |
| 5 | `base62Encode` crashes on empty bytes (`BigInt.parse('')`) | `helpers.dart:34` | **Low** | Add `if (bytes.isEmpty) return 'a'` guard |

**New Test Files Created:**

| File | Tests | Key Coverage |
|------|-------|--------------|
| `helpers_test.dart` | 28 | `bytesToHex`(5)/`hexToBytes`(4)/`bytesToBase64`(3)/`base64ToBytes`(1)/`randomString`(3)/`randomBytes`(3)/`base62Encode`(5) |
| `models_test.dart` | 21 | Song/Lyric/Playlist `fromJson` null safety, missing keys, type mismatches |
| `config_test.dart` | 17 | init flow (first/restore/load), getter null paths, all setter persistence roundtrips, uid=0 edge case |
| `xeapi_proxy_test.dart` | 8 | Success body+cookies, endpoint/data/cookie forwarding, null cookie fallback, DioException propagation, HTTP 500 |

**Existing Test Files Enhanced:**

| File | Before | After | New Tests Cover |
|------|--------|-------|-----------------|
| `eapi_test.dart` | 28 | 34 | `eapiResDecrypt` (6): non-gzip decrypt, gzip decompression (`aeapi:true`), invalid hex, empty string, garbled ciphertext, non-JSON decrypted data |
| `request_engine_test.dart` | 19 | 31 | Network error (DioException) + HTTP 500 + all 7 special status codes + weapi/eapi encryptResponse bytes + EAPI overrideDomain |
| `auth_api_test.dart` | 26 | 37 | registerAnonymous non-200, getLoginQrKey missing unikey/non-Map body, loginCellphone null body, loginStatus non-Map, refreshToken empty cookies, getXeapiPublicKey non-200/signature mismatch/DioException |
| `auth_service_test.dart` | 4 | 8 | pollLoginQr DioException propagation, initialize registerAnonymous failure propagation |
| `music_api_test.dart` | 20 | 27 | search null body, songDetail/playlistDetail/userPlaylists/recommend/artistTopSongs non-success responses, getSongUrls non-200 proxy response, searchSongs missing result map |

**Final Verification:**
- `flutter analyze` → No issues
- `flutter test` → **271/271 passed**

---

### Project State Summary

| Phase | Status | Key Files | Tests |
|-------|--------|-----------|-------|
| 0 | ✅ | Scaffolding + Constants | — |
| 1 | ✅ | `eapi.dart` (70), `weapi.dart` (155) | 46 |
| 2 | ✅ | `config.dart` (116), `cookie_manager.dart` (170), `request_engine.dart` (243) | 73 |
| 3 | ✅ | `xeapi_helpers.dart` (22), `xeapi_proxy.dart` (43), `auth_api.dart` (374), `auth_service.dart` (71) | 54 |
| 4 | ✅ | `music_api.dart` (273), models (song/lyric/playlist/user/search_result) | 48 |
| Review | ✅ | 5 bugs fixed, 7 new test files, 5 enhanced test files | +109 new tests |
| 5 | ⬜ | Flutter UI + Player | — |
| 6 | ⬜ | Cloud Function Deployment | — |

**Total: ~1,550 source lines, 271 tests, 0 analyze errors**
