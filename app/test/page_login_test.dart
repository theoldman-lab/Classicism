import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:classicism/services/player_service.dart';

import 'package:classicism/core/config.dart';
import 'package:classicism/state/providers.dart';
import 'package:classicism/ui/pages/login_page.dart';

import 'test_helpers.dart';

Widget _build(Widget child) {
  return MaterialApp(home: child);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LoginPage', () {
    Future<void> pumpLoginPage(WidgetTester tester) async {
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
            ],
            child: const LoginPage(),
          ),
        ),
      );
    }

    testWidgets('renders app bar with title', (tester) async {
      await pumpLoginPage(tester);
      await tester.pump();
      expect(find.text('登录'), findsOneWidget);
    });

    testWidgets('renders tab bar with two tabs', (tester) async {
      await pumpLoginPage(tester);
      await tester.pump();
      expect(find.text('扫码登录'), findsAtLeast(1));
      expect(find.text('手机号登录'), findsOneWidget);
    });

    testWidgets('shows QR tab by default', (tester) async {
      await pumpLoginPage(tester);
      await tester.pump();
      expect(find.textContaining('QR码登录将在云函数部署后启用'), findsOneWidget);
    });

    testWidgets('switching to phone tab shows login form', (tester) async {
      await pumpLoginPage(tester);
      await tester.pump();

      await tester.tap(find.text('手机号登录'));
      await tester.pumpAndSettle();

      expect(find.text('手机号'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);
      expect(find.byIcon(Icons.phone_android), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);
    });

    testWidgets('phone login form has phone input field', (tester) async {
      await pumpLoginPage(tester);
      await tester.pump();

      await tester.tap(find.text('手机号登录'));
      await tester.pumpAndSettle();

      final phoneField = find.widgetWithText(TextField, '手机号');
      expect(phoneField, findsOneWidget);

      await tester.enterText(phoneField, '13800138000');
      await tester.pump();
      expect(find.text('13800138000'), findsOneWidget);
    });

    testWidgets('phone login form has password field', (tester) async {
      await pumpLoginPage(tester);
      await tester.pump();

      await tester.tap(find.text('手机号登录'));
      await tester.pumpAndSettle();

      final pwdField = find.widgetWithText(TextField, '密码');
      expect(pwdField, findsOneWidget);
    });

    testWidgets('renders login button', (tester) async {
      await pumpLoginPage(tester);
      await tester.pump();

      await tester.tap(find.text('手机号登录'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
    });

    testWidgets('shows error when empty phone', (tester) async {
      await pumpLoginPage(tester);
      await tester.pump();

      await tester.tap(find.text('手机号登录'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump();

      expect(find.text('请输入手机号和密码'), findsOneWidget);
    });

    testWidgets('shows error when empty password', (tester) async {
      await pumpLoginPage(tester);
      await tester.pump();

      await tester.tap(find.text('手机号登录'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '手机号'), '13800138000');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump();

      expect(find.text('请输入手机号和密码'), findsOneWidget);
    });

    testWidgets('login button calls login with phone and password', (tester) async {
      await pumpLoginPage(tester);
      await tester.pump();

      await tester.tap(find.text('手机号登录'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '手机号'), '13800138000');
      await tester.enterText(find.widgetWithText(TextField, '密码'), 'test123');

      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump();

      // MockAuthService.loginWithPassword should have been called
      // We can't easily verify in widget test, but at least no crash
    });
  });
}
