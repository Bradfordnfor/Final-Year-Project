import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api/api_client.dart';
import '../../core/api/auth_api.dart';
import '../../core/routes.dart';

/// Unauthenticated page opened from the email-change confirmation email
/// (`/#/confirm-email?token=…`). Confirms the change on load and reports the
/// outcome.
class ConfirmEmailScreen extends StatefulWidget {
  const ConfirmEmailScreen({super.key});

  @override
  State<ConfirmEmailScreen> createState() => _ConfirmEmailScreenState();
}

class _ConfirmEmailScreenState extends State<ConfirmEmailScreen> {
  bool _loading = true;
  bool _success = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _confirm();
  }

  Future<void> _confirm() async {
    final token = Get.parameters['token'];
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _success = false;
        _message = 'This confirmation link is missing its token.';
      });
      return;
    }
    try {
      await AuthApi(ApiClient()).confirmEmail(token);
      setState(() {
        _loading = false;
        _success = true;
        _message =
            'Your email address has been updated. You can sign in with it now.';
      });
    } on DioException catch (e) {
      final detail = (e.response?.data as Map?)?['detail'] as String?;
      setState(() {
        _loading = false;
        _success = false;
        _message =
            detail ?? 'This confirmation link is invalid or has expired.';
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _success = false;
        _message = 'Cannot reach the server. Please try again later.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    )
                  else ...[
                    Icon(
                      _success
                          ? Icons.mark_email_read_outlined
                          : Icons.error_outline,
                      size: 56,
                      color: _success ? cs.primary : cs.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _success ? 'Email confirmed' : 'Confirmation failed',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(_message, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Get.offAllNamed(AppRoutes.login),
                      child: const Text('Go to sign in'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
