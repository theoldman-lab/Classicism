# 详细开发计划

## 方案选择：B — 最小 XEAPI 代理 + 主体本地化

> 方案 A（全本地 FFI）需用 `dart:ffi` 调用 libsodium 实现 X25519 ECDH，开发成本高、调试困难。
> **方案 B** 仅在 3 个 `xeapi` 端点使用云函数中转，其余 10+ MVP 端点全部 Dart 直连，务实可行。

---

## Phase 0：项目脚手架 & 常量定义

**目标**：搭建 Flutter 项目骨架，准备所有密钥常量。

### 0.1 Flutter 项目初始化

```bash
flutter create --org com.classicism --project-name classicism .
```

### 0.2 依赖安装 (pubspec.yaml)

```yaml
dependencies:
  dio: ^5.4.0
  pointycastle: ^3.7.3
  crypto: ^3.0.3
  shared_preferences: ^2.2.2
  just_audio: ^0.9.36
  qr_flutter: ^4.1.0
  flutter_riverpod: ^2.4.9
  json_annotation: ^4.8.1

dev_dependencies:
  build_runner: ^2.4.8
  json_serializable: ^6.7.1
  flutter_test:
    sdk: flutter
```

### 0.3 密钥常量文件 `lib/core/crypto/constants.dart`

从 `util/crypto.js` 和 `util/config.json` 提取所有硬编码常量：

```dart
// AES
const iv = '0102030405060708';
const presetKey = '0CoJUm6Qyw8W8jud';
const eapiKey = 'e82ckenh8dichen8';
const linuxapiKey = 'rFgB&h#%2?^eDg:Q';

// RSA 公钥 (PEM)
const rsaPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCgt4+moXkhBe3ZDvIseJ6NrB4B
...（从 crypto.js 完整复制）
-----END PUBLIC KEY-----
''';

// XEAPI 静态密钥
final xeapiStaticKey = Uint8List.fromList([
  0xab, 0x1d, 0x5a, 0x43, 0x0f, 0x6b, 0xb0, 0x4a,
  0x3f, 0x01, 0xe8, 0x1d, 0xdd, 0x72, 0xbd, 0x91,
  0x6d, 0x5c, 0xe5, 0x91, 0x24, 0x8a, 0xc1, 0x28,
  0x71, 0x48, 0x06, 0xd7, 0xf8, 0xfb, 0x1b, 0x84,
]);

// XEAPI 签名密钥
const xeapiSignKey = 'mUHCwVNWJbunMqAHf5MImuirT6plvs6VSFW62MGHstFQxhBGdEoIhLItH3djc4+FB/OKty3+lL2rGeoFBpVe5g==';

// X25519 SPKI 前缀
final x25519SpkiPrefix = Uint8List.fromList([
  0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x03, 0x21, 0x00,
]);

// Base62 字母表
const base62Alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

// API 域名 (来自 config.json)
const musicApiHost = 'https://music.163.com';
const musicEapiHost = 'https://music.163.com';
const musicWeapiHost = 'https://music.163.com';
const musicXeapiHost = 'https://interface.music.163.com';
```

### 0.4 目录结构

```
lib/
├── main.dart
├── core/
│   ├── crypto/
│   │   ├── constants.dart      # 密钥常量
│   │   ├── weapi.dart          # weapi 加密实现
│   │   ├── eapi.dart           # eapi 加密实现
│   │   └── helpers.dart        # hex/base64 转换等
│   ├── cookie_manager.dart     # Cookie 管理
│   ├── request_engine.dart     # 请求分发引擎
│   └── config.dart             # 全局配置
├── api/
│   ├── auth_api.dart           # 认证接口
│   ├── music_api.dart          # 核心音乐接口
│   └── xeapi_proxy.dart        # 云函数代理封装
├── models/                     # 数据模型
│   ├── song.dart
│   ├── playlist.dart
│   ├── lyric.dart
│   ├── user.dart
│   └── search_result.dart
├── services/
│   ├── auth_service.dart       # 认证状态管理
│   └── player_service.dart     # 播放器服务
├── state/                      # Riverpod providers
└── ui/
    ├── pages/
    │   ├── home_page.dart
    │   ├── search_page.dart
    │   ├── login_page.dart
    │   ├── player_page.dart
    │   └── playlist_page.dart
    └── widgets/
        ├── song_tile.dart
        ├── mini_player.dart
        └── qr_login.dart
```

---

## Phase 1：Dart 加密原语层

**目标**：完整移植 `weapi()` 和 `eapi()` 函数至 Dart，确保输出与 Node.js 版逐字节一致。

### 1.1 `eapi.dart` — 难度：低 | 预计 2h

**需实现的函数**：

| JS 函数 | Dart 实现 |
|---|---|
| `aesEncrypt(text, key, iv, 'ECB')` | `pointycastle` — `AESFastEngine` + `ECBBlockCipher` + `PaddedBlockCipher(PKCS7Padding())` |
| `aesDecrypt(ciphertext, key, iv, 'ECB')` | 同上，解密模式 |
| `md5(text)` | `package:crypto` — `md5.convert(utf8.encode(text))` |
| `eapi(url, object)` | `JSON.stringify(object)` → `md5(nobody + path + use + body + md5forencrypt)` → ECB加密 |

**关键路径**：
```
eapi('/api/search/get', { s: 'test', type: 1 })
  → JSON body = '{"s":"test","type":1}'
  → digest = md5('nobody/api/search/getuse{"s":"test","type":1}md5forencrypt')
  → params = '/api/search/get-36cd479b6b5-"digest"-"body"'
  → encrypted = aesEcbEncrypt(params, eapiKey)
  → 返回 { params: hex(encrypted) }
```

**验证方式**：用同样的输入在 Node.js 中运行 `eapi()`，对比二进制输出。

### 1.2 `weapi.dart` — 难度：中 | 预计 4h

**需实现的函数**：

| JS 函数 | Dart 实现 |
|---|---|
| `aesEncrypt(text, key, iv, 'CBC')` | `pointycastle` — CBC 模式（默认 PKCS7） |
| `rsaEncrypt(text, publicKeyPem)` | `pointycastle` — `RSAEngine` + `PKCS1Encoding` (验证无填充模式) |
| `weapi(object)` | 串联：AES-CBC(presetKey, iv) → AES-CBC(random16, iv) → RSA(random16_reversed) |

**关键路径**：
```
weapi({ phone: '13800138000', password: 'md5hash', rememberLogin: 'true' })
  → json = JSON.stringify(data)
  → secretKey = random(16)  // 随机16字节base64
  → encText = aesCbc(aesCbc(json, presetKey, iv), secretKey, iv)
  → encSecKey = rsaEncrypt(secretKey.reversed, publicKey).toHex()
  → 返回 { params: encText, encSecKey: encSecKey }
```

**WebAPI 请求头**：
```
Content-Type: application/x-www-form-urlencoded
Cookie: os=pc; osver=Microsoft-Windows-10-Professional...; appver=2.10.6; MUSIC_A=xxx; ...
```

### 1.3 加密测试用例

```dart
void main() {
  test('eapi - matches Node.js output', () {
    final result = eapi('/api/search/get', {'s': '周杰伦', 'type': '1', 'limit': '30'});
    expect(result.params, equals('已知正确的hex输出'));
  });

  test('weapi - matches Node.js output', () {
    // 注意：weapi 使用随机 secretKey，需要 mock random(16) 来固定
    final result = weapi({'phone': '13800138000', 'password': 'abc123...'});
    expect(result.encSecKey.length, equals(256)); // RSA 1024-bit = 256 hex chars
  });
}
```

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
    'osver': '14',         // Android 版本
    'appver': '8.20.10',   // 网易云 APP 版本
    'versioncode': '140',
    'mobilename': 'Pixel 8 Pro',
    'buildver': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'resolution': '2400x1080',
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
test/
├── crypto/
│   ├── eapi_test.dart
│   └── weapi_test.dart
├── core/
│   ├── cookie_manager_test.dart
│   └── request_engine_test.dart
├── api/
│   ├── auth_api_test.dart
│   └── music_api_test.dart
└── ui/
    └── search_page_test.dart
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

| Phase | 内容 | 预计时间 |
|-------|------|---------|
| 0 | 脚手架 + 常量 | 0.5h |
| 1 | Dart 加密原语 | 6h |
| 2 | 请求引擎 + Cookie | 4h |
| 3 | 认证模块 | 2h |
| 4 | 核心业务接口 | 2h |
| 5 | Flutter UI | 8-12h |
| 6 | 云函数 | 2h |
| 7 | 测试 | 3h |
| **总计** | | **约 28-32h** |

---

## 风险 & 应对

| 风险 | 应对 |
|------|------|
| **pointycastle RSA 无填充模式不支持** | 尝试 `Pkcs1Encoding` 默认行为；若不行则改用 `flutter_rust_bridge` 调 openssl |
| **X25519 云函数延迟过高** | 使用 Cloudflare Workers（全球边缘节点），延迟 < 100ms |
| **网易云 API 变更** | 跟进上游 `@neteasecloudmusicapienhanced/api` npm 包更新，同步修正 |
| **歌曲 URL 防盗链** | 播放前实时获取 URL，失败则降级尝试其他音质等级 |
| **VIP 歌曲限制 (fee=1)** | 仅试听 30 秒，UI 清晰标注 |

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
