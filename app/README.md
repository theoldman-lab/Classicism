# Classicism — Flutter App

本地化网易云音乐 Android 客户端。核心加密层（weapi/eapi）纯 Dart 实现，xeapi 端点通过轻量云函数中转。不依赖外部服务器。

## 环境

- Flutter 3.41.6 · Dart SDK ^3.11.4
- Android only

## 快速开始

```bash
cd app
flutter pub get
flutter run                        # debug
flutter run --dart-define=XEAPI_PROXY_URL=https://your-domain.com/api/xeapi
flutter test                       # 344 tests
```

## 项目状态

| Metric | Value |
|--------|-------|
| Source files | 32 |
| Source lines | ~3,990 |
| Tests | **344** |
| `flutter analyze` | 0 issues |

## 目录结构

```
app/
├── pubspec.yaml
├── lib/
│   ├── main.dart                      # App 入口 (Material3 + Riverpod + 路由)
│   ├── core/
│   │   ├── config.dart                # 全局配置 + SharedPreferences 持久化
│   │   ├── cookie_manager.dart        # Cookie 解析/处理/指纹生成
│   │   ├── request_engine.dart        # 中央请求调度器 (weapi/eapi/xeapi/api 分发)
│   │   └── crypto/
│   │       ├── constants.dart         # 所有密钥/域名/设备指纹常量
│   │       ├── helpers.dart           # hex/base64/random/base62 工具
│   │       ├── eapi.dart              # MD5 + AES-ECB (128/192/256 自适应)
│   │       ├── weapi.dart             # AES-128-CBC + RSA-1024 + ASN.1 DER
│   │       └── xeapi_helpers.dart     # HMAC-SHA256 签名 + AES-256-ECB 解密
│   ├── api/
│   │   ├── auth_api.dart              # 认证模块 (7 methods: register/QR/phone/refresh)
│   │   ├── music_api.dart             # 核心业务接口 (11 methods)
│   │   └── xeapi_proxy.dart           # XEAPI 云函数代理封装
│   ├── models/
│   │   ├── song.dart                  # Song (id/name/artist/album/cover/duration/fee)
│   │   ├── lyric.dart                 # Lyric (lrc/tlyric) + fromJson
│   │   ├── playlist.dart              # Playlist (id/name/cover/tracks/creator)
│   │   ├── user.dart                  # User (userId/nickname)
│   │   └── search_result.dart         # SearchResult (songs/songCount)
│   ├── services/
│   │   ├── auth_service.dart          # 认证编排 (initialize/pollQR/login/logout)
│   │   └── player_service.dart        # just_audio 封装 (playSongs/seek/playMode)
│   ├── state/
│   │   └── providers.dart             # Riverpod (auth/player/search/recommend)
│   └── ui/
│       ├── pages/
│       │   ├── home_page.dart         # 首页（搜索栏 + 快捷卡片 + 推荐列表）
│       │   ├── search_page.dart       # 搜索（搜索栏 + TabBar 歌单/歌曲）
│       │   ├── playlist_page.dart     # 歌单详情（SliverAppBar + 曲目列表）
│       │   ├── player_page.dart       # 全屏播放器（封面 + 进度条 + 歌词）
│       │   └── login_page.dart        # 登录（TabBar: QR码 | 手机号）
│       └── widgets/
│           ├── mini_player.dart        # 底部迷你播放条（进度条 + 封面 + 控制）
│           ├── song_tile.dart          # 歌曲列表项（封面 + 歌名/歌手 + 时长）
│           ├── playlist_tile.dart      # 歌单列表项（封面 + 名称 + 曲目数）
│           ├── search_bar.dart         # 搜索框（300ms debounce + 清除按钮）
│           ├── search_result_list.dart  # 搜索结果（TabBar 歌曲/歌单）
│           ├── lyric_view.dart         # 歌词滚动（LRC 解析 + 当前位置高亮）
│           └── qr_login.dart           # QR 码登录（生成 + 2 秒轮询 + 状态反馈）
└── test/
    ├── golden_vectors.json             # 17 黄金测试向量
    ├── eapi_test.dart                  # 34 tests
    ├── weapi_test.dart                 # 18 tests
    ├── helpers_test.dart               # 28 tests
    ├── models_test.dart                # 21 tests
    ├── config_test.dart                # 17 tests
    ├── cookie_manager_test.dart        # 25 tests
    ├── request_engine_test.dart        # 31 tests
    ├── xeapi_helpers_test.dart         # 9 tests
    ├── xeapi_proxy_test.dart           # 8 tests
    ├── auth_api_test.dart              # 37 tests
    ├── auth_service_test.dart          # 8 tests
    ├── music_api_test.dart             # 27 tests
    ├── widget_test.dart                # 1 test
    ├── test_helpers.dart               # Mock 工具 (MockMusicApi/MockAuthService)
    ├── widget_song_tile_test.dart       # 10 tests
    ├── widget_playlist_tile_test.dart   # 9 tests
    ├── widget_search_bar_test.dart      # 10 tests
    ├── widget_lyric_view_test.dart      # 15 tests
    ├── page_home_test.dart              # 6 tests
    ├── page_player_test.dart            # 8 tests
    ├── page_login_test.dart             # 10 tests
    └── page_search_test.dart            # 5 tests
```

## 架构分层

```
main.dart (入口 + DI + 路由)
  │
  ├── state/ (Riverpod Providers)
  │   ├── authProvider    → AuthService  → AuthApi   → auth_api.dart
  │   ├── playerProvider  → PlayerService → MusicApi  → music_api.dart
  │   ├── searchProvider  → MusicApi
  │   └── recommendSongsProvider → MusicApi
  │
  ├── ui/pages/ (5 pages)
  │   └── ui/widgets/ (7 reusable widgets)
  │
  └── core/ (Infrastructure)
      ├── request_engine.dart → dio → music.163.com
      ├── cookie_manager.dart → cookie fingerprints
      └── config.dart → SharedPreferences
```

## 核心依赖

| 包 | 版本 | 用途 |
|---|---|---|
| dio | 5.9.2 | HTTP |
| pointycastle | 3.9.1 | AES (CBC/ECB/GCM) + RSA |
| crypto | 3.0.7 | MD5 / HMAC |
| just_audio | 0.9.46 | 音频播放 |
| qr_flutter | 4.1.0 | QR 码 |
| flutter_riverpod | 2.6.1 | 状态管理 |
| shared_preferences | 2.5.5 | 持久化 |

## 开发阶段

| # | 阶段 | 状态 |
|---|------|------|
| 0 | 项目脚手架 & 常量 | ✅ |
| 1 | Dart 加密层 (eapi + weapi) | ✅ |
| 2 | 请求引擎 + Cookie 管理 | ✅ |
| 3 | 认证模块 | ✅ |
| 4 | 核心业务接口 | ✅ |
| 5 | Flutter UI + 播放器 (5 pages, 7 widgets) | ✅ |
| 6 | 云函数部署 (381 行, 零依赖) | ✅ |

## 许可证

MIT — 参见根目录 LICENSE
