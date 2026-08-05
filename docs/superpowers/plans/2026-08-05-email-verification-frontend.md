# Email Verification Frontend (Phase D) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Flutter web frontend for the already-shipped email-verification backend: account-activation and email-confirmation pages, a login "resend activation" affordance, and the create-user / university-creation / bulk-import / change-email UX changes that go with pending (password-less) accounts.

**Architecture:** Two new unauthenticated GetX routes (`/activate`, `/confirm-email`) that read their token from `Get.parameters['token']` and call the existing `POST /auth/activate` and `POST /auth/confirm-email`. Activation auto-logs-in by reusing the `TokenResponse` the endpoint returns. The app keeps Flutter web's **default hash URL strategy**; the backend link builders are changed to emit `/#/…` so the emailed links resolve with zero web-server config. Existing forms that used to take/show passwords are updated to reflect that accounts are now activated by their owner via email.

**Tech Stack:** Flutter (web), GetX (routing + state), Dio (HTTP). Backend: FastAPI + pytest. Flutter package name: `university_timetabling`.

## Global Constraints

- Flutter package import prefix in tests is `package:university_timetabling/…`.
- Backend base URL the app talks to: `http://localhost:8000` (`lib/core/constants.dart`).
- **Hash routing only** — do NOT add `usePathUrlStrategy`/`setUrlStrategy`. Emailed links must be of the form `{app_base_url}/#/activate?token=…` and `{app_base_url}/#/confirm-email?token=…`.
- Password minimum length is **6** characters everywhere (matches the backend `/auth/activate` and change-password rules).
- **No passwords are ever shown, typed at creation, or stored in the UI.** Accounts are activated by their owner through the emailed link.
- Login not-verified response is HTTP **403** with detail `"Email not verified. Check your inbox or request a new activation link."`.
- Resend-activation UI copy must be generic ("If that account exists, we've sent a new activation link.") — never confirm whether an account exists.
- Commit messages: plain sentences, no `feat:`/`fix:` prefixes, no `Co-Authored-By` line (project convention).
- Per-frontend-task verification gate: `flutter analyze` from `frontend/` must report **No issues found!** (no new errors/warnings).

---

## File Map

**Backend (Task 1)**
- Modify: `backend/app/services/email.py` — `activation_link()` emits hash form.
- Modify: `backend/app/routers/auth.py:120` — confirm-email link emits hash form.
- Modify: `backend/tests/test_activation.py` — assert `/#/activate?token=`.
- Modify: `backend/tests/test_email_change.py` — assert `/#/confirm-email?token=`.

**Frontend**
- Modify: `frontend/lib/core/api/auth_api.dart` — add `activate`, `confirmEmail`, `resendActivation`; change `changeEmail` return type (Task 2 + Task 8).
- Modify: `frontend/lib/core/controllers/auth_controller.dart` — `applyToken`, 403 detection, `resendActivation`.
- Modify: `frontend/lib/core/routes.dart` — register `/activate`, `/confirm-email`.
- Create: `frontend/lib/features/auth/activate_screen.dart`.
- Create: `frontend/lib/features/auth/confirm_email_screen.dart`.
- Modify: `frontend/lib/features/auth/login_screen.dart` — resend affordance.
- Modify: `frontend/lib/features/management/management_screen.dart` — drop password field.
- Modify: `frontend/lib/features/universities/universities_screen.dart` — drop admin password, show activation link.
- Modify: `frontend/lib/core/widgets/app_shell.dart` — change-email confirmation messaging.
- Modify: `frontend/lib/features/bulk_import/bulk_import_screen.dart` — invitation UX.

---

## Task 1: Backend — hash-routing activation & confirm links

**Files:**
- Modify: `backend/app/services/email.py:45`
- Modify: `backend/app/routers/auth.py:120`
- Test: `backend/tests/test_activation.py:69,101`
- Test: `backend/tests/test_email_change.py:14`

**Interfaces:**
- Produces: emailed links of shape `{app_base_url}/#/activate?token=<raw>` and `{app_base_url}/#/confirm-email?token=<raw>`. Frontend Tasks 3–4 rely on this hash form landing on the GetX routes.

- [ ] **Step 1: Tighten the activation test to require the hash form**

In `backend/tests/test_activation.py`, line 69 currently reads:

```python
    assert any(re.search(r"/activate\?token=\S+", m["text"]) for m in sent_emails)
```

Change it to require the hash prefix:

```python
    assert any(re.search(r"/#/activate\?token=\S+", m["text"]) for m in sent_emails)
```

And line 101 currently reads:

```python
    assert "/activate?token=" in r.json()["admin_activation_link"]
```

Change it to:

```python
    assert "/#/activate?token=" in r.json()["admin_activation_link"]
```

- [ ] **Step 2: Tighten the email-change test to require the hash form**

In `backend/tests/test_email_change.py`, line 14 currently reads:

```python
        match = re.search(r"/confirm-email\?token=(\S+)", m["text"])
```

Change it to:

```python
        match = re.search(r"/#/confirm-email\?token=(\S+)", m["text"])
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd backend && python -m pytest tests/test_activation.py tests/test_email_change.py -q`
Expected: FAIL — the emailed links still lack `/#/`, so the tightened regexes/substrings no longer match (activation email test, admin_activation_link test, and email-change token extraction all fail).

- [ ] **Step 4: Make `activation_link` emit the hash form**

In `backend/app/services/email.py`, the function at line 41 currently returns:

```python
    return f"{settings.app_base_url}/activate?token={raw}"
```

Change it to:

```python
    return f"{settings.app_base_url}/#/activate?token={raw}"
```

- [ ] **Step 5: Make the confirm-email link emit the hash form**

In `backend/app/routers/auth.py`, line 120 currently reads:

```python
    link = f"{settings.app_base_url}/confirm-email?token={raw}"
```

Change it to:

```python
    link = f"{settings.app_base_url}/#/confirm-email?token={raw}"
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd backend && python -m pytest tests/test_activation.py tests/test_email_change.py -q`
Expected: PASS (all activation and email-change tests green).

- [ ] **Step 7: Run the full backend suite to confirm no regressions**

Run: `cd backend && python -m pytest -q`
Expected: PASS (whole suite green — was 186 before this change).

- [ ] **Step 8: Commit**

```bash
git add backend/app/services/email.py backend/app/routers/auth.py backend/tests/test_activation.py backend/tests/test_email_change.py
git commit -m "email verification: emit hash-routing activation and confirm links for the Flutter web frontend"
```

---

## Task 2: Frontend API — activate, confirm, resend methods

**Files:**
- Modify: `frontend/lib/core/api/auth_api.dart`

**Interfaces:**
- Consumes: `ApiClient` (`lib/core/api/api_client.dart`) `post(path, {data})`; `TokenResponse.fromJson` (`lib/core/models/user.dart`).
- Produces:
  - `AuthApi.activate(String token, String newPassword) -> Future<TokenResponse>`
  - `AuthApi.confirmEmail(String token) -> Future<void>`
  - `AuthApi.resendActivation(String email) -> Future<void>`
  These are consumed by Tasks 3, 4, and 5.

- [ ] **Step 1: Add the three methods to `AuthApi`**

In `frontend/lib/core/api/auth_api.dart`, add these methods inside the `AuthApi` class (place them after `getMe`, before `changePassword`):

```dart
  /// Sets the password for a pending account via an activation token and logs
  /// the user in. Returns the same token/user shape as `/auth/login`.
  Future<TokenResponse> activate(String token, String newPassword) async {
    final response = await _client.post('/auth/activate', data: {
      'token': token,
      'new_password': newPassword,
    });
    return TokenResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Confirms an email-change token, switching the account to the new address.
  Future<void> confirmEmail(String token) async {
    await _client.post('/auth/confirm-email', data: {'token': token});
  }

  /// Requests a fresh activation email for a pending account. The backend
  /// always responds generically, so callers must not reveal whether the
  /// account exists.
  Future<void> resendActivation(String email) async {
    await _client.post('/auth/resend-activation', data: {'email': email});
  }
```

- [ ] **Step 2: Verify analyze is clean**

Run: `cd frontend && flutter analyze`
Expected: No issues found!

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/core/api/auth_api.dart
git commit -m "frontend api: add activate, confirm-email, and resend-activation calls"
```

---

## Task 3: Activation route + auto-login

**Files:**
- Modify: `frontend/lib/core/controllers/auth_controller.dart`
- Create: `frontend/lib/features/auth/activate_screen.dart`
- Modify: `frontend/lib/core/routes.dart`

**Interfaces:**
- Consumes: `AuthApi.activate` (Task 2); `TokenResponse`, `UserModel.isSuperAdmin` (`lib/core/models/user.dart`); `AppRoutes.universities`, `AppRoutes.dashboard`.
- Produces:
  - `AuthController.applyToken(TokenResponse result) -> Future<void>` — stores the token, sets `user`, and navigates (super-admin → universities, else dashboard). Consumed here and reused by login. Task 5 also relies on it.
  - `AppRoutes.activate = '/activate'` GetPage.

- [ ] **Step 1: Extract `applyToken` and reuse it in `login`**

In `frontend/lib/core/controllers/auth_controller.dart`, the current `login` method (lines 41–57) reads:

```dart
  Future<void> login(String email, String password) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final result = await AuthApi(ApiClient()).login(email, password);
      _token = result.accessToken;
      await _storage.write(key: _tokenKey, value: _token);
      user.value = result.user;
      Get.offAllNamed(
        result.user.isSuperAdmin ? AppRoutes.universities : AppRoutes.dashboard,
      );
    } on Exception catch (e) {
      errorMessage.value = _extractMessage(e);
    } finally {
      isLoading.value = false;
    }
  }
```

Replace it with a version that delegates session-establishment to a new public `applyToken` method:

```dart
  Future<void> login(String email, String password) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final result = await AuthApi(ApiClient()).login(email, password);
      await applyToken(result);
    } on Exception catch (e) {
      errorMessage.value = _extractMessage(e);
    } finally {
      isLoading.value = false;
    }
  }

  /// Stores a successful token/user (from login or activation), persists the
  /// token, and routes to the landing screen for the user's role.
  Future<void> applyToken(TokenResponse result) async {
    _token = result.accessToken;
    await _storage.write(key: _tokenKey, value: _token);
    user.value = result.user;
    Get.offAllNamed(
      result.user.isSuperAdmin ? AppRoutes.universities : AppRoutes.dashboard,
    );
  }
```

Add the `TokenResponse` import at the top of the file if not already present — `user.dart` is already imported (`import '../models/user.dart';`), and `TokenResponse` lives in that file, so no new import is needed.

- [ ] **Step 2: Create the activation screen**

Create `frontend/lib/features/auth/activate_screen.dart`:

```dart
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
      final detail = (e.response?.data as Map?)?['detail'] as String?;
      setState(() {
        _error = detail ??
            'Could not activate. The link may be invalid or expired.';
        _submitting = false;
      });
    } catch (_) {
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
```

- [ ] **Step 3: Register the route**

In `frontend/lib/core/routes.dart`:

Add the import near the other feature imports (after the `login_screen.dart` import at line 4):

```dart
import '../features/auth/activate_screen.dart';
```

Add the route name constant inside `AppRoutes` (after `static const login = '/login';`):

```dart
  static const activate = '/activate';
```

Add the GetPage to the `pages` list (after the `login` GetPage at line 34):

```dart
    GetPage(name: activate, page: () => const ActivateScreen()),
```

- [ ] **Step 4: Verify analyze is clean**

Run: `cd frontend && flutter analyze`
Expected: No issues found!

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/core/controllers/auth_controller.dart frontend/lib/features/auth/activate_screen.dart frontend/lib/core/routes.dart
git commit -m "frontend: activation page with auto-login on the /activate route"
```

---

## Task 4: Email-confirmation route

**Files:**
- Create: `frontend/lib/features/auth/confirm_email_screen.dart`
- Modify: `frontend/lib/core/routes.dart`

**Interfaces:**
- Consumes: `AuthApi.confirmEmail` (Task 2); `AppRoutes.login`.
- Produces: `AppRoutes.confirmEmail = '/confirm-email'` GetPage.

- [ ] **Step 1: Create the confirm-email screen**

Create `frontend/lib/features/auth/confirm_email_screen.dart`:

```dart
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
```

- [ ] **Step 2: Register the route**

In `frontend/lib/core/routes.dart`:

Add the import (after the `activate_screen.dart` import from Task 3):

```dart
import '../features/auth/confirm_email_screen.dart';
```

Add the route name constant (after `static const activate = '/activate';`):

```dart
  static const confirmEmail = '/confirm-email';
```

Add the GetPage (after the `activate` GetPage):

```dart
    GetPage(name: confirmEmail, page: () => const ConfirmEmailScreen()),
```

- [ ] **Step 3: Verify analyze is clean**

Run: `cd frontend && flutter analyze`
Expected: No issues found!

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/features/auth/confirm_email_screen.dart frontend/lib/core/routes.dart
git commit -m "frontend: email-change confirmation page on the /confirm-email route"
```

---

## Task 5: Login — resend-activation affordance on the 403

**Files:**
- Modify: `frontend/lib/core/controllers/auth_controller.dart`
- Modify: `frontend/lib/features/auth/login_screen.dart`

**Interfaces:**
- Consumes: `AuthApi.resendActivation` (Task 2); `DioException` (`package:dio/dio.dart`).
- Produces:
  - `AuthController.needsActivation` (`RxBool`) — true after a not-verified login.
  - `AuthController.resendActivation() -> Future<void>` — resends to the last-attempted email and shows a generic snackbar.

- [ ] **Step 1: Add 403 detection + resend to the controller**

In `frontend/lib/core/controllers/auth_controller.dart`:

Add the Dio import at the top (after the existing package imports):

```dart
import 'package:dio/dio.dart';
```

Add these observable/state fields inside the class (after `final RxString errorMessage = ''.obs;`):

```dart
  /// True when the last login attempt failed because the email is unverified,
  /// so the UI can offer a "resend activation" action.
  final RxBool needsActivation = false.obs;
  String _lastLoginEmail = '';
```

Replace the `login` method (the version produced in Task 3) with one that clears `needsActivation`, remembers the email, and detects the 403:

```dart
  Future<void> login(String email, String password) async {
    isLoading.value = true;
    errorMessage.value = '';
    needsActivation.value = false;
    _lastLoginEmail = email;
    try {
      final result = await AuthApi(ApiClient()).login(email, password);
      await applyToken(result);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final detail = (e.response?.data as Map?)?['detail'] as String?;
      if (code == 403) {
        needsActivation.value = true;
        errorMessage.value = detail ??
            'Email not verified. Check your inbox or request a new activation link.';
      } else if (code == 401) {
        errorMessage.value = 'Invalid email or password.';
      } else {
        errorMessage.value = detail ?? 'An error occurred. Please try again.';
      }
    } catch (_) {
      errorMessage.value = 'Cannot reach server. Check your connection.';
    } finally {
      isLoading.value = false;
    }
  }

  /// Resends the activation email to the last email a login was attempted with.
  /// Always shows a generic message — never reveals whether the account exists.
  Future<void> resendActivation() async {
    if (_lastLoginEmail.isEmpty) return;
    try {
      await AuthApi(ApiClient()).resendActivation(_lastLoginEmail);
    } catch (_) {
      // Ignore — the generic message below must not leak backend state.
    }
    Get.snackbar(
      'Check your inbox',
      "If that account exists, we've sent a new activation link.",
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
    );
  }
```

The old `_extractMessage` helper (lines 68–77) is now unused. Delete it:

```dart
  String _extractMessage(Exception e) {
    final msg = e.toString();
    if (msg.contains('401') || msg.contains('Unauthorized')) {
      return 'Invalid email or password.';
    }
    if (msg.contains('SocketException') || msg.contains('connection')) {
      return 'Cannot reach server. Check your connection.';
    }
    return 'An error occurred. Please try again.';
  }
```

- [ ] **Step 2: Add the resend affordance to the login form**

In `frontend/lib/features/auth/login_screen.dart`, find the error-message `Obx` block (lines 101–112) and add a second `Obx` immediately after its closing `}),` (before the `const SizedBox(height: 8),` that precedes the sign-in button):

```dart
                      Obx(() {
                        if (!AuthController.to.needsActivation.value) {
                          return const SizedBox.shrink();
                        }
                        return Align(
                          child: TextButton.icon(
                            icon: const Icon(Icons.mark_email_read_outlined,
                                size: 18),
                            label: const Text('Resend activation email'),
                            onPressed: () =>
                                AuthController.to.resendActivation(),
                          ),
                        );
                      }),
```

- [ ] **Step 3: Verify analyze is clean**

Run: `cd frontend && flutter analyze`
Expected: No issues found!

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/core/controllers/auth_controller.dart frontend/lib/features/auth/login_screen.dart
git commit -m "frontend login: detect the unverified-email 403 and offer to resend the activation email"
```

---

## Task 6: Create-user form — remove the password field

**Files:**
- Modify: `frontend/lib/features/management/management_screen.dart`

**Interfaces:**
- Consumes: `UserApi.createUser(Map)` (unchanged; the backend `UserCreate` schema no longer accepts `password`).

- [ ] **Step 1: Remove the password controller**

In `frontend/lib/features/management/management_screen.dart`, in `_showAddSheet` (around line 486), delete the password controller declaration:

```dart
    final passCtrl = TextEditingController();
```

- [ ] **Step 2: Replace the password field with an invite note**

Replace the password `TextField` and its trailing spacer (lines 523–527):

```dart
                const SizedBox(height: 12),
                TextField(controller: passCtrl,
                    decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                    obscureText: true),
                const SizedBox(height: 12),
```

with an informational note (no password input):

```dart
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Theme.of(ctx).colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.mark_email_read_outlined,
                          size: 18, color: Theme.of(ctx).colorScheme.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'An activation invite will be emailed to this address. '
                          'The user sets their own password from the link.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
```

- [ ] **Step 3: Drop `password` from the create payload**

In the same method, in the payload map (lines 579–584), remove the password line so it reads:

```dart
                    final payload = <String, dynamic>{
                      'full_name': nameCtrl.text.trim(),
                      'email': emailCtrl.text.trim(),
                      'role': selectedRole,
                    };
```

- [ ] **Step 4: Verify analyze is clean**

Run: `cd frontend && flutter analyze`
Expected: No issues found! (In particular, no "unused" `passCtrl` warning — confirming every reference is gone.)

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/features/management/management_screen.dart
git commit -m "frontend: create-user form emails an activation invite instead of taking a password"
```

---

## Task 7: University-creation form — invite the admin, show the bootstrap link

**Files:**
- Modify: `frontend/lib/features/universities/universities_screen.dart`

**Interfaces:**
- Consumes: `UniversityApi.createUniversityWithAdmin(Map) -> Future<Map<String,dynamic>>` (unchanged); the response now carries `admin_activation_link` and no longer needs `admin_password` sent.

- [ ] **Step 1: Add the clipboard import**

At the top of `frontend/lib/features/universities/universities_screen.dart`, add (after the existing `package:flutter/material.dart` import):

```dart
import 'package:flutter/services.dart';
```

- [ ] **Step 2: Remove the admin-password controller and obscure flag**

In `_showAddDialog` (around lines 43–52), delete these two lines:

```dart
    final adminPasswordCtrl = TextEditingController();
```

```dart
    bool obscure = true;
```

- [ ] **Step 3: Replace the admin-password field with an invite note**

Replace the "Admin Account" helper text and the password `TextFormField` (lines 115–153):

```dart
                    Text(
                      'The university admin will use these credentials to log in.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.outline),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: adminNameCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Admin Full Name'),
                      validator: (v) =>
                          v?.trim().isEmpty == true ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: adminEmailCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Admin Email'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) =>
                          v?.trim().isEmpty == true ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: adminPasswordCtrl,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: 'Admin Password',
                        suffixIcon: IconButton(
                          icon: Icon(obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setS(() => obscure = !obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'At least 6 characters'
                          : null,
                    ),
```

with a version that drops the password input and explains the invite:

```dart
                    Text(
                      'The admin is emailed an activation link to set their own '
                      'password. No password is created here.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.outline),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: adminNameCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Admin Full Name'),
                      validator: (v) =>
                          v?.trim().isEmpty == true ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: adminEmailCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Admin Email'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) =>
                          v?.trim().isEmpty == true ? 'Required' : null,
                    ),
```

- [ ] **Step 4: Drop `admin_password` from the request and update the confirmation call**

Replace the create call block (lines 177–189):

```dart
    if (confirmed != true) return;
    try {
      createdResult = await _api.createUniversityWithAdmin({
        'name': nameCtrl.text.trim(),
        'slug': slugCtrl.text.trim(),
        'overflow_threshold': double.parse(thresholdCtrl.text.trim()),
        'admin_full_name': adminNameCtrl.text.trim(),
        'admin_email': adminEmailCtrl.text.trim(),
        'admin_password': adminPasswordCtrl.text.trim(),
      });
      await _load();
      if (mounted) {
        await _showCreatedConfirmation(createdResult, adminPasswordCtrl.text.trim());
      }
    } catch (e) {
```

with:

```dart
    if (confirmed != true) return;
    try {
      createdResult = await _api.createUniversityWithAdmin({
        'name': nameCtrl.text.trim(),
        'slug': slugCtrl.text.trim(),
        'overflow_threshold': double.parse(thresholdCtrl.text.trim()),
        'admin_full_name': adminNameCtrl.text.trim(),
        'admin_email': adminEmailCtrl.text.trim(),
      });
      await _load();
      if (mounted) {
        await _showCreatedConfirmation(createdResult);
      }
    } catch (e) {
```

- [ ] **Step 5: Rewrite `_showCreatedConfirmation` to show the activation link**

Replace the whole `_showCreatedConfirmation` method (lines 198–258):

```dart
  Future<void> _showCreatedConfirmation(Map<String, dynamic>? result, String password) async {
    if (result == null) return;
    final email = result['admin_email'] as String;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle,
                color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('University Created'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share these login details with the university admin:',
                style: Theme.of(ctx).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Theme.of(ctx).colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Email: $email',
                      style: const TextStyle(fontFamily: 'monospace')),
                  const SizedBox(height: 4),
                  Text('Password: $password',
                      style: const TextStyle(fontFamily: 'monospace')),
                  const SizedBox(height: 4),
                  Text('University: ${result['name']}'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'The admin can change their password after logging in.',
              style: Theme.of(ctx)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(ctx).colorScheme.outline),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
```

with a version that confirms the invitation was emailed and surfaces the bootstrap activation link with a copy button:

```dart
  Future<void> _showCreatedConfirmation(Map<String, dynamic>? result) async {
    if (result == null) return;
    final email = result['admin_email'] as String;
    final link = result['admin_activation_link'] as String? ?? '';
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle,
                color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('University Created'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('An activation invite has been emailed to the admin:',
                style: Theme.of(ctx).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Theme.of(ctx).colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Email: $email',
                      style: const TextStyle(fontFamily: 'monospace')),
                  const SizedBox(height: 4),
                  Text('University: ${result['name']}'),
                ],
              ),
            ),
            if (link.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'If email delivery is not configured yet, share this activation '
                'link with the admin directly:',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.outline),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      link,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    tooltip: 'Copy activation link',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                            content: Text('Activation link copied'),
                            duration: Duration(seconds: 1)),
                      );
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 6: Verify analyze is clean**

Run: `cd frontend && flutter analyze`
Expected: No issues found! (No unused `adminPasswordCtrl`/`obscure`, and `_showCreatedConfirmation` now takes one argument at its single call site.)

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/features/universities/universities_screen.dart
git commit -m "frontend: university creation invites the admin by email and surfaces the bootstrap activation link"
```

---

## Task 8: My Account — change-email confirmation flow

**Files:**
- Modify: `frontend/lib/core/api/auth_api.dart`
- Modify: `frontend/lib/core/widgets/app_shell.dart`

**Interfaces:**
- Changes: `AuthApi.changeEmail(String email)` return type from `Future<UserModel>` to `Future<String>` (the pending address). This is a breaking signature change; its only caller (`app_shell.dart`) is updated in the same task so the tree stays analyze-clean.

- [ ] **Step 1: Change `changeEmail` to return the pending address**

In `frontend/lib/core/api/auth_api.dart`, replace the current `changeEmail` method (lines 28–33):

```dart
  /// Updates the current user's email and returns the refreshed account.
  Future<UserModel> changeEmail(String email) async {
    final response =
        await _client.post('/auth/change-email', data: {'email': email});
    return UserModel.fromJson(response.data as Map<String, dynamic>);
  }
```

with:

```dart
  /// Requests an email change. The backend emails a confirmation link to the
  /// new address and does NOT switch the account email until it is confirmed.
  /// Returns the pending (new) address for display.
  Future<String> changeEmail(String email) async {
    final response =
        await _client.post('/auth/change-email', data: {'email': email});
    return (response.data as Map<String, dynamic>)['pending_email'] as String;
  }
```

Note: `UserModel` may now be an unused import in `auth_api.dart` if nothing else references it — leave the import in place only if `TokenResponse`/`UserModel` are still used (they are: `getMe` returns `UserModel`, `login` returns `TokenResponse`). No import change needed.

- [ ] **Step 2: Update the My Account save handler**

In `frontend/lib/core/widgets/app_shell.dart`, replace the email-save `onPressed` body (lines 613–640):

```dart
                : () async {
                    setS(() => saving = true);
                    try {
                      final updated =
                          await AuthApi(ApiClient(token: AuthController.to.token))
                              .changeEmail(emailCtrl.text.trim());
                      AuthController.to.user.value = updated;
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        Get.snackbar('Email updated', '',
                            snackPosition: SnackPosition.BOTTOM,
                            duration: const Duration(seconds: 2));
                      }
                    } on DioException catch (e) {
                      final detail = (e.response?.data as Map?)?['detail']
                              as String? ??
                          'Failed to update email';
                      setS(() {
                        errorMsg = detail;
                        saving = false;
                      });
                    } catch (e) {
                      setS(() {
                        errorMsg = e.toString();
                        saving = false;
                      });
                    }
                  },
```

with a version that shows the pending-confirmation message and does NOT mutate the current user email:

```dart
                : () async {
                    setS(() => saving = true);
                    try {
                      final pending =
                          await AuthApi(ApiClient(token: AuthController.to.token))
                              .changeEmail(emailCtrl.text.trim());
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        Get.snackbar(
                          'Confirm your new email',
                          "We've sent a confirmation link to $pending. "
                          'Your email changes once you confirm.',
                          snackPosition: SnackPosition.BOTTOM,
                          duration: const Duration(seconds: 4),
                        );
                      }
                    } on DioException catch (e) {
                      final detail = (e.response?.data as Map?)?['detail']
                              as String? ??
                          'Failed to request email change';
                      setS(() {
                        errorMsg = detail;
                        saving = false;
                      });
                    } catch (e) {
                      setS(() {
                        errorMsg = e.toString();
                        saving = false;
                      });
                    }
                  },
```

- [ ] **Step 3: Relabel the Save button**

In the same `AlertDialog`, change the email-save button's label from `'Save'` to `'Send confirmation'`. The button's `child` (lines 641–648) ends with:

```dart
                : const Text('Save'),
```

Change it to:

```dart
                : const Text('Send confirmation'),
```

- [ ] **Step 4: Verify analyze is clean**

Run: `cd frontend && flutter analyze`
Expected: No issues found!

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/core/api/auth_api.dart frontend/lib/core/widgets/app_shell.dart
git commit -m "frontend: change-email sends a confirmation link instead of swapping the address immediately"
```

---

## Task 9: Bulk-import — invitations, not passwords

**Files:**
- Modify: `frontend/lib/features/bulk_import/bulk_import_screen.dart`

**Interfaces:**
- Consumes: `POST /users/bulk-import/` result — created items are now `{name, email}` and skipped items `{email, reason}`; the preview created items are `{name, email, faculty, department}`. Neither carries `temp_password` or `will_generate_password` any longer.

- [ ] **Step 1: Update the CSV-format instructions**

In the instructions card, remove the password column row and update the sample + note. Replace lines 116–146:

```dart
                      const _CsvFormatRow('name', 'Lecturer full name', required: true),
                      const _CsvFormatRow('email', 'Login email (must be unique)', required: true),
                      const _CsvFormatRow('faculty', 'Faculty name', required: true),
                      const _CsvFormatRow('department', 'Department name', required: true),
                      const _CsvFormatRow('password', 'Initial password (auto-generated if blank)', required: false),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Text(
                          'name,email,faculty,department,password\n'
                          'John Doe,jdoe@ub.cm,Faculty of Engineering and Technology,Computer Engineering,\n'
                          'Jane Smith,jsmith@ub.cm,Faculty of Engineering and Technology,Electrical Engineering,Start123',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Lecturers are imported into your university. Faculty and '
                        'department are matched by name (case-insensitive). Leave '
                        'the password blank to have one generated and shown once below.',
                        style: TextStyle(fontSize: 12, color: cs.outline),
                      ),
```

with:

```dart
                      const _CsvFormatRow('name', 'Lecturer full name', required: true),
                      const _CsvFormatRow('email', 'Login email (must be unique)', required: true),
                      const _CsvFormatRow('faculty', 'Faculty name', required: true),
                      const _CsvFormatRow('department', 'Department name', required: true),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Text(
                          'name,email,faculty,department\n'
                          'John Doe,jdoe@ub.cm,Faculty of Engineering and Technology,Computer Engineering\n'
                          'Jane Smith,jsmith@ub.cm,Faculty of Engineering and Technology,Electrical Engineering',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Lecturers are imported into your university. Faculty and '
                        'department are matched by name (case-insensitive). Each '
                        'lecturer is emailed an activation invite to set their own '
                        'password.',
                        style: TextStyle(fontSize: 12, color: cs.outline),
                      ),
```

- [ ] **Step 2: Drop the "password auto / from file" badge from the preview**

In the dry-run preview, replace the created-row builder (lines 282–313):

```dart
                        ...(_preview!['created'] as List? ?? []).map((item) {
                          final m = item as Map<String, dynamic>;
                          final willGen = m['will_generate_password'] == true;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(Icons.person_add_alt,
                                    size: 16, color: cs.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(m['name'] as String? ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13)),
                                      Text(
                                          '${m['email']}  ·  ${m['faculty']} / ${m['department']}',
                                          style: TextStyle(
                                              fontSize: 11, color: cs.outline)),
                                    ],
                                  ),
                                ),
                                Text(willGen ? 'password auto' : 'from file',
                                    style: TextStyle(
                                        fontSize: 10, color: cs.outline)),
                              ],
                            ),
                          );
                        }),
```

with a version that drops the password badge:

```dart
                        ...(_preview!['created'] as List? ?? []).map((item) {
                          final m = item as Map<String, dynamic>;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(Icons.person_add_alt,
                                    size: 16, color: cs.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(m['name'] as String? ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13)),
                                      Text(
                                          '${m['email']}  ·  ${m['faculty']} / ${m['department']}',
                                          style: TextStyle(
                                              fontSize: 11, color: cs.outline)),
                                    ],
                                  ),
                                ),
                                const Text('will invite',
                                    style: TextStyle(fontSize: 10)),
                              ],
                            ),
                          );
                        }),
```

- [ ] **Step 3: Replace the results block — invitations, not passwords**

Replace the entire committed-results block (lines 368–476, from `if (_result != null) ...[` through its closing `],`):

```dart
              // Results
              if (_result != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer.withAlpha(60),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.error.withAlpha(80)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_outlined,
                          color: Theme.of(context).colorScheme.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Save these passwords now — they will not be shown again.',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Created ${(_result!['created'] as List?)?.length ?? 0} accounts  ·  '
                  'Skipped ${(_result!['skipped'] as List?)?.length ?? 0}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline),
                ),
                const SizedBox(height: 12),
                ...(_result!['created'] as List? ?? []).map((item) {
                  final m = item as Map<String, dynamic>;
                  final tempPassword = m['temp_password'] as String?;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m['name'] as String? ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                Text(m['email'] as String? ?? '',
                                    style: TextStyle(
                                        color: Theme.of(context).colorScheme.outline,
                                        fontSize: 12)),
                                if (tempPassword != null) ...[
                                  const SizedBox(height: 4),
                                  SelectableText(
                                    tempPassword,
                                    style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                        color: Theme.of(context).colorScheme.primary,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ] else
                                  Text('password set from file',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context).colorScheme.outline)),
                              ],
                            ),
                          ),
                          if (tempPassword != null)
                            IconButton(
                              icon: const Icon(Icons.copy_outlined, size: 18),
                              tooltip: 'Copy password',
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: tempPassword));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Password copied'),
                                      duration: Duration(seconds: 1)),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  );
                }),
                if ((_result!['skipped'] as List?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  Text('Skipped:',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.outline)),
                  const SizedBox(height: 8),
                  ...(_result!['skipped'] as List).map((item) {
                    final m = item as Map<String, dynamic>;
                    return Text('• ${m['email']} — ${m['reason']}',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                            fontSize: 12));
                  }),
                ],
              ],
```

with an invitation-oriented results block:

```dart
              // Results
              if (_result != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withAlpha(80),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withAlpha(80)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.mark_email_read_outlined,
                          color: Theme.of(context).colorScheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Invitations sent to ${(_result!['created'] as List?)?.length ?? 0} '
                          'lecturer${((_result!['created'] as List?)?.length ?? 0) == 1 ? '' : 's'}. '
                          'Each sets their own password from the emailed link.',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Invited ${(_result!['created'] as List?)?.length ?? 0}  ·  '
                  'Skipped ${(_result!['skipped'] as List?)?.length ?? 0}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline),
                ),
                const SizedBox(height: 12),
                ...(_result!['created'] as List? ?? []).map((item) {
                  final m = item as Map<String, dynamic>;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(Icons.person_add_alt,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m['name'] as String? ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                Text(m['email'] as String? ?? '',
                                    style: TextStyle(
                                        color: Theme.of(context).colorScheme.outline,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          Text('invited',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.outline)),
                        ],
                      ),
                    ),
                  );
                }),
                if ((_result!['skipped'] as List?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  Text('Skipped:',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.outline)),
                  const SizedBox(height: 8),
                  ...(_result!['skipped'] as List).map((item) {
                    final m = item as Map<String, dynamic>;
                    return Text('• ${m['email']} — ${m['reason']}',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                            fontSize: 12));
                  }),
                ],
              ],
```

- [ ] **Step 4: Verify analyze is clean**

Run: `cd frontend && flutter analyze`
Expected: No issues found! (The `Clipboard`/`services.dart` import may now be unused in this file — if analyze flags it, remove the `import 'package:flutter/services.dart';` line from `bulk_import_screen.dart`. Note `Uint8List` comes from `services.dart` too, so keep the import if the file still references `Uint8List`/`MultipartFile.fromBytes` — it does, via `_fileBytes` of type `Uint8List`. Leave the import in place.)

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/features/bulk_import/bulk_import_screen.dart
git commit -m "frontend bulk import: report invitations sent instead of showing passwords"
```

---

## Task 10: End-to-end verification & memory update

**Files:**
- Modify: `C:\Users\Bradford Nfor\.claude\projects\C--Users-Bradford-Nfor-OneDrive-Desktop-my-projects-final-year-project\memory\project_progress.md`

**Interfaces:** none (verification + docs).

- [ ] **Step 1: Start the backend with the console email backend**

Run (in one terminal): `cd backend && python -m uvicorn app.main:app --reload`
The console `EmailSender` is selected automatically when no `smtp_host` is set, so every activation/confirmation email — including its link — is printed to this terminal's logs.

- [ ] **Step 2: Serve the Flutter web app on port 8080**

Run (in another terminal): `cd frontend && flutter run -d chrome --web-port 8080`
Port 8080 matches the backend default `app_base_url` (`http://localhost:8080`), so the printed links open this running app.

- [ ] **Step 3: Verify the activation flow**

1. As a university admin, open Management → Add User, create a user with an email you control. Confirm the form has **no password field** and shows the invite note.
2. In the backend terminal, find the logged activation email and copy the `http://localhost:8080/#/activate?token=…` link.
3. Open that link in the browser. Confirm the activation page loads, set a password (≥6, matching confirm), submit.
4. Confirm you are **auto-logged-in** and land on the dashboard (or universities for a super-admin).

Expected: activation succeeds and routes into the app without a manual login.

- [ ] **Step 4: Verify the login resend affordance**

1. Create another pending user but do NOT activate.
2. Log out, then try to log in as that user. Confirm the error shows the not-verified message and a **"Resend activation email"** button appears.
3. Click it; confirm the generic "If that account exists…" snackbar shows and a fresh link is logged in the backend terminal.

- [ ] **Step 5: Verify the change-email confirmation flow**

1. Logged in as any user, open My Account, enter a new email, click **Send confirmation**.
2. Confirm the snackbar says a confirmation link was sent to the new address, and the displayed account email is **unchanged**.
3. Copy the `…/#/confirm-email?token=…` link from the backend terminal and open it. Confirm the confirmation page shows success.
4. Re-open My Account (or re-login) and confirm the email is now the new address.

- [ ] **Step 6: Verify university creation + bulk import**

1. As super-admin, create a university. Confirm the form has **no admin password**, and the success dialog shows the emailed-invite confirmation plus a copyable activation link (bootstrap fallback). Open that link and activate the admin.
2. As a university admin/faculty head, bulk-import a small lecturer CSV (`name,email,faculty,department`). Confirm the preview shows "will invite" (no password badge) and the committed result reads **"Invitations sent to N lecturers"** with no passwords anywhere.

- [ ] **Step 7: Update the project-progress memory**

Edit `memory/project_progress.md`: in the email-verification bullet, change "**Phase D (Flutter frontend) is PENDING**" to note Phase D is **COMPLETE** (activation + confirm-email pages, login resend, password fields dropped from create-user/university forms, bulk-import invitation UX, change-email confirmation, hash-routing links). Keep the wording plain.

- [ ] **Step 8: Commit any docs/memory changes**

```bash
git add docs/superpowers/plans/2026-08-05-email-verification-frontend.md
git commit -m "email verification: Phase D frontend implementation plan"
```

(The memory directory lives outside the repo and is not committed.)

---

## Self-Review

**Spec coverage** (against `docs/superpowers/specs/2026-08-02-email-verification-design.md`, Frontend section):
- Unauthenticated `/activate` route + set-password + auto-login → Task 3. ✓
- Unauthenticated `/confirm-email` route → Task 4. ✓
- Hash-routing link format (locked decision) → Task 1 (backend) + Tasks 3/4 (routes read `Get.parameters['token']`). ✓
- API layer: `activate`, `confirmEmail`, `resendActivation`, `changeEmail` return change → Task 2 + Task 8. ✓
- Login not-verified 403 → resend action → Task 5. ✓
- Create-user form drops password → Task 6. ✓
- University-creation drops admin password, shows `admin_activation_link` with copy → Task 7. ✓
- Bulk-import "invitations sent", no passwords → Task 9. ✓
- My Account change-email "we've sent a confirmation link…" → Task 8. ✓
- End-to-end verification with console email backend → Task 10. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to". Every code step shows the exact before/after. ✓

**Type consistency:** `applyToken(TokenResponse)` defined in Task 3, consumed in Tasks 3 & 5. `AuthApi.activate → TokenResponse`, `confirmEmail → void`, `resendActivation → void`, `changeEmail → String` are defined in Tasks 2/8 and consumed by the screens that call them. `needsActivation` (RxBool) and `resendActivation()` defined in Task 5, consumed by login_screen in the same task. Route constants `activate`/`confirmEmail` defined and used within Tasks 3/4. ✓

**Breaking-change ordering:** The only breaking signature change (`changeEmail` return type) is made together with its sole caller in Task 8, so every task leaves the tree `flutter analyze`-clean. ✓
