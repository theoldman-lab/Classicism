import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:classicism/ui/widgets/lyric_view.dart';

void main() {
  group('LyricView.parse', () {
    test('parses simple LRC line', () {
      final result = LyricView.parse('[00:01.00]hello');
      expect(result.length, 1);
      expect(result[0].$2, 'hello');
      expect(result[0].$1, const Duration(minutes: 0, seconds: 1, milliseconds: 0));
    });

    test('parses milliseconds correctly', () {
      final result = LyricView.parse('[00:00.50]text');
      expect(result.length, 1);
      expect(result[0].$1, const Duration(milliseconds: 500));
    });

    test('parses 3-digit milliseconds (centiseconds)', () {
      final result = LyricView.parse('[01:23.456]text');
      expect(result[0].$1, const Duration(minutes: 1, seconds: 23, milliseconds: 456));
    });

    test('parses multiple lines', () {
      const lrc = '[00:01.00]first\n[00:02.00]second\n[00:03.00]third';
      final result = LyricView.parse(lrc);
      expect(result.length, 3);
      expect(result.map((e) => e.$2), ['first', 'second', 'third']);
    });

    test('parses line with multiple timestamps', () {
      final result = LyricView.parse('[00:01.00][00:02.00]repeated');
      expect(result.length, 2);
      expect(result[0].$2, 'repeated');
      expect(result[1].$2, 'repeated');
    });

    test('skips lines without timestamps', () {
      final result = LyricView.parse('[ti:Title]\n[00:01.00]real');
      expect(result.length, 1);
      expect(result[0].$2, 'real');
    });

    test('returns empty for empty string', () {
      expect(LyricView.parse(''), isEmpty);
    });

    test('returns empty for string with no valid timestamps', () {
      expect(LyricView.parse('no timestamps here'), isEmpty);
    });

    test('sorts by time', () {
      final result = LyricView.parse('[00:03.00]c\n[00:01.00]a\n[00:02.00]b');
      expect(result.map((e) => e.$2), ['a', 'b', 'c']);
    });

    test('handles timestamp with colon separator', () {
      final result = LyricView.parse('[00:01:00]text');
      expect(result.length, 1);
      expect(result[0].$1, const Duration(minutes: 0, seconds: 1, milliseconds: 0));
    });
  });

  group('LyricView widget', () {
    testWidgets('renders lyric lines', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LyricView(lrcText: '[00:01.00]Hello\n[00:02.00]World'),
        ),
      ));
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('World'), findsOneWidget);
    });

    testWidgets('shows placeholder for empty lyrics', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LyricView(lrcText: '')),
      ));
      expect(find.text('暂无歌词'), findsOneWidget);
    });

    testWidgets('highlights current line in primary color', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LyricView(
            lrcText: '[00:01.00]Line1\n[00:02.00]Line2\n[00:03.00]Line3',
            position: const Duration(seconds: 2, milliseconds: 500),
          ),
        ),
      ));
      // Line2 should be current (position 2.5s >= 2.0s and < 3.0s)
      final line1Style = (tester.widget(find.text('Line1')) as Text).style;
      final line2Style = (tester.widget(find.text('Line2')) as Text).style;
      final line3Style = (tester.widget(find.text('Line3')) as Text).style;

      expect(line2Style?.fontWeight, FontWeight.bold);
      expect(line2Style?.fontSize, greaterThan(line1Style?.fontSize ?? 14));
      expect(line1Style?.fontWeight, isNot(FontWeight.bold));
      expect(line3Style?.fontWeight, isNot(FontWeight.bold));
    });

    testWidgets('first line highlighted when position is zero', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LyricView(
            lrcText: '[00:01.00]A\n[00:02.00]B',
          ),
        ),
      ));
      final aStyle = (tester.widget(find.text('A')) as Text).style;
      expect(aStyle?.fontWeight, FontWeight.bold);
    });

    testWidgets('uses ListView for scrolling', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LyricView(
            lrcText: '[00:01.00]A\n[00:02.00]B\n[00:03.00]C\n[00:04.00]D',
          ),
        ),
      ));
      expect(find.byType(ListView), findsOneWidget);
    });
  });
}
