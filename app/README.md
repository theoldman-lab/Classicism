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
flutter test     # 46 tests
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
│   │       ├── helpers.dart           # hex/base64/random 工具
│   │       ├── eapi.dart              # MD5 + AES-128-ECB (Phase 1)
│   │       └── weapi.dart             # AES-128-CBC + RSA-1024 (Phase 1)
│   ├── core/                          # (Phase 2) cookie_manager, request_engine, config
│   ├── api/                           # (Phase 3-4) auth_api, music_api, xeapi_proxy
│   ├── models/                        # 数据模型骨架
│   ├── services/                      # 服务层骨架
│   ├── state/                         # Riverpod providers
│   └── ui/                            # (Phase 5) pages + widgets
└── test/
    ├── golden_vectors.json            # 17 黄金测试向量
    ├── eapi_test.dart                 # 28 tests
    └── weapi_test.dart                # 18 tests
```

## 开发阶段

| # | 阶段 | 状态 |
|---|------|------|
| 0 | 项目脚手架 & 常量 | ✅ |
| 1 | Dart 加密层 (eapi + weapi) | ✅ |
| 2 | 请求引擎 + Cookie 管理 | ⬜ |
| 3 | 认证模块 | ⬜ |
| 4 | 核心业务接口 | ⬜ |
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
