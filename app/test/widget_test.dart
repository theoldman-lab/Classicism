import 'package:flutter_test/flutter_test.dart';

import 'package:classicism/main.dart';

void main() {
  testWidgets('App renders Phase 0 placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(const ClassicismApp());

    expect(find.text('Classicism - Phase 0 Ready'), findsOneWidget);
  });
}
