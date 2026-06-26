import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:classicism/api/auth_api.dart';
import 'package:classicism/api/music_api.dart';
import 'package:classicism/core/config.dart';
import 'package:classicism/core/cookie_manager.dart';
import 'package:classicism/core/request_engine.dart';
import 'package:classicism/main.dart';
import 'package:classicism/services/auth_service.dart';
import 'package:classicism/services/player_service.dart';
import 'package:classicism/state/providers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App renders Material3 themed app', (WidgetTester tester) async {
    final config = AppConfig.instance;
    await config.init();

    final cookieManager = CookieManager(config);
    final dio = Dio();
    final directDio = Dio();

    final requestEngine = NeteaseRequest(
      dio: dio,
      cookie: cookieManager,
      config: config,
    );

    final musicApi = MusicApi(request: requestEngine);

    final authApi = AuthApi(
      request: requestEngine,
      directDio: directDio,
      config: config,
    );

    final authService = AuthService(api: authApi, config: config);
    final playerService = PlayerService(api: musicApi);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicApiProvider.overrideWithValue(musicApi),
          authServiceProvider.overrideWithValue(authService),
          playerServiceProvider.overrideWithValue(playerService),
          recommendSongsProvider.overrideWith((_) async => []),
        ],
        child: const ClassicismApp(),
      ),
    );

    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsAtLeast(1));
  });
}
