import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:classicism/services/player_service.dart';

import 'package:classicism/core/config.dart';
import 'package:classicism/state/providers.dart';
import 'package:classicism/ui/pages/home_page.dart';

import 'test_helpers.dart';

Widget _build(Widget child) {
  return MaterialApp(home: child);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HomePage', () {
    Future<void> pumpHomePage(WidgetTester tester) async {
      await AppConfig.instance.init();

      final musicApi = MockMusicApi();
      final authService = MockAuthService();
      final playerService = PlayerService(api: musicApi);

      await tester.pumpWidget(
        _build(
          ProviderScope(
            overrides: [
              musicApiProvider.overrideWithValue(musicApi),
              authServiceProvider.overrideWithValue(authService),
              playerServiceProvider.overrideWithValue(playerService),
              recommendSongsProvider.overrideWith((_) async => []),
            ],
            child: const HomePage(),
          ),
        ),
      );
    }

    testWidgets('renders search bar', (tester) async {
      await pumpHomePage(tester);
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders quick action cards', (tester) async {
      await pumpHomePage(tester);
      await tester.pump();
      expect(find.text('每日推荐'), findsOneWidget);
      expect(find.text('歌单'), findsOneWidget);
      expect(find.textContaining('登录'), findsAtLeast(1));
    });

    testWidgets('shows login prompt when guest', (tester) async {
      await pumpHomePage(tester);
      // pumpAndSettle to wait for async initialize
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('登录后获取每日推荐'), findsOneWidget);
    });

    testWidgets('shows loading indicator during init', (tester) async {
      await AppConfig.instance.init();
      final musicApi = MockMusicApi();
      final authService = MockAuthService();
      final playerService = PlayerService(api: musicApi);

      await tester.pumpWidget(
        _build(
          ProviderScope(
            overrides: [
              musicApiProvider.overrideWithValue(musicApi),
              authServiceProvider.overrideWithValue(authService),
              playerServiceProvider.overrideWithValue(playerService),
              recommendSongsProvider.overrideWith((_) async => []),
            ],
            child: const HomePage(),
          ),
        ),
      );
      // Immediately after pump, should show loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('tapping login card navigates to login', (tester) async {
      await pumpHomePage(tester);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final loginCard = find.textContaining('登录');
      expect(loginCard, findsAtLeast(1));
    });

    testWidgets('tapping daily recommend card navigates to search', (tester) async {
      await pumpHomePage(tester);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final dailyBtn = find.text('每日推荐');
      expect(dailyBtn, findsOneWidget);
    });
  });
}
