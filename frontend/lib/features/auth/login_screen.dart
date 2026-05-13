import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/controllers/auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    AuthController.to.login(_emailCtrl.text.trim(), _passwordCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
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
                    Icon(Icons.school_rounded,
                        size: 56, color: colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      'UB Timetabling',
                      textAlign: TextAlign.center,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sign in to continue',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: colorScheme.outline),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
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
                      validator: (v) =>
                          (v == null || v.length < 6) ? 'Min 6 characters' : null,
                    ),
                    const SizedBox(height: 8),
                    // Error message
                    Obx(() {
                      final err = AuthController.to.errorMessage.value;
                      if (err.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          err,
                          style: TextStyle(color: colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Obx(() {
                      final loading = AuthController.to.isLoading.value;
                      return FilledButton(
                        onPressed: loading ? null : _submit,
                        child: loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Sign In'),
                      );
                    }),
                    const SizedBox(height: 24),
                    _TestAccountsPanel(
                      onSelect: (email, pass) {
                        _emailCtrl.text = email;
                        _passwordCtrl.text = pass;
                      },
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

class _TestAccountsPanel extends StatefulWidget {
  final void Function(String email, String password) onSelect;
  const _TestAccountsPanel({required this.onSelect});

  @override
  State<_TestAccountsPanel> createState() => _TestAccountsPanelState();
}

class _TestAccountsPanelState extends State<_TestAccountsPanel> {
  bool _expanded = false;

  static const _accounts = [
    (label: 'Super Admin',        email: 'superadmin@ub.cm', pass: 'super123',    color: Colors.purple),
    (label: 'University Admin',   email: 'admin@ub.cm',      pass: 'admin123',    color: Colors.blue),
    (label: 'Faculty Head (FET)', email: 'fethead@ub.cm',    pass: 'fethead123',  color: Colors.teal),
    (label: 'Timetable Officer',  email: 'officer@ub.cm',    pass: 'officer123',  color: Colors.indigo),
    (label: 'Lecturer',           email: 'lecturer@ub.cm',   pass: 'lecturer123', color: Colors.green),
    (label: 'Student',            email: 'student@ub.cm',    pass: 'student123',  color: Colors.grey),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.developer_mode_outlined,
                    size: 16, color: cs.outline),
                const SizedBox(width: 6),
                Text('Test Accounts',
                    style: TextStyle(fontSize: 13, color: cs.outline)),
                const SizedBox(width: 4),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: cs.outline),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withAlpha(80),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              children: _accounts.map((a) {
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => widget.onSelect(a.email, a.pass),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: a.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              Text(a.email,
                                  style: TextStyle(
                                      fontSize: 11, color: cs.outline)),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios,
                            size: 12, color: cs.outline),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
