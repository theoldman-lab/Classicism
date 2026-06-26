# Classicism — Flutter App

本地化网易云音乐 Android 客户端。核心加密层（weapi/eapi）纯 Dart 实现，xeapi 端点通过轻量云函数中转。不依赖外部服务器。

## 环境

- Flutter 3.41.6 · Dart SDK ^3.11.4
- Android only

## 快速开始

```bash
cd app
flutter pub get
flutter run      # debug
flutter test     # 271 tests
```

## 目录结构

```
app/
├── pubspec.yaml
├── lib/
│   ├── main.dart                      # App 入口 (Material3 + Riverpod)
│   ├── core/
│   │   └── crypto/
│   │       ├── constants.dart         # 密钥/域名/设备指纹常量 (Phase 0)
│   │       ├── helpers.dart           # hex/base64/random/base62 工具
│   │       ├── eapi.dart              # MD5 + AES-ECB (Phase 1)
│   │       ├── weapi.dart             # AES-128-CBC + RSA-1024 + ASN.1 DER (Phase 1)
│   │       └── xeapi_helpers.dart     # HMAC-SHA256 签名 + AES-256-ECB 解密 (Phase 3)
│   ├── core/
│   │   ├── config.dart                # 全局配置 + SharedPreferences 持久化 (Phase 2)
│   │   ├── cookie_manager.dart        # Cookie 解析/处理/指纹生成 (Phase 2)
│   │   └── request_engine.dart        # 中央请求调度器 (Phase 2)
│   ├── api/
│   │   ├── auth_api.dart              # 认证模块 (Phase 3)
│   │   ├── music_api.dart             # 核心业务接口 (Phase 4)
│   │   └── xeapi_proxy.dart           # XEAPI 云函数代理 (Phase 3)
│   ├── models/                        # 数据模型 (Song/Lyric/Playlist/User/SearchResult)
│   ├── services/                      # 服务层 (AuthService/PlayerService)
│   ├── state/                         # Riverpod providers (Phase 5)
│   └── ui/                            # (Phase 5) pages + widgets
└── test/
    ├── golden_vectors.json            # 17 黄金测试向量
    ├── eapi_test.dart                 # 34 tests
    ├── weapi_test.dart                # 18 tests
    ├── helpers_test.dart              # 28 tests
    ├── models_test.dart               # 21 tests
    ├── config_test.dart               # 17 tests
    ├── cookie_manager_test.dart       # 25 tests
    ├── request_engine_test.dart       # 31 tests
    ├── xeapi_helpers_test.dart        # 9 tests
    ├── xeapi_proxy_test.dart          # 8 tests
    ├── auth_api_test.dart             # 37 tests
    ├── auth_service_test.dart         # 8 tests
    ├── music_api_test.dart            # 27 tests
    └── widget_test.dart               # 1 test
```

## 开发阶段

| # | 阶段 | 状态 |
|---|------|------|
| 0 | 项目脚手架 & 常量 | ✅ |
| 1 | Dart 加密层 (eapi + weapi) | ✅ |
| 2 | 请求引擎 + Cookie 管理 | ✅ |
| 3 | 认证模块 | ✅ |
| 4 | 核心业务接口 | ✅ |
| Review | 全代码审查 + 测试增强 | ✅ |
| 5 | Flutter UI + 播放器 | ⬜ |
| 6 | 云函数部署 | ⬜ |

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

## 许可证

MIT — 参见根目录 LICENSE
