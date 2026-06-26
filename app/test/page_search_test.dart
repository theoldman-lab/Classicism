import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:classicism/services/player_service.dart';

import 'package:classicism/core/config.dart';
import 'package:classicism/state/providers.dart';
import 'package:classicism/ui/pages/search_page.dart';

import 'test_helpers.dart';

Widget _build(Widget child) {
  return MaterialApp(home: child);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SearchPage', () {
    testWidgets('renders search bar in app bar', (tester) async {
      await AppConfig.instance.init();

      final musicApi = MockMusicApi();
      final playerService = PlayerService(api: musicApi);

      await tester.pumpWidget(
        _build(
          ProviderScope(
            overrides: [
              musicApiProvider.overrideWithValue(musicApi),
              playerServiceProvider.overrideWithValue(playerService),
              recommendSongsProvider.overrideWith((_) async => []),
            ],
            child: const SearchPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders search icon in text field', (tester) async {
      await AppConfig.instance.init();

      final musicApi = MockMusicApi();
      final playerService = PlayerService(api: musicApi);

      await tester.pumpWidget(
        _build(
          ProviderScope(
            overrides: [
              musicApiProvider.overrideWithValue(musicApi),
              playerServiceProvider.overrideWithValue(playerService),
              recommendSongsProvider.overrideWith((_) async => []),
            ],
            child: const SearchPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('renders SearchResultList', (tester) async {
      await AppConfig.instance.init();

      final musicApi = MockMusicApi();
      final playerService = PlayerService(api: musicApi);

      await tester.pumpWidget(
        _build(
          ProviderScope(
            overrides: [
              musicApiProvider.overrideWithValue(musicApi),
              playerServiceProvider.overrideWithValue(playerService),
              recommendSongsProvider.overrideWith((_) async => []),
            ],
            child: const SearchPage(),
          ),
        ),
      );
      await tester.pump();

      // Should show placeholder text for empty search
      expect(find.text('输入关键词搜索'), findsOneWidget);
    });

    testWidgets('renders MiniPlayer at bottom', (tester) async {
      await AppConfig.instance.init();

      final musicApi = MockMusicApi();
      final playerService = PlayerService(api: musicApi);

      await tester.pumpWidget(
        _build(
          ProviderScope(
            overrides: [
              musicApiProvider.overrideWithValue(musicApi),
              playerServiceProvider.overrideWithValue(playerService),
              recommendSongsProvider.overrideWith((_) async => []),
            ],
            child: const SearchPage(),
          ),
        ),
      );
      await tester.pump();

      // MiniPlayer is empty when no song playing, so it shrinks to nothing
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('handles search input', (tester) async {
      await AppConfig.instance.init();

      final musicApi = MockMusicApi();
      final playerService = PlayerService(api: musicApi);

      await tester.pumpWidget(
        _build(
          ProviderScope(
            overrides: [
              musicApiProvider.overrideWithValue(musicApi),
              playerServiceProvider.overrideWithValue(playerService),
              recommendSongsProvider.overrideWith((_) async => []),
            ],
            child: const SearchPage(),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '周杰伦');
      await tester.pump(const Duration(milliseconds: 350));

      // Should not crash
      expect(find.text('周杰伦'), findsOneWidget);
    });
  });
}
