import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/auth_api.dart';
import 'api/music_api.dart';
import 'api/xeapi_proxy.dart';
import 'core/config.dart';
import 'core/cookie_manager.dart';
import 'core/request_engine.dart';
import 'services/auth_service.dart';
import 'services/player_service.dart';
import 'state/providers.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/login_page.dart';
import 'ui/pages/player_page.dart';
import 'ui/pages/playlist_page.dart';
import 'ui/pages/search_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.instance;
  await config.init();

  final cookieManager = CookieManager(config);
  final dio = Dio();
  final directDio = Dio();

  // XEAPI cloud function URL — set via --dart-define or replace after deploy
  // e.g. 'https://classicism-xeapi.vercel.app/api/xeapi'
  const xeapiProxyUrl = String.fromEnvironment(
    'XEAPI_PROXY_URL',
    defaultValue: '',
  );

  final requestEngine = NeteaseRequest(
    dio: dio,
    cookie: cookieManager,
    config: config,
    xeapiProxyUrl: xeapiProxyUrl.isNotEmpty ? xeapiProxyUrl : null,
  );

  final xeapiProxy = xeapiProxyUrl.isNotEmpty
      ? XeapiProxy(dio: Dio(), proxyUrl: xeapiProxyUrl)
      : null;

  final musicApi = MusicApi(
    request: requestEngine,
    xeapiProxy: xeapiProxy,
  );

  final authApi = AuthApi(
    request: requestEngine,
    directDio: directDio,
    config: config,
    xeapiProxy: xeapiProxy,
  );

  final authService = AuthService(api: authApi, config: config);
  final playerService = PlayerService(api: musicApi);

  // Attempt guest registration; non-fatal if cloud function unavailable
  try {
    await authService.initialize();
  } catch (_) {
    // App runs in limited mode without MUSIC_A
  }

  runApp(
    ProviderScope(
      overrides: [
        musicApiProvider.overrideWithValue(musicApi),
        authServiceProvider.overrideWithValue(authService),
        playerServiceProvider.overrideWithValue(playerService),
      ],
      child: const ClassicismApp(),
    ),
  );
}

class ClassicismApp extends StatelessWidget {
  const ClassicismApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Classicism',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE53333),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE53333),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      initialRoute: '/',
      routes: {
        '/': (_) => const HomePage(),
        '/search': (_) => const SearchPage(),
        '/playlist': (_) => const PlaylistPage(),
        '/player': (_) => const PlayerPage(),
        '/login': (_) => const LoginPage(),
      },
    );
  }
}
