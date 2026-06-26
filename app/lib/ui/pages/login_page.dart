import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loginLoading = false;
  String? _loginError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    if (phone.isEmpty || password.isEmpty) {
      setState(() => _loginError = '请输入手机号和密码');
      return;
    }

    setState(() {
      _loginLoading = true;
      _loginError = null;
    });

    try {
      final result = await ref
          .read(authProvider.notifier)
          .loginWithPassword(phone, password);

      if (!mounted) return;

      if (result.isSuccess) {
        Navigator.pop(context);
      } else {
        setState(() => _loginError = '登录失败 (${result.code})');
      }
    } catch (e) {
      if (mounted) setState(() => _loginError = e.toString());
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '扫码登录'),
            Tab(text: '手机号登录'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildQrTab(theme),
          _buildPhoneTab(theme),
        ],
      ),
    );
  }

  Widget _buildQrTab(ThemeData theme) {
    // The QR widget needs AuthApi, which will be wired via Provider in main.dart
    // For now, we use a placeholder since providers aren't wired yet
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_scanner, size: 120, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text('扫码登录', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('请使用网易云音乐App扫描二维码',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 32),
            const Text('QR码登录将在云函数部署后启用',
                style: TextStyle(color: Colors.orange)),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '手机号',
              prefixIcon: Icon(Icons.phone_android),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _login(),
            decoration: const InputDecoration(
              labelText: '密码',
              prefixIcon: Icon(Icons.lock),
              border: OutlineInputBorder(),
            ),
          ),
          if (_loginError != null) ...[
            const SizedBox(height: 12),
            Text(_loginError!,
                style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loginLoading ? null : _login,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _loginLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('登录', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
