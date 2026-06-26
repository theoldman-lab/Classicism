# Classicism — 本地化网易云音乐 Android 客户端

基于 [NeteaseCloudMusicApiEnhanced](https://github.com/ndz-org/NeteaseCloudMusicApiEnhanced) 的 API 逆向工程成果，构建一个**完全本地化、无需外部服务器**的轻量化 Android 网易云音乐客户端。采用 **Flutter + Dart** 技术栈，核心加密逻辑直接移植至 Dart 层，仅 `xeapi` 端点使用轻量云函数中转。

## 设计目标

- **零外部依赖**：除 `xeapi` 云函数（约 3 个端点）外，所有请求直连 music.163.com
- **纯 Dart 加密**：`weapi` / `eapi` 方案在 Dart 内完成，无需嵌入 Node.js
- **轻量化**：仅实现 MVP 功能（登录、搜索、播放、歌单、歌词），体量控制在 30MB 以内
- **完全开源**：无混淆、无商业 SDK 依赖

## 架构概览

```
┌──────────────────────────────────────────────┐
│ Flutter App (Android)                        │
│                                              │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐ │
│  │ weapi     │  │ eapi      │  │ xeapi      │ │
│  │ (纯Dart)  │  │ (纯Dart)  │  │ (云函数代理)│ │
│  └────┬─────┘  └────┬─────┘  └─────┬──────┘ │
│       │             │              │         │
│       └──────┬──────┘              │         │
│              │                     │         │
│        ┌─────┴──────┐       ┌─────┴──────┐  │
│        │ Request     │       │ Vercel     │  │
│        │ Engine      │       │ Function   │  │
│        │ (cookie管理) │       │ (透传加密)  │  │
│        └─────┬──────┘       └─────┬──────┘  │
│              │                     │         │
└──────────────┼─────────────────────┼─────────┘
               ▼                     ▼
         music.163.com          music.163.com
        (weapi/eapi)             (xeapi)
```

## 目录结构

```
Classicism/
├── README.MD                # 项目说明
├── DEVELOPMENT_PLAN.md      # 详细开发计划
├── WORKLOG.md               # 工作日志
├── app/                     # Flutter 应用（Android 目标）
│   ├── pubspec.yaml         #   Dart 依赖
│   ├── lib/
│   │   ├── main.dart        #   入口（Material3 + Riverpod）
│   │   ├── core/
│   │   │   └── crypto/
│   │   │       ├── constants.dart   # 所有密钥/域名/设备指纹常量 (Phase 0)
│   │   │       ├── helpers.dart     # hex/base64/random/base62 工具
│   │   │       ├── eapi.dart        # MD5 + AES-ECB（128/192/256 自适应）
│   │   │       ├── weapi.dart       # AES-128-CBC + RSA-1024 + ASN.1 DER
│   │   │       └── xeapi_helpers.dart # HMAC-SHA256 签名 + AES-256-ECB 解密 (Phase 3)
│   │   ├── core/
│   │   │   ├── config.dart          # 全局配置 + SharedPreferences 持久化
│   │   │   ├── cookie_manager.dart  # Cookie 解析/处理/指纹生成
│   │   │   └── request_engine.dart  # 中央请求调度器（Crypto 分发 + HTTP）
│   │   ├── api/
│   │   │   ├── auth_api.dart        # 认证模块（7 方法：注册/登录/QR/token）
│   │   │   ├── music_api.dart       # 核心业务接口（9 方法 + 2 便捷）
│   │   │   └── xeapi_proxy.dart     # XEAPI 云函数代理封装
│   │   ├── models/                  # 数据模型（Song/Lyric/Playlist/User/SearchResult）
│   │   ├── services/                # 服务层（AuthService/PlayerService）
│   │   └── state/                   # 状态管理骨架 (Phase 5)
│   └── test/
│       ├── golden_vectors.json      # 17 个黄金测试向量
│       ├── eapi_test.dart           # 34 tests
│       ├── weapi_test.dart          # 18 tests
│       ├── helpers_test.dart        # 28 tests
│       ├── models_test.dart         # 21 tests
│       ├── config_test.dart         # 17 tests
│       ├── cookie_manager_test.dart # 25 tests
│       ├── request_engine_test.dart # 31 tests
│       ├── xeapi_helpers_test.dart  # 9 tests
│       ├── xeapi_proxy_test.dart    # 8 tests
│       ├── auth_api_test.dart       # 37 tests
│       ├── auth_service_test.dart   # 8 tests
│       ├── music_api_test.dart      # 27 tests
│       └── widget_test.dart         # 1 test
├── scripts/
│   └── gen_golden_vectors.js        # 黄金向量生成器
├── test/
│   └── golden_vectors.json          # 生成物（17 vectors）
├── interface.d.ts                   # 完整 TypeScript 类型声明（Dart 模型参考）
├── package.json                     # 上游项目依赖信息
├── module/                          # 400+ API端点定义（移植参考）
│   ├── login_cellphone.js           #   手机号登录 (weapi)
│   ├── login_qr_key.js              #   QR登录-获取密钥 (eapi)
│   ├── login_qr_check.js            #   QR登录-轮询状态 (eapi)
│   ├── register_anonimous.js        #   游客登录 (xeapi)
│   ├── register_xeapikey.js          #   获取X25519公钥 (特殊直接 API)
│   ├── search.js                    #   搜索 (eapi)
│   ├── song_url_v1.js               #   歌曲播放链接 (xeapi)
│   ├── lyric.js                     #   歌词 (eapi)
│   ├── song_detail.js               #   歌曲详情 (weapi)
│   ├── playlist_detail.js           #   歌单详情 (eapi)
│   ├── user_playlist.js             #   用户歌单 (weapi)
│   ├── recommend_songs.js           #   每日推荐 (weapi)
│   └── ...                          #   其余380+端点
└── util/                            # 核心工具库（加密移植源）
    ├── crypto.js                    #   6种加密方案：weapi/eapi/linuxapi/xeapi/api
    ├── request.js                   #   请求引擎：cookie管理、加密分发、响应解密
    ├── index.js                     #   Cookie/deviceId工具函数
    ├── option.js                    #   请求选项构造
    ├── config.json                  #   API域名及配置常量
    ├── xeapiKey.js                  #   X25519密钥管理
    ├── client-sign.js               #   客户端签名
    ├── apicache.js                  #   响应缓存中间件
    └── memory-cache.js              #   内存TTL缓存
```

## 核心概念

### 加密方案

| 方案 | 算法 | 典型端点 | Dart 移植 |
|------|------|---------|-----------|
| **eapi** | MD5 + AES-ECB（128/256 自适应） | 搜索、歌单、歌词、QR登录 | `pointycastle` |
| **weapi** | AES-128-CBC×2 + RSA-1024 | 手机登录、推荐、用户歌单、歌曲详情 | `pointycastle` |
| **xeapi** | X25519 ECDH + AES-128-GCM | 歌曲链接、游客登录 | **云函数代理** |
| **xeapi sign** | HMAC-SHA256 + AES-256-ECB | X25519 公钥获取 | 直接 Dart 实现 |
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
【游客态】可搜索、试听（30秒）
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

关键持久化字段：
- `MUSIC_A` — 匿名游客token（首次启动获取）
- `MUSIC_U` — 登录用户token（登录后获取）
- `__csrf` — CSRF防护token（登录后获取）
- `deviceId` — 设备标识（首次生成，持久化，52位hex）
- `osver` / `os` / `appver` / `channel` — 设备指纹（固定值）

## 依赖项

### Flutter (Dart pub, resolved)
| 包 | 版本 | 用途 |
|---|---|---|
| `dio` | 5.9.2 | HTTP 客户端 |
| `pointycastle` | 3.9.1 | AES（CBC/ECB/GCM）+ RSA |
| `crypto` | 3.0.7 | MD5 / HMAC-SHA256 |
| `shared_preferences` | 2.5.5 | Cookie 持久化 |
| `just_audio` | 0.9.46 | 音频播放 |
| `qr_flutter` | 4.1.0 | QR码生成 |
| `flutter_riverpod` | 2.6.1 | 状态管理 |
| `json_annotation` | 4.12.0 | JSON 模型 |
| `build_runner` | 2.15.0 | 代码生成 (dev) |

**环境**：Flutter 3.41.6 · Dart SDK ^3.11.4 · Android (only)

### 云函数（仅 3 个端点）

部署至 Vercel / Cloudflare Workers，最小化代码（复用现有 crypto.js）：

| 端点 | 用途 |
|---|---|
| `register_anonimous` | 获取游客 MUSIC_A |
| `register_xeapikey` | 获取 X25519 公钥 |
| `song_url_v1` | 获取歌曲播放链接 |

## 开发阶段

详见 [DEVELOPMENT_PLAN.md](./DEVELOPMENT_PLAN.md)

| # | 阶段 | 状态 |
|---|------|------|
| 0 | 项目脚手架 & 常量定义 | ✅ |
| 1 | Dart 加密原语层（weapi / eapi） | ✅ |
| 2 | 请求引擎 + Cookie 管理 | ✅ |
| 3 | 认证模块（登录/注册/QR/token） | ✅ |
| 4 | 核心业务接口（搜索/播放/歌单/歌词） | ✅ |
| Review | 全代码审查 + 测试增强（271 tests, 零错误） | ✅ |
| 5 | Flutter UI + 播放器 | ⬜ |
| 6 | 云函数部署 | ⬜ |

## 保密声明

本项目仅供学习研究使用，禁止用于商业或非法用途。所有 API 接口归网易云音乐所有，使用时请遵守相关服务条款。

## 致谢

- [Binaryify/NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi) — 原始项目
- [ndz-org/NeteaseCloudMusicApiEnhanced](https://github.com/ndz-org/NeteaseCloudMusicApiEnhanced) — 升级维护版
- `@neteasecloudmusicapienhanced/api` — npm 包

## 许可证

MIT
