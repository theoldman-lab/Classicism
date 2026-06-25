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

## Next → Phase 1: Dart Crypto Layer

- [ ] `eapi.dart` — MD5 + AES-128-ECB encrypt/decrypt
- [ ] `weapi.dart` — AES-128-CBC×2 + RSA-1024
- [ ] Unit tests against known JS output vectors
