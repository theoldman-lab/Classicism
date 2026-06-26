import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:classicism/ui/widgets/search_bar.dart';

void main() {
  group('ClassicismSearchBar', () {
    testWidgets('renders with hint text', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ClassicismSearchBar(onSearch: (_) {})),
      ));
      expect(find.text('搜索歌曲、歌单'), findsOneWidget);
    });

    testWidgets('renders with custom hint', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ClassicismSearchBar(onSearch: (_) {}, hintText: 'Custom')),
      ));
      expect(find.text('Custom'), findsOneWidget);
    });

    testWidgets('renders search icon', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ClassicismSearchBar(onSearch: (_) {})),
      ));
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('calls onSearch when submitted', (tester) async {
      String? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ClassicismSearchBar(onSearch: (v) => result = v)),
      ));
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(result, 'hello');
    });

    testWidgets('calls onSearch after debounce', (tester) async {
      String? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ClassicismSearchBar(onSearch: (v) => result = v)),
      ));
      await tester.enterText(find.byType(TextField), 'test');
      // Advance past debounce timer (300ms)
      await tester.pump(const Duration(milliseconds: 350));
      expect(result, 'test');
    });

    testWidgets('does not call onSearch for empty query', (tester) async {
      String? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ClassicismSearchBar(onSearch: (v) => result = v)),
      ));
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump(const Duration(milliseconds: 350));
      expect(result, isNull);
    });

    testWidgets('shows clear button when text entered', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ClassicismSearchBar(onSearch: (_) {})),
      ));
      await tester.enterText(find.byType(TextField), 'x');
      await tester.pump();
      expect(find.byIcon(Icons.clear_rounded), findsOneWidget);
    });

    testWidgets('clear button clears text', (tester) async {
      String? lastSearch;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ClassicismSearchBar(onSearch: (v) {
            lastSearch = v;
          }),
        ),
      ));
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump(const Duration(milliseconds: 350));
      expect(lastSearch, 'hello');

      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pump();
      expect(find.text('hello'), findsNothing);
    });

    testWidgets('trims whitespace from query', (tester) async {
      String? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ClassicismSearchBar(onSearch: (v) => result = v)),
      ));
      await tester.enterText(find.byType(TextField), '  hello  ');
      await tester.pump(const Duration(milliseconds: 350));
      expect(result, 'hello');
    });

    testWidgets('cancels previous debounce on new input', (tester) async {
      final results = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ClassicismSearchBar(onSearch: results.add)),
      ));
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump(const Duration(milliseconds: 350));
      // Only last value should trigger
      expect(results.length, 1);
      expect(results.first, 'abc');
    });
  });
}
