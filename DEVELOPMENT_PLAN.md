# 详细开发计划

## 方案选择：B — 最小 XEAPI 代理 + 主体本地化

> 方案 A（全本地 FFI）需用 `dart:ffi` 调用 libsodium 实现 X25519 ECDH，开发成本高、调试困难。
> **方案 B** 仅在 3 个 `xeapi` 端点使用云函数中转，其余 10+ MVP 端点全部 Dart 直连，务实可行。

---

## Phase 0：项目脚手架 & 常量定义 ✅

> **状态：DONE** （2026-06-25）
> 产出：`app/` Flutter 项目，`flutter analyze` 零错误，`flutter test` 通过

**目标**：搭建 Flutter 项目骨架，准备所有密钥常量。

### 0.1 Flutter 项目初始化

```bash
flutter create --org com.classicism --project-name classicism --platforms android app
```
实际创建在 `app/` 子目录下，与上游参考代码（`module/`、`util/`）隔离。

### 0.2 依赖安装 (pubspec.yaml)

```yaml
dependencies:
  dio: ^5.4.0              # → resolved 5.9.2
  pointycastle: ^3.7.3     # → resolved 3.9.1
  crypto: ^3.0.3           # → resolved 3.0.7
  shared_preferences: ^2.2.2
  just_audio: ^0.9.36
  qr_flutter: ^4.1.0
  flutter_riverpod: ^2.4.9
  json_annotation: ^4.8.1

dev_dependencies:
  build_runner: ^2.4.8
  json_serializable: ^6.7.1
```

### 0.3 密钥常量文件 `lib/core/crypto/constants.dart`

从 `util/crypto.js` 和 `util/config.json` 和 `util/request.js` 提取所有硬编码常量。
审查发现并修复 4 个 bug：`linuxapiKey` 首字符丢失、`defaultAppver` 版本不完整、`defaultResolution` 不一致、缺少 `eapiDelimiter`。
所有常量与上游逐字节交叉验证通过。

### 0.4 Helpers `lib/core/crypto/helpers.dart`
`hex↔bytes`、`base64↔bytes`、`randomString`、`randomBytes`、`base62Encode`

### 0.5 目录骨架
`app/lib/` 下完整目录结构已创建（core/crypto/、api/、models/、services/、state/、ui/），含 19 个占位文件。

---

## Phase 1：Dart 加密原语层 ✅

> **状态：DONE** （2026-06-25）
> 产出：`eapi.dart` (54行) + `weapi.dart` (147行)，46/46 tests passed，逐字节对照黄金向量

**目标**：完整移植 `weapi()` 和 `eapi()` 函数至 Dart，确保输出与 Node.js 版逐字节一致。

### 1.0 黄金向量生成

- 编写 `scripts/gen_golden_vectors.js` 从 `util/crypto.js` 生成 17 个测试向量
- 使用确定性 PRNG（seed=12345）mock `Math.random` 确保 weapi 可重复
- 17 向量：MD5×4、EAPI×8、WEAPI×4、AES ECB×4、AES CBC×3、RSA×2
- 关键发现：weapi 第2层加密的输入是第1层 base64 **字符串的 UTF-8 字节**，不是原始 ciphertext 字节

### 1.1 `eapi.dart` (54 lines) — 难度：低 | 实际 1.5h

| 函数 | 实现 | 验证 |
|---|---|---|
| `_aesEcbEncrypt` | `PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()))` | 4 gold vectors |
| `_aesEcbDecrypt` | 同上，解密模式 | 4 roundtrips |
| `eapi(url, data)` | MD5 digest → ECB encrypt → uppercase hex | 8 gold vectors (含中文) |
| `eapiResDecrypt(hex)` | ECB decrypt → optional gzip → JSON.parse | structure 验证 |

**pointycastle 3.9 API 注意**：`PaddedBlockCipherImpl.init()` 需 `PaddedBlockCipherParameters<KeyParameter, CipherParameters>(key, null)`

### 1.2 `weapi.dart` (147 lines) — 难度：中 | 实际 3.5h

| 函数 | 实现 | 验证 |
|---|---|---|
| `_aesCbcEncrypt` | `PaddedBlockCipherImpl` + `ParametersWithIV<KeyParameter>` + `CBCBlockCipher` → base64 | 3 gold vectors |
| `_parsePublicKey(pem)` | 手动 ASN.1 DER 解析：PEM→base64→DER→SEQUENCE→INTEGER(n)→INTEGER(e) | 间接（通过 RSA） |
| `_rsaEncrypt(text, key)` | `RSAEngine.init(PublicKeyParameter)` + 左填零至128字节 + `processBlock` → lowercase hex | 2 gold vectors (256 hex chars) |
| `weapi(data, {secretKey})` | 二层 AES-CBC + RSA reversed key | 4 gold vectors |

**RSA NONE padding 实现**：`inputBlockSize`=127 字节（加密模式），输入 16 字节左填零至 128 字节。`outputBlockSize`=128 字节 → hex=256 字符，与 node-forge 输出逐位一致。

**ASN.1 DER 解析**：手动实现 tag-length-value 读取，支持多字节长度（≥0x80）。PEM→DER 路径：`SEQUENCE` → `SEQUENCE(AlgorithmIdentifier)` skip → `BIT STRING` → `SEQUENCE` → `INTEGER(n)` → `INTEGER(e)`。

### 1.3 测试

| 测试文件 | 测试数 | 覆盖 |
|---|---|---|
| `test/eapi_test.dart` | 28 | MD5×4 + AES-ECB×8 + EAPI encrypt×8 + EAPI decrypt×8 |
| `test/weapi_test.dart` | 18 | AES-CBC×3 + RSA×2 + WEAPI golden×4 + WEAPI layers×8 |

所有测试读取 `test/golden_vectors.json`（由 1.0 生成），逐字节对照 Node.js 黄金输出。

---

## Phase 2：请求引擎 + Cookie 管理

**目标**：实现 `NeteaseRequest` 类，统一调度加密、HTTP、响应处理。

### 2.1 `cookie_manager.dart` — 预计 1h

从 `util/index.js` 移植：

| 函数 | 说明 |
|---|---|
| `cookieToJson(cookie)` | `"MUSIC_A=xxx; os=pc"` → `{ MUSIC_A: 'xxx', os: 'pc' }` |
| `cookieObjToString(obj)` | `{ MUSIC_A: 'xxx' }` → `"MUSIC_A=xxx"` (含 encodeURIComponent) |
| `generateDeviceId()` | 52位随机 hex 字符串 |

### 2.2 `request_engine.dart` — 预计 3h

从 `util/request.js` 移植核心调度逻辑：

```dart
class NeteaseRequest {
  final Dio _dio;
  final CookieManager _cookie;

  Future<ApiResponse> request(
    String method,    // 'POST' | 'GET'
    String endpoint,  // '/api/search/get'
    Map<String, dynamic> data,
    { Crypto crypto = Crypto.eapi,
      bool encryptResponse = false,
      String? ua }
  ) async {
    // 1. 补充 cookie (deviceId, MUSIC_A, osver, 等)
    final cookie = _cookie.buildCookie();

    // 2. 根据 crypto 类型选择加密路径
    final body = switch (crypto) {
      Crypto.weapi => _weapiRequest(endpoint, data, cookie),
      Crypto.eapi  => _eapiRequest(endpoint, data, cookie),
      Crypto.xeapi => _xeapiProxyRequest(endpoint, data, cookie),
      Crypto.api   => _plainRequest(endpoint, data),
    };

    // 3. 发送请求
    final response = await _dio.post(...);

    // 4. 处理 Set-Cookie 响应头
    _cookie.mergeCookies(response);

    // 5. 解密响应（如果需要）
    final decoded = switch (crypto) {
      Crypto.weapi when encryptResponse => eapiResDecrypt(response.body),
      Crypto.eapi  when encryptResponse => eapiResDecrypt(response.body),
      _ => jsonDecode(response.body),
    };

    return ApiResponse(body: decoded, cookie: _cookie.current);
  }
}
```

**各加密路径差异表**：

| Crypto | URL 前缀 | Content-Type | Body 字段 | Cookie 格式 |
|--------|---------|--------------|-----------|-------------|
| `weapi` | `/weapi/` | `application/x-www-form-urlencoded` | `params` + `encSecKey` | OS=pc 且 URL-encoded |
| `eapi` | `/eapi/` | `application/x-www-form-urlencoded` | `params` | OS=android |
| `xeapi` | `/xeapi/` | `application/json` | `{ B, S, R }` | 云函数内部处理 |
| `api` | `/api/` | `application/x-www-form-urlencoded` | `params` | 普通 |

### 2.3 设备指纹生成

```dart
Map<String, String> buildDeviceFingerprint() {
  return {
    'os': 'android',
    'osver': '14',
    'appver': '8.20.20.231215173437',   // ← 必须与上游 osMap 一致
    'versioncode': '140',
    'mobilename': '',
    'buildver': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'resolution': '1920x1080',
    '__csrf': _csrf,
    'channel': 'xiaomi',
    'requestId': '${DateTime.now().millisecondsSinceEpoch}_${random(4)}',
  };
}
```

---

## Phase 3：认证模块

**目标**：实现游客注册 + QR 扫码登录 + 手机号登录 + token 刷新完整链路。

### 3.1 初始化顺序（极关键）

```
1. SharedPreferences 读取 deviceId → 若无则生成并写入
2. SharedPreferences 读取 MUSIC_A → 若无则调用 registerAnonymous()
3. SharedPreferences 读取 xeapiKeyState → 若无则调用 getXeapiPublicKey()
4. 此时可发起所有游客请求
```

### 3.2 `auth_api.dart` — 预计 2h

```dart
class AuthApi {
  final NeteaseRequest _request;

  // 游客注册 → 获取 MUSIC_A [xeapi → 云函数]
  Future<String> registerAnonymous();

  // 获取 X25519 公钥 [xeapi → 云函数]
  Future<XeapiKeyState> getXeapiPublicKey();

  // QR 登录 - 步骤1: 获取 unikey [eapi]
  Future<String> getLoginQrKey();

  // QR 登录 - 步骤2: 轮询扫描状态 [eapi]
  // 返回码: 800=过期 801=等待扫码 802=已扫待确认 803=成功
  Future<QrCheckResult> checkLoginQr(String unikey);

  // 手机号密码登录 [weapi]
  // password 传入前需 MD5
  Future<LoginResult> loginCellphone({
    required String phone,
    required String md5Password,
    String countryCode = '86',
  });

  // 检查登录状态 [weapi]
  Future<bool> loginStatus();

  // 刷新 token [eapi]
  Future<String> refreshToken();
}
```

### 3.3 QR 登录轮询策略

```dart
Stream<QrCheckResult> pollLoginQr(String unikey) async* {
  while (true) {
    final result = await checkLoginQr(unikey);
    yield result;
    if (result.code == 803) break;  // 成功
    if (result.code == 800) break;  // 过期
    await Future.delayed(Duration(seconds: 2));
  }
}
```

### 3.4 手机号登录流程

```
用户输入 phone + password
  → password = MD5(password)  // 纯 MD5，无盐
  → weapi({ phone, password: md5Password, rememberLogin: 'true' })
  → POST /weapi/login/cellphone
  → 响应 cookie 含 MUSIC_U + __csrf
  → 持久化至 SharedPreferences
```

---

## Phase 4：核心业务接口

**目标**：实现搜索、播放、歌词、歌单等核心 API。

### 4.1 `music_api.dart` — 预计 2h

```dart
class MusicApi {
  final NeteaseRequest _request;

  /// 搜索 [eapi]
  /// type: 1=歌曲 10=专辑 100=歌手 1000=歌单 1002=用户
  Future<SearchResult> search(String keywords, {
    int type = 1, int limit = 30, int offset = 0,
  });

  /// 获取歌曲播放链接 [xeapi → 云函数]
  /// level: standard|exhigh|lossless|hires|jymaster
  /// 返回: [{ id, url, type, level, fee, freeTrialInfo }]
  Future<List<SongUrl>> getSongUrls(List<int> ids, {
    String level = 'exhigh',
  });

  /// 获取歌词 [eapi]
  Future<Lyric> getLyric(int songId);

  /// 获取歌曲详情 [eapi]
  Future<List<SongDetail>> getSongDetail(List<int> ids);

  /// 获取歌单详情 [eapi]
  Future<PlaylistDetail> getPlaylistDetail(int playlistId);

  /// 获取用户歌单 [weapi]
  Future<List<Playlist>> getUserPlaylists(int userId);

  /// 每日推荐歌曲 [weapi]
  Future<List<Song>> getRecommendSongs();

  /// 获取专辑 [weapi]
  Future<Album> getAlbum(int albumId);

  /// 获取歌手热门歌曲 [eapi]
  Future<List<Song>> getArtistTopSongs(int artistId);
}
```

### 4.2 各端点速查

| 方法 | 端点 | 加密 | 关键参数 |
|------|------|------|---------|
| `search` | `/api/search/get` | eapi | `s`, `type`, `limit`, `offset` |
| `getSongUrls` | `/api/song/enhance/player/url/v1` | xeapi | `ids` (JSON数组字符串), `level` |
| `getLyric` | `/api/song/lyric` | eapi | `id` (songId) |
| `getSongDetail` | `/api/v3/song/detail` | eapi | `c` (JSON: `'[{"id":123}]'`) |
| `getPlaylistDetail` | `/api/v6/playlist/detail` | eapi | `id`, `n` (返回数量), `s` (偏移,默认0) |
| `getUserPlaylists` | `/api/user/playlist` | weapi | `uid`, `limit`, `offset` |
| `getRecommendSongs` | `/api/v3/discovery/recommend/songs` | weapi | 无 |
| `getAlbum` | `/api/v1/album/{id}` | weapi | id (路径参数) |
| `getArtistTopSongs` | `/api/v1/artist/songs` | eapi | `id`, `private_cloud`, `work_type`, `order`, `offset`, `limit` |

### 4.3 数据模型

```dart
// song.dart
@JsonSerializable()
class Song {
  final int id;
  final String name;
  final List<Artist> ar;
  final Album al;
  final int dt;  // 时长 (ms)
  final int fee; // 0=免费 1=VIP
  // ...
}

// playlist.dart
@JsonSerializable()
class PlaylistDetail {
  final int id;
  final String name;
  final String coverImgUrl;
  final int trackCount;
  final int playCount;
  final List<Song> tracks;
  // ...
}

// lyric.dart
@JsonSerializable()
class Lyric {
  final String? lrc;   // 原始歌词
  final String? tlyric; // 翻译歌词
}
```

---

## Phase 5：Flutter UI + 播放器

### 5.1 页面路由

```
/          → HomePage      (推荐 + 快捷入口)
/search    → SearchPage    (搜索)
/playlist  → PlaylistPage  (歌单详情)
/player    → PlayerPage    (全屏播放器 + 歌词)
/login     → LoginPage     (QR码 + 手机号登录)
```

### 5.2 核心组件

| 组件 | 说明 |
|------|------|
| `MiniPlayer` | 底部迷你播放条（常驻） |
| `SongTile` | 歌曲列表项 |
| `QrCodeLogin` | QR 码登录组件（含轮询） |
| `LyricView` | 歌词滚动视图 |
| `SearchBar` | 搜索输入框 + 热词 |

### 5.3 状态管理 (Riverpod)

```dart
// 认证状态
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(authServiceProvider));
});

// 播放器状态
final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  return PlayerNotifier(ref.read(musicApiProvider));
});

// 搜索状态
final searchProvider = StateNotifierProvider.family<SearchNotifier, SearchState, String>((ref, query) {
  return SearchNotifier(ref.read(musicApiProvider), query);
});
```

### 5.4 播放器实现要点

```dart
// 使用 just_audio 播放远程 URL
final player = AudioPlayer();

Future<void> playSong(Song song) async {
  final urls = await musicApi.getSongUrls([song.id]);
  if (urls.isEmpty || urls.first.url == null) {
    // 无版权或VIP限制
    return;
  }
  await player.setAudioSource(
    AudioSource.uri(Uri.parse(urls.first.url!)),
  );
  player.play();
}
```

**注意**：网易云歌曲 URL 有时效性（通常几小时），需在播放前实时获取。

---

## Phase 6：云函数部署

### 6.1 云函数代码结构

```
xeapi-proxy/
├── api/
│   └── xeapi-proxy.js       # Vercel Serverless Function
├── util/
│   ├── crypto.js            # 从原项目复制
│   ├── config.json          # 从原项目复制
│   └── xeapiKey.js          # 从原项目复制
└── package.json
```

### 6.2 `xeapi-proxy.js` 核心逻辑

```javascript
const { xeapi, registerXeapiKey } = require('./util/crypto');
const axios = require('axios');

module.exports = async (req, res) => {
  const { endpoint, data, cookie } = req.body;

  const encoded = xeapi(endpoint, data, { cookie });

  const response = await axios.post(
    `https://interface.music.163.com/xeapi${endpoint}`,
    encoded,
    { headers: { 'Content-Type': 'application/json' } }
  );

  // xeapi 响应需解密
  const body = xeapiResDecrypt(response.data);

  res.json({ body, cookie: extractCookie(response.headers) });
};
```

### 6.3 部署

```bash
# Vercel
cd xeapi-proxy
vercel deploy --prod

# 环境变量
# 无需任何环境变量（纯透传计算）
```

### 6.4 Flutter 端封装

```dart
class XeapiProxy {
  static const _proxyUrl = 'https://your-proxy.vercel.app/api/xeapi-proxy';

  Future<Map<String, dynamic>> call(
    String endpoint,
    Map<String, dynamic> data,
    String cookie,
  ) async {
    final response = await Dio().post(_proxyUrl, data: {
      'endpoint': endpoint,
      'data': data,
      'cookie': cookie,
    });
    return response.data['body'];
  }
}
```

---

## Phase 7：测试 & 发布

### 7.1 测试策略

| 层 | 测试类型 | 覆盖范围 |
|---|---|---|
| 加密层 | 单元测试 | weapi/eapi 函数输入输出一致性 |
| 请求引擎 | 集成测试 | Cookie 管理、加密分发 |
| 认证 | 集成测试 | 游客注册 → 登录 → 刷新 token |
| 业务 API | 集成测试 | 搜索/歌词/歌单返回格式 |
| UI | Widget测试 | 各页面渲染、状态流转 |

### 7.2 测试结构

```
test/                               # ← 当前已实现
├── golden_vectors.json             # 黄金向量（17 vectors, scripts/gen_golden_vectors.js）
├── eapi_test.dart                  # MD5×4 + AES-ECB×8 + EAPI×16 = 28 tests ✅
└── weapi_test.dart                 # AES-CBC×3 + RSA×2 + WEAPI×12 = 18 tests ✅

test/                               # ← 待实现
├── cookie_manager_test.dart        # Phase 2
├── request_engine_test.dart        # Phase 2
├── auth_api_test.dart              # Phase 3
├── music_api_test.dart             # Phase 4
└── widget/                         # Phase 5
```

### 7.3 发布检查清单

- [ ] `flutter analyze` 零错误
- [ ] `flutter test` 全通过
- [ ] 云函数已部署并验证
- [ ] Release build: `flutter build apk --release`
- [ ] APK 体积 < 30MB
- [ ] 首次启动完整链路验证（安装 → 游客注册 → 搜索 → 试听）
- [ ] 登录链路验证（QR码 / 手机号）
- [ ] 歌曲完整播放验证

---

## 工作量估算

| Phase | 内容 | 预计 | 实际 | 状态 |
|-------|------|------|------|------|
| 0 | 脚手架 + 常量 | 0.5h | 1h | ✅ |
| 1 | Dart 加密原语 | 6h | 5h | ✅ |
| 2 | 请求引擎 + Cookie | 4h | — | ⬜ |
| 3 | 认证模块 | 2h | — | ⬜ |
| 4 | 核心业务接口 | 2h | — | ⬜ |
| 5 | Flutter UI | 8-12h | — | ⬜ |
| 6 | 云函数 | 2h | — | ⬜ |
| 7 | 测试 | 3h | — | ⬜ |
| **总计** | | **约 28-32h** | **6h elapsed** | |

---

## 风险 & 应对

| 风险 | 应对 | 状态 |
|------|------|------|
| ~~pointycastle RSA 无填充模式不支持~~ | 已解决：手动 ASN.1 DER 解析 + `RSAEngine` 左填零至 128 字节 | ✅ |
| X25519 云函数延迟过高 | 使用 Cloudflare Workers（全球边缘节点），延迟 < 100ms | ⬜ |
| 网易云 API 变更 | 跟进上游 `@neteasecloudmusicapienhanced/api` npm 包更新，同步修正 | ⬜ |
| 歌曲 URL 防盗链 | 播放前实时获取 URL，失败则降级尝试其他音质等级 | ⬜ |
| VIP 歌曲限制 (fee=1) | 仅试听 30 秒，UI 清晰标注 | ⬜ |

---

## 扩展路线（Phase 8+）

- [ ] 离线缓存（下载歌曲至本地）
- [ ] 私人 FM / 心动模式
- [ ] 评论浏览与发布
- [ ] 云盘上传
- [ ] 多语言歌词翻译
- [ ] Material You 动态主题
- [ ] iOS 适配
- [ ] 桌面播放通知 / 锁屏控制
