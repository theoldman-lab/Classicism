# Classicism — 本地化网易云音乐 Android 客户端

基于 [NeteaseCloudMusicApiEnhanced](https://github.com/ndz-org/NeteaseCloudMusicApiEnhanced) 的 API 逆向工程成果，构建一个**完全本地化**的轻量 Android 网易云音乐客户端。采用 **Flutter + Dart** 技术栈，核心加密逻辑纯 Dart 实现，`xeapi` 端点通过自包含云函数（381 行 JS，零 npm 依赖）中转。

## 设计目标

- **零外部依赖**：除 `xeapi` 云函数（2 个端点）外，所有请求直连 music.163.com
- **纯 Dart 加密**：`weapi` / `eapi` 在 Dart 内完成，无需嵌入 Node.js
- **轻量化**：MVP 功能（登录、搜索、播放、歌单、歌词）
- **完全开源**：无混淆、无商业 SDK 依赖

## 项目状态

| Metric | Value |
|--------|-------|
| Flutter | 3.41.6 · Dart ^3.11.4 |
| Platform | Android only |
| Source files | 32 |
| Source lines | ~3,990 |
| Tests | **344** |
| `flutter analyze` | 0 errors, 0 warnings |

## 架构概览

```
┌──────────────────────────────────────────────────────┐
│ Flutter App (Android)                                │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌────────────────────┐ │
│  │ weapi     │  │ eapi      │  │ xeapi              │ │
│  │ (纯Dart)  │  │ (纯Dart)  │  │ (自包含云函数代理)   │ │
│  └────┬─────┘  └────┬─────┘  └─────────┬──────────┘ │
│       │             │                   │            │
│       └──────┬──────┘                   │            │
│              │                          │            │
│        ┌─────┴──────┐            ┌─────┴──────┐     │
│        │ Request     │            │ Cloudflare │     │
│        │ Engine      │            │ Workers /  │     │
│        │ (cookie管理) │            │ Vercel     │     │
│        └─────┬──────┘            └─────┬──────┘     │
│              │                         │            │
└──────────────┼─────────────────────────┼────────────┘
               ▼                         ▼
         music.163.com              music.163.com
        (weapi/eapi)                 (xeapi)
```

## 目录结构

```
Classicism/
├── README.MD                     # 项目说明
├── DEVELOPMENT_PLAN.md           # 详细开发计划
├── WORKLOG.md                    # 工作日志
├── app/                          # Flutter 应用
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart             # 入口（Material3 + Riverpod + 路由）
│   │   ├── core/
│   │   │   └── crypto/
│   │   │       ├── constants.dart     # 密钥/域名/设备指纹常量
│   │   │       ├── helpers.dart       # hex/base64/random/base62
│   │   │       ├── eapi.dart          # MD5 + AES-ECB
│   │   │       ├── weapi.dart         # AES-CBC + RSA-1024 + ASN.1 DER
│   │   │       └── xeapi_helpers.dart # HMAC-SHA256 + AES-256-ECB
│   │   ├── core/
│   │   │   ├── config.dart            # 全局配置 + SharedPreferences
│   │   │   ├── cookie_manager.dart    # Cookie 解析/指纹
│   │   │   └── request_engine.dart    # 中央请求调度器
│   │   ├── api/
│   │   │   ├── auth_api.dart          # 认证（7 方法）
│   │   │   ├── music_api.dart         # 业务接口（11 方法）
│   │   │   └── xeapi_proxy.dart       # 云函数代理封装
│   │   ├── models/                    # Song/Lyric/Playlist/User/SearchResult
│   │   ├── services/
│   │   │   ├── auth_service.dart      # 认证编排
│   │   │   └── player_service.dart    # just_audio 封装
│   │   ├── state/
│   │   │   └── providers.dart         # Riverpod (auth/player/search/recommend)
│   │   └── ui/
│   │       ├── pages/
│   │       │   ├── home_page.dart     # 首页（推荐 + 快捷入口）
│   │       │   ├── search_page.dart   # 搜索
│   │       │   ├── playlist_page.dart # 歌单详情
│   │       │   ├── player_page.dart   # 全屏播放器 + 歌词
│   │       │   └── login_page.dart    # 扫码/手机号登录
│   │       └── widgets/
│   │           ├── mini_player.dart    # 底部迷你播放条
│   │           ├── song_tile.dart      # 歌曲列表项
│   │           ├── playlist_tile.dart  # 歌单列表项
│   │           ├── search_bar.dart     # 搜索框（含 debounce）
│   │           ├── search_result_list.dart # 搜索结果列表
│   │           ├── lyric_view.dart     # 歌词滚动视图
│   │           └── qr_login.dart       # QR 码登录组件
│   └── test/                          # 344 tests（23 个文件）
├── xeapi-proxy/                  # 云函数
│   ├── api/xeapi.js              #   自包含函数（381 行，零 npm 依赖）
│   ├── package.json
│   ├── vercel.json               #   Vercel 配置
│   └── wrangler.toml             #   Cloudflare Workers 配置
├── scripts/
│   └── gen_golden_vectors.js     # 黄金向量生成器
├── module/                       # 上游参考（400+ API 端点）
├── util/                         # 上游参考（加密/请求引擎）
└── interface.d.ts                # TypeScript 类型声明
```

## 核心概念

### 加密方案

| 方案 | 算法 | 典型端点 | 实现 |
|------|------|---------|------|
| **eapi** | MD5 + AES-ECB（128/256 自适应） | 搜索、歌单、歌词、QR登录 | `pointycastle` |
| **weapi** | AES-128-CBC×2 + RSA-1024 | 手机登录、推荐、用户歌单 | `pointycastle` |
| **xeapi** | X25519 ECDH + AES-128-GCM | 歌曲链接、游客注册 | **云函数**（Node 内置 `crypto`） |
| **xeapi sign** | HMAC-SHA256 + AES-256-ECB | X25519 公钥获取 | 直接 Dart（`crypto` 包） |
| **linuxapi** | AES-128-ECB | 桌面端专用 | 暂不移植 |
| **api** | 明文 | 少量旧端点 | 直接请求 |

### 认证流程

```
首次启动
  │
  ▼
生成 deviceId (52位hex) ──→ 持久化
  │
  ▼
register_anonimous() [xeapi] ──→ 云函数 ──→ 获取 MUSIC_A 游客token
  │
  ▼
【游客态】可搜索、试听
  │
  ├── QR码登录 ──→ login_qr_key [eapi] ──→ 获取 unikey
  │                 login_qr_check [eapi] ──→ 轮询 (每2s)
  │                 803成功 ──→ 获取 MUSIC_U + __csrf
  │
  └── 手机号登录 ──→ login_cellphone [weapi] ──→ 获取 MUSIC_U
  │
  ▼
【登录态】完整播放、收藏、评论
  │
  ▼
login_refresh() [eapi] ──→ 定期刷新token
```

### Cookie 管理

| 字段 | 说明 |
|------|------|
| `MUSIC_A` | 匿名游客 token（首次启动获取） |
| `MUSIC_U` | 登录用户 token（登录后获取） |
| `__csrf` | CSRF 防护 token（登录后获取） |
| `deviceId` | 设备标识（首次生成，持久化，52位 hex） |
| `osver` / `os` / `appver` / `channel` | 设备指纹（固定值） |

## 依赖项

### Flutter (Dart pub)

| 包 | 版本 | 用途 |
|---|---|---|
| `dio` | 5.9.2 | HTTP 客户端 |
| `pointycastle` | 3.9.1 | AES（CBC/ECB/GCM）+ RSA |
| `crypto` | 3.0.7 | MD5 / HMAC-SHA256 |
| `shared_preferences` | 2.5.5 | Cookie 持久化 |
| `just_audio` | 0.9.46 | 音频播放 |
| `qr_flutter` | 4.1.0 | QR 码生成 |
| `flutter_riverpod` | 2.6.1 | 状态管理 |
| `json_annotation` | 4.12.0 | JSON 模型 (dev: build_runner 2.15.0) |

### 云函数（零 npm 依赖）

仅使用 Node.js 内置 `crypto` / `zlib` / `fetch`。部署至 Vercel 或 Cloudflare Workers：

| 端点 | 用途 | 加密 |
|------|------|------|
| `/api/register/anonimous` | 获取游客 MUSIC_A | xeapi |
| `/api/song/enhance/player/url/v1` | 获取歌曲播放链接 | xeapi |

> `register_xeapikey`（X25519 公钥获取）已由 Dart 端 HMAC-SHA256 直连实现，无需云函数。

## 快速开始

```bash
# Flutter
cd app
flutter pub get
flutter run                 # debug

# Cloud function (Vercel)
cd ../xeapi-proxy
vercel deploy --prod

# Flutter with cloud function URL
flutter run --dart-define=XEAPI_PROXY_URL=https://your-domain.com/api/xeapi

# Tests
flutter test                # 344 tests
```

## 开发阶段

| # | 阶段 | 状态 |
|---|------|------|
| 0 | 项目脚手架 & 常量定义 | ✅ |
| 1 | Dart 加密原语层（weapi / eapi） | ✅ |
| 2 | 请求引擎 + Cookie 管理 | ✅ |
| 3 | 认证模块（登录/注册/QR/token） | ✅ |
| 4 | 核心业务接口（搜索/播放/歌单/歌词） | ✅ |
| Review | 全代码审查 + 测试增强 | ✅ |
| 5 | Flutter UI + 播放器（5 页面, 7 Widgets, Riverpod） | ✅ |
| 6 | 云函数部署（381 行, 零依赖, Vercel + CF Workers） | ✅ |

详见 [DEVELOPMENT_PLAN.md](./DEVELOPMENT_PLAN.md)

## 保密声明

本项目仅供学习研究使用，禁止用于商业或非法用途。所有 API 接口归网易云音乐所有，使用时请遵守相关服务条款。

## 致谢

- [Binaryify/NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi) — 原始项目
- [ndz-org/NeteaseCloudMusicApiEnhanced](https://github.com/ndz-org/NeteaseCloudMusicApiEnhanced) — 升级维护版

## 许可证

MIT
