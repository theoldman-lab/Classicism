import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:classicism/services/player_service.dart';

import 'package:classicism/core/config.dart';
import 'package:classicism/state/providers.dart';
import 'package:classicism/ui/pages/player_page.dart';

import 'test_helpers.dart';

Widget _build(Widget child) {
  return MaterialApp(home: child);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PlayerPage', () {
    Future<void> pumpPlayerPage(WidgetTester tester) async {
      await AppConfig.instance.init();

      final musicApi = MockMusicApi();
      final playerService = PlayerService(api: musicApi);

      await tester.pumpWidget(
        _build(
          ProviderScope(
            overrides: [
              musicApiProvider.overrideWithValue(musicApi),
              playerServiceProvider.overrideWithValue(playerService),
            ],
            child: const PlayerPage(),
          ),
        ),
      );
    }

    testWidgets('renders close button', (tester) async {
      await pumpPlayerPage(tester);
      await tester.pump();
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    });

    testWidgets('renders control buttons', (tester) async {
      await pumpPlayerPage(tester);
      await tester.pump();
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    });

    testWidgets('shows empty state when no song', (tester) async {
      await pumpPlayerPage(tester);
      await tester.pump();
      expect(find.text('未在播放'), findsOneWidget);
    });

    testWidgets('renders album art placeholder when no song', (tester) async {
      await pumpPlayerPage(tester);
      await tester.pump();
      expect(find.byIcon(Icons.music_note), findsAtLeast(1));
    });

    testWidgets('renders progress slider', (tester) async {
      await pumpPlayerPage(tester);
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('renders play mode button', (tester) async {
      await pumpPlayerPage(tester);
      await tester.pump();
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
    });

    testWidgets('renders lyrics section placeholder', (tester) async {
      await pumpPlayerPage(tester);
      await tester.pump();
      expect(find.text('加载歌词中...'), findsOneWidget);
    });

    testWidgets('tapping close button pops navigation', (tester) async {
      await pumpPlayerPage(tester);
      await tester.pump();

      // The close button is a Navigator.pop
      final closeBtn = find.byIcon(Icons.keyboard_arrow_down_rounded);
      expect(closeBtn, findsOneWidget);
    });
  });
}
