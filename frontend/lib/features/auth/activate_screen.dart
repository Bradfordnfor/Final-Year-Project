import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api/api_client.dart';
import '../../core/api/auth_api.dart';
import '../../core/controllers/auth_controller.dart';
import '../../core/routes.dart';

/// Unauthenticated page opened from the activation email
/// (`/#/activate?token=…`). The user sets a password; on success we auto-login.
class ActivateScreen extends StatefulWidget {
  const ActivateScreen({super.key});

  @override
  State<ActivateScreen> createState() => _ActivateScreenState();
}

class _ActivateScreenState extends State<ActivateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  String? get _token => Get.parameters['token'];

  @override
  void dispose() {
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final token = _token;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'This activation link is missing its token.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await AuthApi(ApiClient()).activate(token, _pwCtrl.text);
      await AuthController.to.applyToken(result); // auto-login + redirect
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = (e.response?.data as Map?)?['detail'] as String?;
      setState(() {
        _error = detail ??
            'Could not activate. The link may be invalid or expired.';
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Cannot reach the server. Check your connection and try again.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final missingToken = _token == null || _token!.isEmpty;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Image.asset('assets/images/logo.png',
                            height: 160, filterQuality: FilterQuality.high),
                      ),
                      const SizedBox(height: 8),
                      Text('Activate your account',
                          textAlign: TextAlign.center,
                          style: textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Set a password to finish setting up your account.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium
                              ?.copyWith(color: cs.outline)),
                      const SizedBox(height: 24),
                      if (missingToken)
                        Text(
                          'This activation link is missing its token. Please '
                          'open the link from your invitation email again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.error),
                        )
                      else ...[
                        TextFormField(
                          controller: _pwCtrl,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'New password',
                            prefixIcon: const Icon(Icons.lock_outlined),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) => (v == null || v.length < 6)
                              ? 'Min 6 characters'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmCtrl,
                          obscureText: _obscure,
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: Icon(Icons.lock_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v != _pwCtrl.text)
                              ? 'Passwords do not match'
                              : null,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.error)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Activate & sign in'),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Get.offAllNamed(AppRoutes.login),
                        child: const Text('Back to sign in'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
