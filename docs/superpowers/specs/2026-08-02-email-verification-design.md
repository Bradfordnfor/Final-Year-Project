# Email Verification & Account Activation — Design

Date: 2026-08-02
Status: Approved (pending spec review)

## Problem

The system has no email verification. Login only checks `is_active`; there is
no proof that a user's email address is real or belongs to them, no
email-sending infrastructure, and accounts are provisioned top-down (admins
create users, university creation bundles a first admin, bulk import mints
lecturer accounts with a generated password shown once). The `change-email`
flow swaps an address with no confirmation. For a product a real university
would run, accounts must be activated by the person who owns the email, users
must set their own passwords (no plaintext passwords handed around), and email
changes must be confirmed.

## Goals

1. **Activation on creation** — admin-created users, the first admin of a new
   university, and bulk-imported lecturers are created *pending* (no password),
   receive an activation email, and set their own password via the link before
   they can log in.
2. **Email-change confirmation** — changing an email sends a confirmation link
   to the new address; the change takes effect only when confirmed.
3. **Deployable anywhere** — email delivery is pluggable: real SMTP in
   production, a console/log backend in dev and tests (no network in tests).

## Decisions locked in brainstorming

- Email delivery: a pluggable `EmailSender` abstraction, SMTP backend for prod,
  console backend for dev + tests.
- Activation owns the password entirely: creation paths make pending accounts
  with no usable password; the activation link sets it. This retires bulk
  import's shown-password UX (becomes "invitations sent to N lecturers").
- The first admin of a new university is created pending + emailed, with a
  bootstrap safety valve (activation link returned in the create response,
  super-admin-only, plus console logging) so a fresh/misconfigured install can
  never lock the first admin out.
- Existing accounts are grandfathered as verified. The system's first
  super-admin stays seeded/pre-verified.
- Token expiries: activation 7 days, email-change 24 hours.
- The existing test suite's create-then-login helpers (notably
  `make_university`) will be updated to complete activation; we do not keep a
  password-at-creation path to spare the tests.

## Phased decomposition

Each phase is independently testable and becomes its own implementation-plan
task group.

- **Phase A — Foundation.** `EmailSender` + backends, settings, the
  `verification_tokens` table, the `users.is_verified` column, one Alembic
  migration, and login gating on `is_verified`.
- **Phase B — Activation.** Creation paths produce pending accounts and send
  activation emails; `POST /auth/activate`; `POST /auth/resend-activation`.
  Update `create_user`, `create_university`, lecturer bulk import, and the
  affected tests/helpers.
- **Phase C — Email-change confirmation.** `change-email` sends a confirm link
  to the new address; `POST /auth/confirm-email`.
- **Phase D — Frontend.** Activation page, confirm page, login resend
  affordance, and the create-user / university-creation / bulk-import /
  change-email UX updates.

## Email infrastructure (`backend/app/services/email.py`)

- `EmailSender` interface: `send(to: str, subject: str, html: str, text: str) -> None`.
- `SmtpEmailSender` — stdlib `smtplib` over TLS, reads SMTP settings.
- `ConsoleEmailSender` — logs recipient, subject, and the link (so dev/tests
  always have the token without a mail server).
- `get_email_sender()` factory: returns `SmtpEmailSender` when `smtp_host` is
  configured, else `ConsoleEmailSender`. Injected into routers as a FastAPI
  dependency so tests can override it if they want to capture messages.
- Message builders: `build_activation_email(link)` and
  `build_email_change_email(link)` produce subject + html + text.

New optional settings in `config.py` (all have safe defaults; absence selects
the console backend):

- `smtp_host: str | None = None`, `smtp_port: int = 587`,
  `smtp_username: str | None = None`, `smtp_password: str | None = None`,
  `smtp_from: str = "no-reply@timetabling.local"`, `smtp_use_tls: bool = True`
- `app_base_url: str = "http://localhost:8080"` — used to build links
  (`{app_base_url}/activate?token=...`, `{app_base_url}/confirm-email?token=...`)
- `activation_token_days: int = 7`, `email_change_token_hours: int = 24`

## Data model

### `users.is_verified`

New boolean column. Model default `False` (new accounts start pending). The
Alembic migration backfills all existing rows to `True`.

### `verification_tokens` table

| column | type | notes |
|---|---|---|
| `id` | int PK | |
| `user_id` | FK users.id | the account being activated / whose email is changing |
| `token_hash` | str, indexed | SHA-256 hex of the raw token; the raw token is never stored |
| `purpose` | str | `activation` or `email_change` |
| `new_email` | str, nullable | for `email_change`: the address to switch to once confirmed |
| `expires_at` | datetime | activation now+7d, email_change now+24h |
| `created_at` | datetime | |

- The raw token is `secrets.token_urlsafe(32)`, embedded only in the emailed
  link. Lookups hash the incoming token and match `token_hash`.
- **Single-use:** the token row is deleted on successful use.
- **Resend/reissue:** issuing a new token for a (user, purpose) deletes any
  existing tokens of that purpose for that user first.
- Expired or unknown tokens yield a 400 with a clear "link expired or invalid;
  request a new one" message.

## Backend flows

### Pending on creation

`create_user` (`POST /users/`), `create_university` (first admin), and the
lecturer bulk import (`POST /users/bulk-import/`) all:

1. create the account with `is_verified=False` and no usable password
   (`hashed_password` set to an unusable sentinel via `get_password_hash` of a
   random secret, so it can never be guessed or used to log in),
2. issue an `activation` token,
3. send the activation email.

Schema/response changes:

- `UserCreate.password` is removed (no longer supplied at creation).
- `UniversityWithAdminCreate.admin_password` is removed. The
  `UniversityCreateResponse` gains `admin_activation_link` (super-admin-only
  bootstrap fallback).
- Lecturer bulk import's result drops `temp_password`/`will_generate_password`;
  the created entries just confirm the invitation was sent. The preview
  (`dry_run`) and the frontend copy change to "invitations."

### `POST /auth/activate`

Body `{ token: str, new_password: str }`.
- Validate token (exists, purpose `activation`, not expired).
- `new_password` min length 6 (matches existing change-password rule).
- Set the password, `is_verified=True`, `is_active=True`; delete the token.
- Return a `TokenResponse` (auto-login), same shape as `/auth/login`.

### `POST /auth/resend-activation`

Body `{ email: str }`.
- If a matching unverified account exists, reissue + send an activation token.
- **Always** return `{ "ok": true }` (generic) so the endpoint cannot be used to
  probe which emails have accounts.

### Login gating

`login` adds: if `not user.is_verified`, raise `403` with detail
`"Email not verified. Check your inbox or request a new activation link."`
(distinct from the existing `"Account inactive"`). `is_active` remains a
separate admin enable/disable switch.

### Email change → confirmation

- `POST /auth/change-email` `{ email }` (authenticated): validates format and
  uniqueness (as today), then instead of swapping, issues an `email_change`
  token carrying `new_email` and emails a confirm link **to the new address**.
  Returns `{ "ok": true, "pending_email": <new_email> }`. The current email is
  unchanged until confirmation.
- `POST /auth/confirm-email` `{ token }`: validates the `email_change` token,
  re-checks the target address is still free, swaps `user.email`, deletes the
  token. Returns the updated `UserOut`.

## Frontend (Phase D)

- **Unauthenticated routes:**
  - `/activate?token=…` → set-password form → on success store the returned
    token and go to the dashboard (auto-login), or route to login.
  - `/confirm-email?token=…` → calls confirm, shows success/failure message.
- **Login screen:** on the not-verified 403, show a "Resend activation email"
  action that calls `/auth/resend-activation`.
- **Create-user form:** remove the password field; note "an activation invite
  will be emailed to this address."
- **University-creation form (super admin):** remove the admin password field;
  after creation, display the returned `admin_activation_link` as the bootstrap
  fallback with a copy button.
- **Bulk-import lecturers screen:** result shows "Invitations sent to N
  lecturers" and the skipped list; no passwords.
- **My Account → change email:** on submit, show "We've sent a confirmation
  link to <new address>. Your email changes once you confirm."

## Migration & test impact

- One Alembic migration: add `users.is_verified` (server_default true so
  existing rows are verified, then the model default governs new rows as false
  in application code), and create `verification_tokens`.
- Tests build schema via `Base.metadata.create_all`, so the model changes
  suffice there — but the login precondition changes. Update:
  - `tests/conftest.py`: add `activate_user(db, email)` (sets `is_verified=True`)
    and make `make_university` mark its bundled admin verified (or run it
    through activation) so downstream logins keep working.
  - Any test that creates a user via the API and then logs in must activate
    first. The activation endpoint tests exercise the real path; other tests use
    the helper shortcut.
  - `admin_user` fixture and seed super-admin are created `is_verified=True`.

## Testing

- **Email backend:** `ConsoleEmailSender` logs; `SmtpEmailSender` builds the
  correct MIME message and calls `smtplib` (verified with a mocked SMTP, no
  network). Factory selects backend by settings.
- **Tokens:** issue → hash stored not raw; single-use (second use fails);
  reissue deletes prior; expired token rejected.
- **Activation:** create pending account (no login possible) → activate sets
  password + verifies → login works; resend reissues; resend for unknown email
  still returns ok; expired/invalid token rejected.
- **Login gating:** unverified → 403 with the distinct message; verified → ok.
- **Email change:** change-email sends to new address and does not swap;
  confirm swaps; confirming a now-taken address fails; expired token rejected.
- **Creation paths:** `create_user`, `create_university`, and lecturer bulk
  import each create pending accounts and send activation (assert via the
  overridden/console sender); `create_university` returns
  `admin_activation_link`; bulk import result carries no passwords.
- Full suite stays green after the helper/test updates.

## Out of scope (v1)

- Password-reset ("forgot password") — a natural follow-up that reuses this
  token infrastructure, but not part of this feature.
- Rate-limiting beyond single-use tokens (resend is not throttled in v1 beyond
  replacing the prior token).
- Public self-signup (accounts remain admin-provisioned).
- HTML email theming beyond a simple, clean template.

## New dependency

None required — `smtplib`, `email.message`, `secrets`, and `hashlib` are all in
the Python standard library.
