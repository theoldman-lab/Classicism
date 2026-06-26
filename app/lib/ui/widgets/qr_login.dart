import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/auth_api.dart';

enum QrLoginStatus { loading, waiting, scanned, success, expired, error }

class QrCodeLogin extends StatefulWidget {
  final AuthApi authApi;
  final VoidCallback? onSuccess;

  const QrCodeLogin({
    super.key,
    required this.authApi,
    this.onSuccess,
  });

  @override
  State<QrCodeLogin> createState() => _QrCodeLoginState();
}

class _QrCodeLoginState extends State<QrCodeLogin> {
  QrLoginStatus _status = QrLoginStatus.loading;
  String? _unikey;
  String? _errorMessage;
  StreamSubscription? _pollSub;

  @override
  void initState() {
    super.initState();
    _startQrLogin();
  }

  @override
  void dispose() {
    _pollSub?.cancel();
    super.dispose();
  }

  Future<void> _startQrLogin() async {
    setState(() {
      _status = QrLoginStatus.loading;
      _errorMessage = null;
    });

    try {
      _unikey = await widget.authApi.getLoginQrKey();
      setState(() => _status = QrLoginStatus.waiting);
      _startPolling();
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = QrLoginStatus.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _startPolling() {
    _pollSub?.cancel();
    _pollSub = Stream.periodic(const Duration(seconds: 2))
        .asyncMap((_) => widget.authApi.checkLoginQr(_unikey!))
        .listen(
          (result) {
            if (!mounted) return;
            if (result.isSuccess) {
              setState(() => _status = QrLoginStatus.success);
              _pollSub?.cancel();
              widget.onSuccess?.call();
            } else if (result.isScanned) {
              setState(() => _status = QrLoginStatus.scanned);
            } else if (result.isExpired) {
              setState(() => _status = QrLoginStatus.expired);
              _pollSub?.cancel();
            }
          },
          onError: (e) {
            if (mounted) {
              setState(() {
                _status = QrLoginStatus.error;
                _errorMessage = e.toString();
              });
            }
          },
        );
  }

  String get _statusText {
    switch (_status) {
      case QrLoginStatus.loading:
        return '正在获取二维码...';
      case QrLoginStatus.waiting:
        return '请使用网易云音乐App扫码登录';
      case QrLoginStatus.scanned:
        return '已扫码，请在手机上确认登录';
      case QrLoginStatus.success:
        return '登录成功';
      case QrLoginStatus.expired:
        return '二维码已过期';
      case QrLoginStatus.error:
        return _errorMessage ?? '发生错误';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_unikey != null && _status != QrLoginStatus.loading) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: 'https://music.163.com/login?codekey=$_unikey',
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
        ] else if (_status == QrLoginStatus.loading) ...[
          const SizedBox(
            width: 200,
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          _statusText,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _status == QrLoginStatus.success
                ? Colors.green
                : theme.colorScheme.onSurface,
          ),
        ),
        if (_status == QrLoginStatus.expired || _status == QrLoginStatus.error) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _startQrLogin,
            icon: const Icon(Icons.refresh),
            label: const Text('刷新二维码'),
          ),
        ],
      ],
    );
  }
}
