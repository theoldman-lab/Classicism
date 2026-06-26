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

## Phase 2：请求引擎 + Cookie 管理 ✅

> **状态：DONE** （2026-06-26）
> 产出：`config.dart` (116行) + `cookie_manager.dart` (170行) + `request_engine.dart` (243行)，73 tests

**目标**：实现 `NeteaseRequest` 类，统一调度加密、HTTP、响应处理。

### 2.1 `config.dart` — 全局配置与初始化 (116 lines)

- `AppConfig` 单例 + `init()` 异步初始化（SharedPreferences）
- DeviceId：52 位大写 hex，首次生成后持久化，后续复用
- WNMCID：`{6 随机小写字母}.{timestamp_ms}.01.0`，每次 `init()` 重新生成
- Cookie 持久化：`musicA`/`musicU`/`csrf`/`uid` getter/setter 对，写穿 SharedPreferences
- `wnmcid` 从 `late final` 改为 `late String` 以支持测试中的重复 `init()`

### 2.2 `cookie_manager.dart` — Cookie 解析与构建 (170 lines)

移植自 `util/index.js` + `util/request.js`：

| 函数 | 来源 | 说明 |
|------|------|------|
| `cookieToJson(str)` | `util/index.js:89` | `"MUSIC_A=xxx; os=pc"` → `{ MUSIC_A: 'xxx', os: 'pc' }` |
| `cookieObjToString(obj)` | `util/index.js:106` | 反向转换，含 `encodeURIComponent` |
| `generateDeviceId()` | `util/index.js:175` | 静态方法，52 位大写 hex |
| `processCookie(cookie, uri)` | `util/request.js:132` | 填充默认值：`_ntes_nuid`(64 hex)、`_ntes_nnid`、`WNMCID`、`WEVNSM`、`osver`/`deviceId`/`os`/`channel`/`appver`。`!uri.contains('login')` 时加 `NMTID`(32 hex)。`MUSIC_U` 缺失时从 AppConfig 补 `MUSIC_A`。 |
| `buildEapiHeader(cookie, csrf)` | `util/request.js:293` | 构建 eapi/api 专用 header 字典：`osver`/`deviceId`/`os`/`appver`/`versioncode`/`mobilename`/`buildver`/`resolution`/`__csrf`/`channel`/`requestId`，含 `MUSIC_U`/`MUSIC_A` 回退到 AppConfig |
| `createHeaderCookie(header)` | `util/request.js:163` | `encodeURIComponent(k)=encodeURIComponent(v)` 拼接 |
| OS 预设 | `util/request.js:66-97` | pc(weapi 默认)/android(eapi 默认)/iphone/linux 四套指纹方案 |

### 2.3 `request_engine.dart` — 中央请求调度器 (243 lines)

| 组件 | 说明 |
|------|------|
| `ApiResponse` | `{status: int, body: dynamic, cookies: List<String>}`，含 `isSuccess` getter |
| `NeteaseRequest` | 持有 `Dio` + `CookieManager` + `AppConfig`。单一入口：`request(endpoint, data, {crypto, encryptResponse, ua, overrideDomain})` |

**Crypto 分发逻辑**（精确对应 `util/request.js:224-336`）：

| Crypto | URL 拼接 | Body | Cookie | UA |
|--------|---------|------|--------|-----|
| `weapi` | `{domain}/weapi/{endpoint[5:]}` | `{params, encSecKey}` form-urlencoded | `cookieObjToString` OS=pc | Chrome/124 |
| `eapi` | `{apiDomain}/eapi/{endpoint[5:]}` | `{params}` form-urlencoded | `createHeaderCookie` OS=android | NeteaseMusic iPhone |
| `xeapi` | 云函数 POST (JSON) | `{endpoint, data, cookie}` | 云函数内部处理 | — |
| `api` | `{apiDomain}{endpoint}` | plain params form-urlencoded | `createHeaderCookie` | NeteaseMusic iPhone |
| `linuxapi` | — | — | 抛出 `UnimplementedError` | — |

**响应处理**：
- `encryptResponse=true` → `ResponseType.bytes` → `bytesToHex().toUpperCase()` → `eapiResDecrypt(hex)`
- 特殊状态码映射：{201,302,400,502,800,801,802,803} → 200
- `_extractCookies()` 剥离 Set-Cookie 中的 `Domain=...` 属性

**审查修复的 Bug**：
- 初始 cookie 从 `{}` 改为从 `AppConfig` 注入 `MUSIC_U`/`MUSIC_A`/`__csrf`（否则 weapi 登录态请求失败）
- Xeapi 代理响应 cookies 从 `proxyBody['cookie']` 提取（原来错误地从 HTTP headers 提取）
- EAPI/API 分支支持 `overrideDomain` 参数（原来硬编码域名常量）

---

## Phase 3：认证模块 ✅

> **状态：DONE** （2026-06-26）
> 产出：`xeapi_helpers.dart` (22行) + `xeapi_proxy.dart` (43行) + `auth_api.dart` (374行) + `auth_service.dart` (71行)，54 tests

**目标**：实现游客注册 + QR 扫码登录 + 手机号登录 + token 刷新完整链路。

### 3.0 前置修改
- `eapi.dart`：`_aesEcbEncrypt`/`_aesEcbDecrypt` 改为 public（去掉下划线），注释更新为 "AES-ECB (auto-detects key size: 128/192/256-bit)"，供 `xeapiDecryptPublicKey`（AES-256-ECB）复用

### 3.1 `crypto/xeapi_helpers.dart` — XEAPI 签名与解密 (22 lines)

| 函数 | 来源 | 说明 |
|------|------|------|
| `xeapiSign(timestamp, nonce)` | `util/crypto.js:189` | HMAC-SHA256 with `xeapiSignKey` as **raw UTF-8 string**（非 base64-decode → 匹配 Node `crypto.createHmac` 行为）。Message = `timestamp + nonce`（无 prefix）。Output: base64。 |
| `xeapiDecryptPublicKey(base64)` | `util/crypto.js:298` | AES-256-ECB decrypt with `xeapiStaticKey` → JSON.parse |

### 3.2 `api/xeapi_proxy.dart` — 云函数代理 (43 lines)

| 组件 | 说明 |
|------|------|
| `XeapiProxyResponse` | `{body: Map, cookies: List<String>}` |
| `XeapiProxy.call(endpoint, data, cookie)` | POST JSON `{endpoint, data, cookie}` → 云函数 → `XeapiProxyResponse`。Content-Type: `application/json`。 |

### 3.3 `api/auth_api.dart` — 7 个认证 API 方法 (374 lines)

| 方法 | 端点 | 加密 | 关键实现 |
|------|------|------|---------|
| `registerAnonymous()` | `/api/register/anonimous` | xeapi→proxy | `cloudmusicDllEncodeId` XORs deviceId with key `'3go8&$8*3*3h0k(2)2'` → MD5 → base64。`buildAnonUsername` = `base64(deviceId + ' ' + encodedId)`。提取 `MUSIC_A` → 持久化。 |
| `getXeapiPublicKey()` | `/api/gorilla/anti/crawler/security/key/get` | **Direct Dio** | 16 位随机 nonce + `xeapiSign(timestamp, nonce)` 签名。验证服务端响应签名。`xeapiDecryptPublicKey` 解密 → `XeapiKeyState`。 |
| `getLoginQrKey()` | `/api/login/qrcode/unikey` | eapi | `type=3` → 返回 `unikey` |
| `checkLoginQr(unikey)` | `/api/login/qrcode/client/login` | eapi | 800=过期/801=等待/802=已扫/803=成功。803 时持久化 `MUSIC_U`+`__csrf`。 |
| `loginCellphone(phone, md5Password)` | `/api/w/login/cellphone` | weapi | 支持 captcha 模式。200 时持久化 auth cookies。 |
| `loginStatus()` | `/api/w/nuser/account/get` | weapi | 返回 account profile 或 null |
| `refreshToken()` | `/api/login/token/refresh` | eapi | 成功时持久化新 MUSIC_U+csrf |

**模型类**（内联于 auth_api.dart）：`XeapiKeyState`（含 `fromJson`）、`QrCheckResult`（含便捷 getter）、`LoginResult`

### 3.4 `services/auth_service.dart` — 认证编排 (71 lines)

| 方法 | 说明 |
|------|------|
| `initialize()` | `AppConfig.init()` → 检查 `musicA` → 若无则调用 `registerAnonymous()` |
| `pollLoginQr(unikey)` | `async*` Stream：2 秒轮询至 803(成功) 或 800(过期) |
| `loginWithPassword(p, m)` | MD5(password) → `loginCellphone()` |
| `logout()` | 清除 `musicU`/`csrf`/`uid`（保留 `musicA` 维持游客态） |

**实际初始化流程**（简化自原计划）：
```
1. SharedPreferences 读取 deviceId → 若无则生成并写入
2. SharedPreferences 读取 MUSIC_A → 若无则调用 registerAnonymous()
3. 此时可发起所有游客请求
```
> 注：原计划第 3 步（获取 xeapiKeyState）移至按需调用。因 xeapi 加密由云函数完成，Dart 客户端无需维护 X25519 密钥。

---

## Phase 4：核心业务接口 ✅

> **状态：DONE** （2026-06-26）
> 产出：`music_api.dart` (273行) + 模型更新（song/lyric/playlist/user/search_result），48 tests

**目标**：实现搜索、播放、歌词、歌单等 9 个核心 API + 2 个便捷方法。

### 4.1 模型更新

| 模型 | 关键字段 | `fromJson` null 安全处理 |
|------|---------|--------------------------|
| `Song` | id, name, artistName(ar[0]), albumName(al), coverUrl(al.picUrl), duration(dt), fee | 全部字段有 null 回退默认值 |
| `Lyric` | lrc(lrc.lyric), tlyric(tlyric.lyric) | lrc 默认 ''，tlyric 允许 null |
| `Playlist` | id, name, coverImgUrl, trackCount, playCount, creatorName(creator.nickname) | trackCount/playCount 默认 0 |
| `User` | userId, nickname | — |
| `SearchResult` | songs, songCount | — |

### 4.2 `api/music_api.dart` — 9 个方法 + 2 个便捷 (273 lines)

| 方法 | 端点 | 加密 | 关键参数/细节 |
|------|------|------|-------------|
| `search(keywords)` | `/api/search/get` | eapi | `s, type=1, limit=30, offset=0` |
| `searchSongs(keywords)` | (封装 search) | — | 便捷：type=1 → `List<Song>` |
| `searchPlaylists(keywords)` | (封装 search) | — | 便捷：type=1000 → `List<Playlist>` |
| `getSongUrls(ids)` | `/api/song/enhance/player/url/v1` | xeapi→proxy | `ids='[1,2,3]'`, `level='exhigh'`(standard/exhigh/lossless/hires/jyeffect/sky/jymaster)。`level='sky'` → `immerseType='c51'` |
| `getLyric(songId)` | `/api/song/lyric` | eapi | `id, tv/lv/rv/kv=-1, _nmclfl=1` → `Lyric?` |
| `getSongDetail(ids)` | `/api/v3/song/detail` | **weapi** ⚠️ | `c='[{"id":1},{"id":2}]'` |
| `getPlaylistDetail(id)` | `/api/v6/playlist/detail` | eapi | `id, n=100000, s=8` → `Playlist?` |
| `getUserPlaylists(uid)` | `/api/user/playlist` | weapi | `uid, limit=30, offset=0, includeVideo=true` |
| `getRecommendSongs()` | `/api/v3/discovery/recommend/songs` | weapi | 需登录。返回 `data.dailySongs` |
| `getAlbum(id)` | `/api/v1/album/{id}` | weapi | id 插入路径 |
| `getArtistTopSongs(id)` | `/api/artist/top/song` | weapi ⚠️ | `id` ← 原计划误标为 eapi，上游使用 weapi |

> ⚠️ **计划修正**：
> - `getSongDetail` 加密方案从 eapi 改为 **weapi**（上游 `song_detail.js` 使用 `createOption(query, 'weapi')`）
> - `getArtistTopSongs` 加密方案从 eapi 改为 **weapi**（上游 `artist_top_song.js` 使用 `createOption(query, 'weapi')`）；
>   端点从 `/api/v1/artist/songs` 改为 `/api/artist/top/song`（上游实际端点）

## Phase 5：Flutter UI + 播放器 ✅

> **状态：DONE** （2026-06-26 Evening）
> 产出：PlayerService (139行) + Providers (265行) + 7 Widgets (733行) + 5 Pages (922行) + Routing，+73 测试

**目标**：实现完整的 Material 3 播放器 UI，含 5 个页面、7 个可复用组件、Riverpod 状态管理、`just_audio` 音频播放。

### 5.0 PlayerService (`lib/services/player_service.dart`, 139 lines)

| 组件 | 实现 |
|------|------|
| `PlayMode` enum | `sequential` / `shuffle` / `singleRepeat` |
| 构造器 | `PlayerService({required MusicApi api})` — 创建 `AudioPlayer`，监听 `currentIndexStream` |
| 流 | `positionStream` / `durationStream` / `playingStream` / `currentSongStream` (broadcast) |
| `playSongs(songs, {startIndex})` | 实时调用 `MusicApi.getSongUrls` → 过滤无 URL 歌曲 → `ConcatenatingAudioSource` + `tag: Song` → `setAudioSource` → `play()` |
| 控制 | `playSong` / `playSongs` / `togglePlayPause` / `next` / `previous` / `seek` / `setPlayMode` |
| 生命周期 | `dispose()` 取消订阅 → `_player.dispose()` |

**设计要点**：`currentSong` 通过 `AudioPlayer.sequence[currentIndex].tag` 提取，无 URL 歌曲自动从 `ConcatenatingAudioSource` 中过滤但保留在 `_playlist` 中。播放模式映射至 `just_audio` 的 `LoopMode` + `setShuffleModeEnabled`。

### 5.1 State Providers (`lib/state/providers.dart`, 265 lines)

| Provider | 类型 | 状态字段 | 方法 |
|----------|------|---------|------|
| `authProvider` | `StateNotifierProvider<AuthNotifier, AuthState>` | `status(AuthStatus)`, `unikey` | `initialize()`, `loginWithPassword()`, `logout()` |
| `playerProvider` | `StateNotifierProvider<PlayerNotifier, PlayerState>` | `currentSong`, `playlist`, `currentIndex`, `playMode`, `isPlaying`, `position`, `duration` | `playSong/playSongs/togglePlayPause/next/previous/seek/setPlayMode` |
| `searchProvider` | `StateNotifierProvider<SearchNotifier, SearchState>` | `query`, `songs`, `playlists`, `isLoading`, `error` | `search(query)`—并发 `searchSongs`+`searchPlaylists`, `clear()` |
| `recommendSongsProvider` | `FutureProvider<List<Song>>` | — | 按需获取每日推荐 |

所有 State 均有手动 `copyWith` 方法。`PlayerNotifier` 通过 4 条 `StreamSubscription` 自动同步 `PlayerService` 状态流。使用 `if (mounted)` 防泄漏。

### 5.2 UI Widgets (7 文件, 733 lines)

| Widget | 文件 | 行 | 关键特性 |
|--------|------|-----|---------|
| `SongTile` | `song_tile.dart` | 94 | 封面 + 兜底图标 / 歌名/歌手 / 时长 `mm:ss` / `onTap` / `showCover` 切换 / 零时长隐藏 trailing |
| `PlaylistTile` | `playlist_tile.dart` | 92 | 封面 + 曲目数/播放量(万)/创建者 / `onTap` / null-safe |
| `MiniPlayer` | `mini_player.dart` | 112 | `ConsumerWidget` → `playerProvider`。`LinearProgressIndicator` + 封面 + 歌名/歌手 + 暂停/下一首。`currentSong==null` 时隐藏。点击导航到 `/player` |
| `ClassicismSearchBar` | `search_bar.dart` | 86 | Material 3 `TextField` + 300ms debounce (`Timer`)。`_controller.addListener`→`setState` 驱动清除按钮可见性 |
| `SearchResultList` | `search_result_list.dart` | 132 | `ConsumerWidget` → `searchProvider`。`TabBar`(歌曲/歌单) + `TabBarView`。复用 `SongTile`/`PlaylistTile`。loading/error/empty 状态 |
| `LyricView` | `lyric_view.dart` | 95 | 静态 `parse(lrc)`：`[mm:ss.xx]`→`List<(Duration, String)>`。支持多时间戳行、3 位毫秒。`ListView` 按 `position` 定位高亮行（primary color/bold/大字号） |
| `QrCodeLogin` | `qr_login.dart` | 154 | 参数接收 `AuthApi`。`initState`→`getLoginQrKey()`→`QrImageView`。2 秒 `Stream.periodic` 轮询。状态：loading/waiting/scanned/success/expired/error。过期/错误时显示刷新按钮 |

### 5.3 UI Pages (5 文件, 922 lines)

| Page | 行 | 说明 |
|------|-----|------|
| `HomePage` | 176 | `ConsumerStatefulWidget`。`addPostFrameCallback`→`authProvider.initialize().catchError(...)`。搜索栏 + 3 快捷卡片（每日推荐/歌单/登录）。`AsyncValue.when` 展示推荐歌曲。未登录时显示登录引导 |
| `SearchPage` | 28 | AppBar 内嵌 `ClassicismSearchBar` + `SearchResultList` + `MiniPlayer` |
| `PlaylistPage` | 204 | `ConsumerStatefulWidget`。`ModalRoute.settings.arguments` 接收 `playlistId`。`SliverAppBar` 展开封面 + 渐变遮罩。元数据栏（创建者/曲目数/播放量）。"播放全部"按钮。`SongTile(showCover: false)` 曲目列表。`CustomScrollView` + `SliverList` |
| `PlayerPage` | 344 | `ConsumerStatefulWidget`。模糊封面背景 + 280×280 专辑封面（阴影）。歌名/歌手。可拖 `Slider` + 时间标签。播放模式切换（`sequential→shuffle→singleRepeat`）。Prev/PlayPause/Next。`LyricView`（歌曲切换时自动 `getLyric`）。关闭按钮 → `Navigator.pop` |
| `LoginPage` | 170 | `ConsumerStatefulWidget` + `TabController`。Tab1: QR 扫码（`QrCodeLogin` 占位，待云函数）。Tab2: 手机号+密码表单 + `FilledButton`。空字段校验 + loading spinner + 错误提示。登录成功 `Navigator.pop` |

### 5.4 Routing + main.dart (106 lines)

```dart
main() async:
  WidgetsFlutterBinding.ensureInitialized()
  AppConfig.instance.init() → SharedPreferences
  CookieManager(config) → cookie fingerprints
  NeteaseRequest(dio, cookie, config) → request dispatcher
  MusicApi / AuthApi / AuthService / PlayerService → service layer
  ProviderScope overrides → musicApi/authService/playerService providers
  ClassicismApp → MaterialApp

Routes:
  /         → HomePage
  /search   → SearchPage
  /playlist → PlaylistPage (arguments: playlistId)
  /player   → PlayerPage
  /login    → LoginPage
```

**Model 更新**：`Playlist` 模型新增 `tracks: List<Song>?` 字段，从 `fromJson` 解析 song 数组。

### 5.5 测试 (73 新增)

| 文件 | 测试数 | 覆盖 |
|------|--------|------|
| `widget_song_tile_test.dart` | 10 | 渲染/空字段/时长格式/封面兜底/onTap/showCover |
| `widget_playlist_tile_test.dart` | 9 | 渲染/播放量千分位/空封面/onTap/null字段 |
| `widget_search_bar_test.dart` | 10 | hint/提交/debounce/空查询/清除按钮/trim/debounce取消 |
| `widget_lyric_view_test.dart` | 15 | parse×10 (毫秒/多行/多时间戳/排序) + widget×5 (渲染/空态/高亮/ListView) |
| `page_home_test.dart` | 6 | 搜索栏/快捷卡片/登录提示/loading/导航 |
| `page_player_test.dart` | 8 | 关闭按钮/控件/空态/专辑图/进度条/播放模式 |
| `page_login_test.dart` | 10 | TabBar/QR页/手机表单/输入框/登录按钮/空值校验 |
| `page_search_test.dart` | 5 | AppBar/搜索图标/空结果/搜索输入/MiniPlayer |

---

## Phase 6：云函数部署 ✅

> **状态：DONE 代码就绪** （2026-06-26 Evening）
> 产出：`xeapi-proxy/api/xeapi.js` (381行, 零npm依赖) + Vercel + Cloudflare Workers 双平台部署
> ⚠️ 免费域名被墙，需绑定自定义域名方可生产使用

**目标**：实现 `xeapi` 加密的云函数中转，使 Flutter 客户端可以间接调用 `xeapi` 端点。

### 6.1 实际架构（与计划差异）

| 项目 | 原计划 | 实际 |
|------|--------|------|
| 文件数 | 3+ util 文件复制 | **1 个自包含文件**（381行） |
| npm 依赖 | `crypto-js` + `axios` | **零外部依赖**（仅 Node 内置 `crypto`/`zlib`/`https`） |
| 端点数 | 3 (`register_anonimous`/`register_xeapikey`/`song_url_v1`) | **2**（`register_xeapikey` 已由 Dart 端 HMAC-SHA256 直连实现） |
| 平台 | Vercel only | Vercel + Cloudflare Workers 双版本 |

### 6.2 云函数实现 (`xeapi-proxy/api/xeapi.js`, 381 lines)

完整自包含实现，零 npm 依赖。结构：

| 模块 | 行 | 实现 |
|------|-----|------|
| 常量 | 12-16 | `xeapiStaticKey`(32B hex), `xeapiSignKey`, `eapiKey`, `x25519SpkiPrefix` |
| AES 原语 | 23-35 | `aesEcbEncrypt`/`aesEcbDecrypt` — `crypto.createCipheriv(Decipheriv)` + 自动密钥位数 |
| X25519 ECDH | 37-58 | `createX25519PublicKey`(SPKI), `deriveX25519AesKey`(HKDF-like), `xeapiEncryptS`(ECDH + AES-128-GCM) |
| XEAPI 加密 | 60-72, 88-98 | `buildXeapiPlaintext`(queryString + base64 body + `e_r=true`), `xeapi()`: AES-ECB×3 + XOR mid-transform + ECDH→S 字段 |
| 响应解密 | 74-80 | `xeapiResDecrypt`: AES-ECB(eapiKey) → gzip 魔数检测 → JSON.parse |
| 签名与密钥注册 | 82-86, 100-141 | `xeapiSign`(HMAC-SHA256), `xeapiDecryptPublicKey`, `registerXeapiKey`(调用 `/api/gorilla/anti/crawler/security/key/get` + 签名验证) |
| HTTP 处理 | 143-198 | Vercel `module.exports` + Cloudflare `export default { fetch }` 双格式 |
| Cookie 提取 | 186-188 | `Set-Cookie` → `Domain=...` 正则剥离 → 返回 `List<String>` |

**关键设计**：内存变量 (`publicKeyState`, `sessionId`, `sessionKey`) 在 Vercel/Worker 实例间持久化，减少密钥注册频率。响应头 `x-encr-ssid`/`x-encr-sskey` 自动缓存用于会话复用。

### 6.3 Flutter 端修改

| 文件 | 修改 |
|------|------|
| `xeapi_proxy.dart:22` | `call()` 加 `{String deviceId = ''}` 可选命名参数（向后兼容） |
| `auth_api.dart:106` | `registerAnonymous()` 传递 `deviceId: _config.deviceId` |
| `music_api.dart:105` | `getSongUrls()` 传递 `deviceId: AppConfig.instance.deviceId` |
| `request_engine.dart:148` | xeapi 分支 POST data 包含 `'deviceId': _config.deviceId` |
| `main.dart:37-52` | `XEAPI_PROXY_URL` 编译时常量注入 (`String.fromEnvironment`)。真实 `XeapiProxy` 实例（URL 非空时）或 `null` |

### 6.4 部署

```bash
# Vercel
cd xeapi-proxy && vercel deploy --prod
# → https://xeapi-proxy-xxxxx.vercel.app/api/xeapi

# Cloudflare Workers
cd xeapi-proxy && wrangler deploy
# → https://classicism-xeapi.xxxxx.workers.dev

# Flutter
flutter run --dart-define=XEAPI_PROXY_URL=https://your-domain.com/api/xeapi
```

### 6.5 文件清单

```
xeapi-proxy/
├── api/xeapi.js      (381 lines) — 自包含云函数
├── wrangler.toml     — Cloudflare Workers 配置 (nodejs_compat)
├── package.json      — { "dependencies": {} }
└── vercel.json       — Vercel 路由 + CORS 头
```

---

## Phase 7：测试 & 审查 ✅

> **状态：DONE** （2026-06-26）
> 产出：344 tests，`flutter analyze` 零错误，修复 5 个 Bug

### 7.1 测试策略（已实施）

| 层 | 测试类型 | 覆盖范围 | 状态 |
|---|---|---|---|
| 加密层 | 单元测试 + 黄金向量 | weapi/eapi 函数输入输出逐字节一致 | ✅ |
| 请求引擎 | 单元测试 (mock Dio) | Cookie 管理、加密分发、URL 构建、响应解密 | ✅ |
| 认证 | 单元测试 (mock Dio) | 游客注册、登录、token 刷新、QR 轮询 | ✅ |
| 业务 API | 单元测试 (mock Dio) | 搜索/歌词/歌单返回格式、空结果处理 | ✅ |
| 模型 | 单元测试 | fromJson null 安全、缺失字段、类型 | ✅ |
| 工具函数 | 单元测试 | hex/base64/base62/random 全覆盖 | ✅ |
| 错误处理 | 单元测试 | 网络异常、非200响应、签名校验失败 | ✅ |
| 审查 | 逐文件对比上游 | 5 bugs 发现并修复 | ✅ |
| UI Widgets | Widget测试 | SongTile/PlaylistTile/SearchBar/LyricView 渲染与交互 | ✅ |
| UI Pages | Widget测试 | Home/Search/Player/Login 页面渲染、表单校验、状态流转 | ✅ |
| 集成测试 | 真实 API | 首次启动完整链路验证 | ⬜ (待自定义域名) |

### 7.2 测试结构

```
test/
├── golden_vectors.json              # 17 黄金向量
├── eapi_test.dart                   # 34 tests ✅
├── weapi_test.dart                  # 18 tests ✅
├── helpers_test.dart                # 28 tests ✅
├── models_test.dart                 # 21 tests ✅
├── config_test.dart                 # 17 tests ✅
├── cookie_manager_test.dart         # 25 tests ✅
├── request_engine_test.dart         # 31 tests ✅
├── xeapi_helpers_test.dart          # 9 tests ✅
├── xeapi_proxy_test.dart            # 8 tests ✅
├── auth_api_test.dart               # 37 tests ✅
├── auth_service_test.dart           # 8 tests ✅
├── music_api_test.dart              # 27 tests ✅
├── widget_test.dart                 # 1 test ✅
├── test_helpers.dart                # Mock 工具 ✅
├── widget_song_tile_test.dart       # 10 tests ✅ (Phase 5)
├── widget_playlist_tile_test.dart   # 9 tests ✅ (Phase 5)
├── widget_search_bar_test.dart      # 10 tests ✅ (Phase 5)
├── widget_lyric_view_test.dart      # 15 tests ✅ (Phase 5)
├── page_home_test.dart              # 6 tests ✅ (Phase 5)
├── page_player_test.dart            # 8 tests ✅ (Phase 5)
├── page_login_test.dart             # 10 tests ✅ (Phase 5)
└── page_search_test.dart            # 5 tests ✅ (Phase 5)
```

### 7.3 发布检查清单

- [x] `flutter analyze` 零错误
- [x] `flutter test` 全通过 (344/344)
- [x] 云函数代码已部署 (Vercel + Cloudflare Workers)
- [ ] 云函数自定义域名绑定（免费域名被墙）
- [ ] Release build: `flutter build apk --release`
- [ ] APK 体积 < 30MB
- [ ] 首次启动完整链路验证（安装 → 游客注册 → 搜索 → 试听）
- [ ] 登录链路验证（QR码 / 手机号）
- [ ] 歌曲完整播放验证

---

## 代码审查记录 (2026-06-26 Afternoon)

逐文件对比上游 `util/*.js`、`module/*.js`，发现并修复 5 个 Bug：

| # | Bug | 文件:行 | 严重度 | 修复 |
|---|-----|---------|--------|------|
| 1 | Cookie 未注入持久化 auth 状态 | `request_engine.dart:75` | **Critical** | 从 `AppConfig` 注入 `MUSIC_U`/`MUSIC_A`/`__csrf` |
| 2 | Xeapi cookies 从错误位置提取 | `request_engine.dart:143` | **High** | 改为从 `proxyBody['cookie']` 提取 |
| 3 | EAPI `overrideDomain` 无效 | `request_engine.dart:124` | Medium | 支持 `overrideDomain ?? apiDomain` |
| 4 | API `overrideDomain` 无效 | `request_engine.dart:162` | Medium | 同上 |
| 5 | `base62Encode` 空输入崩溃 | `helpers.dart:34` | Low | 加 `if (bytes.isEmpty) return 'a'` 守卫 |

审查期间新增 109 个测试（162→271），实现 186 个覆盖盲区中的 Critical/High 全覆盖。

---

## 工作量估算

| Phase | 内容 | 预计 | 实际 | 状态 |
|-------|------|------|------|------|
| 0 | 脚手架 + 常量 | 0.5h | 1h | ✅ |
| 1 | Dart 加密原语 | 6h | 5h | ✅ |
| 2 | 请求引擎 + Cookie | 4h | 4h | ✅ |
| 3 | 认证模块 | 2h | 3h | ✅ |
| 4 | 核心业务接口 | 2h | 2h | ✅ |
| Review | 全代码审查 + 测试增强 | — | 5h | ✅ |
| 5 | Flutter UI | 8-12h | ~8h | ✅ |
| 6 | 云函数 | 2h | ~3h | ✅ (代码就绪) |
| 7 | 集成测试 & 发布 | 3h | — | ⬜ (待自定义域名) |
| **总计** | | **约 28-32h** | **~31h** | |

---

## 风险 & 应对

| 风险 | 应对 | 状态 |
|------|------|------|
| ~~pointycastle RSA 无填充模式不支持~~ | 已解决：手动 ASN.1 DER 解析 + `RSAEngine` 左填零至 128 字节 | ✅ |
| ~~Cookie 未注入 MUSIC_U 导致 weapi 登录态请求失败~~ | 审查发现并修复：从 AppConfig 注入持久化 auth 状态 | ✅ |
| ~~EAPI/API overrideDomain 参数被忽略~~ | 审查发现并修复：支持自定义域名参数 | ✅ |
| X25519 云函数延迟过高 | Cloudflare Workers 已部署（全球边缘节点），Vercel 备用。待自定义域名绑定后国内可访问 | ⬜ |
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
