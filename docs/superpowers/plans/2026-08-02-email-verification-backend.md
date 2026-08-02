# Email Verification & Account Activation — Backend Plan (Phases A–C)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the backend for account activation and email verification: pluggable email delivery, single-use DB-backed tokens, pending-account creation, activation + resend endpoints, login gating on verification, and email-change confirmation.

**Architecture:** New pure/service modules (`app/services/email.py`, `app/services/verification.py`), a `VerificationToken` model + `users.is_verified` column + one Alembic migration, changes to the auth/users/universities routers, and updated test helpers. Email delivery is a `Depends`-injected `EmailSender` so tests capture messages instead of sending them.

**Tech Stack:** Python 3.13, FastAPI, SQLAlchemy 2.0 (typed `Mapped`), Alembic, passlib/bcrypt, python-jose (JWT), pytest + `TestClient`. All email/token primitives are stdlib (`smtplib`, `email.message`, `secrets`, `hashlib`).

**Scope note:** This plan covers Phases A–C (backend). Phase D (Flutter frontend: activation/confirm pages, login resend, form/UX updates) is a separate follow-up plan written after this lands, so its code can be based on the real screens.

## Global Constraints

- Python runs in the venv: `backend/.venv/Scripts/python.exe -m pytest ...` / `-m alembic ...`. Never use bare `python`/`pytest`. Full suite ~3.5 min; baseline before this plan is **159 passing**.
- `EmailSender.send(to, subject, html, text) -> None`. Factory `get_email_sender()` returns `SmtpEmailSender` when `settings.smtp_host` is set, else `ConsoleEmailSender`. Routers depend on it via `Depends(get_email_sender)` so tests override `app.dependency_overrides[get_email_sender]`.
- Tokens: raw is `secrets.token_urlsafe(32)`, embedded only in the link; DB stores `hashlib.sha256(raw.encode()).hexdigest()`. Single-use (row deleted on success). Reissue for a (user_id, purpose) deletes prior tokens of that purpose first. Expiries: activation `settings.activation_token_days` (default 7), email-change `settings.email_change_token_hours` (default 24).
- Links: `{settings.app_base_url}/activate?token={raw}` and `{settings.app_base_url}/confirm-email?token={raw}`.
- `users.is_verified`: model default `False`; migration backfills existing rows to `True`. Login raises `403 "Email not verified. Check your inbox or request a new activation link."` when `not is_verified`. `is_active` stays a separate switch.
- Pending accounts get an unusable password: `get_password_hash(secrets.token_urlsafe(16))`.
- Creation paths must not fail account creation if the email send raises — wrap sends in try/except that logs (except the university bootstrap, which also returns the link).
- Commit messages: plain, no prefix, no `Co-Authored-By`.
- Register every new model in `backend/app/models/__init__.py` so `create_all` (tests) and Alembic see it.

---

## File Structure

- **Create** `backend/app/services/email.py` — `EmailSender` backends, factory, message builders.
- **Create** `backend/app/services/verification.py` — token issue/verify helpers (hashing, expiry, single-use).
- **Create** `backend/app/models/verification.py` — `VerificationToken` model.
- **Modify** `backend/app/models/__init__.py` — register `VerificationToken`.
- **Modify** `backend/app/models/user.py` — add `is_verified`.
- **Modify** `backend/app/config.py` — SMTP + link + expiry settings.
- **Create** `backend/alembic/versions/<rev>_add_email_verification.py` — column + table.
- **Modify** `backend/app/routers/auth.py` — login gating; `/auth/activate`, `/auth/resend-activation`, `/auth/confirm-email`; change-email → confirmation.
- **Modify** `backend/app/routers/users.py` — `create_user` pending + invite; lecturer bulk import pending + invite (drop passwords).
- **Modify** `backend/app/routers/universities.py` — `create_university` pending admin + `admin_activation_link`.
- **Modify** `backend/app/schemas/user.py`, `backend/app/schemas/university.py` — drop passwords, add response field.
- **Modify** `backend/tests/conftest.py` — `is_verified` in fixtures; `activate_user` helper; `make_university` self-activates; `sent_emails`/sender-override fixture.
- **Create** `backend/tests/test_email_sender.py`, `backend/tests/test_verification_tokens.py`, `backend/tests/test_activation.py`, `backend/tests/test_email_change.py`.

---

### Task 1: Email sender abstraction + settings

**Files:**
- Modify: `backend/app/config.py`
- Create: `backend/app/services/email.py`
- Test: `backend/tests/test_email_sender.py`

**Interfaces:**
- Consumes: `app.config.settings`.
- Produces:
  - `class ConsoleEmailSender` / `class SmtpEmailSender`, each `.send(to, subject, html, text) -> None`.
  - `get_email_sender() -> EmailSender` — SMTP if `settings.smtp_host` else console.
  - `build_activation_email(link: str) -> tuple[str, str, str]` → `(subject, html, text)`.
  - `build_email_change_email(link: str) -> tuple[str, str, str]`.

- [ ] **Step 1: Add settings**

In `backend/app/config.py`, add these fields to `Settings` (after `jwt_expire_minutes`):

```python
    # Email delivery (absence of smtp_host selects the console backend)
    smtp_host: str | None = None
    smtp_port: int = 587
    smtp_username: str | None = None
    smtp_password: str | None = None
    smtp_from: str = "no-reply@timetabling.local"
    smtp_use_tls: bool = True
    app_base_url: str = "http://localhost:8080"
    activation_token_days: int = 7
    email_change_token_hours: int = 24
```

- [ ] **Step 2: Write the failing tests**

Create `backend/tests/test_email_sender.py`:

```python
from unittest.mock import MagicMock, patch
from app.services.email import (
    ConsoleEmailSender, SmtpEmailSender, get_email_sender,
    build_activation_email, build_email_change_email,
)
from app.config import settings


def test_build_activation_email_contains_link():
    subject, html, text = build_activation_email("http://x/activate?token=abc")
    assert "activate" in subject.lower()
    assert "http://x/activate?token=abc" in html
    assert "http://x/activate?token=abc" in text


def test_build_email_change_email_contains_link():
    subject, html, text = build_email_change_email("http://x/confirm-email?token=abc")
    assert "http://x/confirm-email?token=abc" in text


def test_console_sender_does_not_raise():
    ConsoleEmailSender().send("a@b.com", "Subject", "<p>hi</p>", "hi")


def test_factory_returns_console_when_no_host(monkeypatch):
    monkeypatch.setattr(settings, "smtp_host", None)
    assert isinstance(get_email_sender(), ConsoleEmailSender)


def test_factory_returns_smtp_when_host_set(monkeypatch):
    monkeypatch.setattr(settings, "smtp_host", "smtp.example.com")
    assert isinstance(get_email_sender(), SmtpEmailSender)


def test_smtp_sender_builds_message_and_sends(monkeypatch):
    monkeypatch.setattr(settings, "smtp_host", "smtp.example.com")
    monkeypatch.setattr(settings, "smtp_username", "u")
    monkeypatch.setattr(settings, "smtp_password", "p")
    fake_smtp = MagicMock()
    cm = MagicMock()
    cm.__enter__.return_value = fake_smtp
    cm.__exit__.return_value = False
    with patch("app.services.email.smtplib.SMTP", return_value=cm) as smtp_ctor:
        SmtpEmailSender().send("to@x.com", "Subj", "<p>h</p>", "h")
    smtp_ctor.assert_called_once_with("smtp.example.com", 587)
    fake_smtp.starttls.assert_called_once()
    fake_smtp.login.assert_called_once_with("u", "p")
    fake_smtp.send_message.assert_called_once()
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd backend && ./.venv/Scripts/python.exe -m pytest tests/test_email_sender.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.services.email'`.

- [ ] **Step 4: Implement**

Create `backend/app/services/email.py`:

```python
import logging
import smtplib
from email.message import EmailMessage
from app.config import settings

logger = logging.getLogger("email")


class ConsoleEmailSender:
    """Dev/test backend: logs the message (including the link) instead of sending."""

    def send(self, to: str, subject: str, html: str, text: str) -> None:
        logger.info("EMAIL (console)\n  to: %s\n  subject: %s\n%s", to, subject, text)


class SmtpEmailSender:
    """Production backend: sends via SMTP using the configured settings."""

    def send(self, to: str, subject: str, html: str, text: str) -> None:
        msg = EmailMessage()
        msg["From"] = settings.smtp_from
        msg["To"] = to
        msg["Subject"] = subject
        msg.set_content(text)
        msg.add_alternative(html, subtype="html")
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port) as server:
            if settings.smtp_use_tls:
                server.starttls()
            if settings.smtp_username:
                server.login(settings.smtp_username, settings.smtp_password)
            server.send_message(msg)


def get_email_sender():
    """FastAPI dependency: real SMTP when configured, console otherwise."""
    if settings.smtp_host:
        return SmtpEmailSender()
    return ConsoleEmailSender()


def build_activation_email(link: str) -> tuple[str, str, str]:
    subject = "Activate your timetabling account"
    text = (
        "Welcome. To activate your account and set your password, open this link:\n"
        f"{link}\n\nThe link expires in 7 days."
    )
    html = (
        "<p>Welcome. To activate your account and set your password, "
        f'click <a href="{link}">this link</a>.</p>'
        "<p>The link expires in 7 days.</p>"
    )
    return subject, html, text


def build_email_change_email(link: str) -> tuple[str, str, str]:
    subject = "Confirm your new email address"
    text = (
        "Confirm this as your new email address by opening this link:\n"
        f"{link}\n\nThe link expires in 24 hours. If you did not request this, ignore it."
    )
    html = (
        "<p>Confirm this as your new email address by clicking "
        f'<a href="{link}">this link</a>.</p>'
        "<p>The link expires in 24 hours. If you did not request this, ignore it.</p>"
    )
    return subject, html, text
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd backend && ./.venv/Scripts/python.exe -m pytest tests/test_email_sender.py -v`
Expected: PASS (6 passed).

- [ ] **Step 6: Commit**

```bash
git add backend/app/config.py backend/app/services/email.py backend/tests/test_email_sender.py
git commit -m "email verification: pluggable email sender (SMTP + console) and settings"
```

---

### Task 2: Verification token model, service, and migration

**Files:**
- Create: `backend/app/models/verification.py`
- Modify: `backend/app/models/__init__.py`
- Modify: `backend/app/models/user.py`
- Create: `backend/app/services/verification.py`
- Create: `backend/alembic/versions/a1b2c3d4e5f6_add_email_verification.py`
- Test: `backend/tests/test_verification_tokens.py`

**Interfaces:**
- Consumes: `Base`, `settings`.
- Produces:
  - `VerificationToken` model (`id, user_id, token_hash, purpose, new_email, expires_at, created_at`).
  - `User.is_verified: bool`.
  - `issue_token(db, user_id: int, purpose: str, ttl: timedelta, new_email: str | None = None) -> str` — deletes prior (user_id, purpose) tokens, inserts a new one, returns the RAW token. Caller flushes/commits.
  - `verify_token(db, raw: str, purpose: str) -> VerificationToken | None` — returns the row if it exists and is unexpired (deletes and returns None if expired); caller applies side effects then `db.delete(row)`.

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_verification_tokens.py`:

```python
from datetime import timedelta
from app.models.verification import VerificationToken
from app.services.verification import issue_token, verify_token, _hash


def test_issue_stores_hash_not_raw(db):
    raw = issue_token(db, user_id=1, purpose="activation", ttl=timedelta(days=7))
    db.commit()
    row = db.query(VerificationToken).filter_by(user_id=1).one()
    assert row.token_hash == _hash(raw)
    assert row.token_hash != raw
    assert row.purpose == "activation"


def test_verify_returns_row_for_valid_token(db):
    raw = issue_token(db, user_id=2, purpose="activation", ttl=timedelta(days=7))
    db.commit()
    row = verify_token(db, raw, "activation")
    assert row is not None and row.user_id == 2


def test_verify_wrong_purpose_returns_none(db):
    raw = issue_token(db, user_id=3, purpose="activation", ttl=timedelta(days=7))
    db.commit()
    assert verify_token(db, raw, "email_change") is None


def test_verify_expired_returns_none_and_deletes(db):
    raw = issue_token(db, user_id=4, purpose="activation", ttl=timedelta(seconds=-1))
    db.commit()
    assert verify_token(db, raw, "activation") is None
    assert db.query(VerificationToken).filter_by(user_id=4).count() == 0


def test_reissue_replaces_prior_token(db):
    first = issue_token(db, user_id=5, purpose="activation", ttl=timedelta(days=7))
    db.commit()
    second = issue_token(db, user_id=5, purpose="activation", ttl=timedelta(days=7))
    db.commit()
    assert db.query(VerificationToken).filter_by(user_id=5, purpose="activation").count() == 1
    assert verify_token(db, first, "activation") is None
    assert verify_token(db, second, "activation") is not None


def test_email_change_carries_new_email(db):
    raw = issue_token(db, user_id=6, purpose="email_change",
                      ttl=timedelta(hours=24), new_email="new@x.com")
    db.commit()
    row = verify_token(db, raw, "email_change")
    assert row.new_email == "new@x.com"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && ./.venv/Scripts/python.exe -m pytest tests/test_verification_tokens.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.models.verification'`.

- [ ] **Step 3: Create the model**

Create `backend/app/models/verification.py`:

```python
from datetime import datetime
from typing import Optional
from sqlalchemy import String, Integer, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class VerificationToken(Base):
    __tablename__ = "verification_tokens"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    token_hash: Mapped[str] = mapped_column(String(64), index=True)
    purpose: Mapped[str] = mapped_column(String(20))  # activation | email_change
    new_email: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
```

- [ ] **Step 4: Register the model and add `is_verified`**

In `backend/app/models/__init__.py`, add after the course import line:

```python
from app.models.verification import VerificationToken
```

In `backend/app/models/user.py`, add to `User` (after `is_active`):

```python
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False)
```

(`Boolean` is already imported in that file.)

- [ ] **Step 5: Create the token service**

Create `backend/app/services/verification.py`:

```python
import hashlib
import secrets
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from app.models.verification import VerificationToken


def _hash(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


def issue_token(db: Session, user_id: int, purpose: str, ttl: timedelta,
                new_email: str | None = None) -> str:
    """Delete any existing token of this purpose for the user, insert a fresh
    one, and return the RAW token (embed it in the emailed link). The DB stores
    only the hash. Caller is responsible for the surrounding commit."""
    db.query(VerificationToken).filter_by(user_id=user_id, purpose=purpose).delete()
    raw = secrets.token_urlsafe(32)
    db.add(VerificationToken(
        user_id=user_id,
        token_hash=_hash(raw),
        purpose=purpose,
        new_email=new_email,
        expires_at=datetime.utcnow() + ttl,
    ))
    db.flush()
    return raw


def verify_token(db: Session, raw: str, purpose: str) -> VerificationToken | None:
    """Return the matching unexpired token row, or None. Expired rows are
    deleted. On success the CALLER applies side effects then deletes the row
    (single-use)."""
    row = (
        db.query(VerificationToken)
        .filter_by(token_hash=_hash(raw), purpose=purpose)
        .first()
    )
    if row is None:
        return None
    if row.expires_at < datetime.utcnow():
        db.delete(row)
        db.flush()
        return None
    return row
```

- [ ] **Step 6: Run the service/model tests**

Run: `cd backend && ./.venv/Scripts/python.exe -m pytest tests/test_verification_tokens.py -v`
Expected: PASS (6 passed). (Tests use `create_all`, so no migration needed for them.)

- [ ] **Step 7: Write the Alembic migration**

Create `backend/alembic/versions/a1b2c3d4e5f6_add_email_verification.py`:

```python
"""add_email_verification

Revision ID: a1b2c3d4e5f6
Revises: b1e7d3a9c042
Create Date: 2026-08-02 00:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = 'b1e7d3a9c042'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # New accounts start unverified; existing accounts are grandfathered verified.
    op.add_column('users', sa.Column(
        'is_verified', sa.Boolean(), nullable=False, server_default=sa.true(),
    ))
    op.alter_column('users', 'is_verified', server_default=sa.false())

    op.create_table(
        'verification_tokens',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('token_hash', sa.String(length=64), nullable=False),
        sa.Column('purpose', sa.String(length=20), nullable=False),
        sa.Column('new_email', sa.String(length=200), nullable=True),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=True),
    )
    op.create_index('ix_verification_tokens_token_hash', 'verification_tokens', ['token_hash'])


def downgrade() -> None:
    op.drop_index('ix_verification_tokens_token_hash', table_name='verification_tokens')
    op.drop_table('verification_tokens')
    op.drop_column('users', 'is_verified')
```

- [ ] **Step 8: Verify the migration is valid (offline SQL render)**

Run: `cd backend && ./.venv/Scripts/python.exe -m alembic upgrade head --sql 2>&1 | tail -20`
Expected: SQL for `ALTER TABLE users ADD COLUMN is_verified` and `CREATE TABLE verification_tokens` renders without error (this validates the script chains from `b1e7d3a9c042` without touching the real DB).

- [ ] **Step 9: Commit**

```bash
git add backend/app/models/verification.py backend/app/models/__init__.py backend/app/models/user.py backend/app/services/verification.py backend/alembic/versions/a1b2c3d4e5f6_add_email_verification.py backend/tests/test_verification_tokens.py
git commit -m "email verification: verification token model, service, and migration"
```

---

### Task 3: Login gating + test-helper updates

**Files:**
- Modify: `backend/app/routers/auth.py`
- Modify: `backend/tests/conftest.py`
- Test: existing suite must stay green; add gating tests to `backend/tests/test_auth.py`.

**Interfaces:**
- Consumes: `User.is_verified`.
- Produces:
  - Login rejects unverified accounts with 403 and the exact message.
  - `conftest.activate_user(email, password="password123")` — sets `is_verified=True` and a known password (via a fresh session).
  - `make_university` self-activates its bundled admin; `admin_user` fixture is created `is_verified=True`.
  - `sent_emails` fixture: overrides `get_email_sender` with a capturing sender, yields the captured list.

- [ ] **Step 1: Write the failing gating test**

Add to `backend/tests/test_auth.py`:

```python
from app.core.security import get_password_hash
from tests.conftest import TestingSessionLocal
from app.models.user import User


def _make_login_user(email, verified):
    dbs = TestingSessionLocal()
    try:
        u = User(email=email, full_name="X", hashed_password=get_password_hash("password123"),
                 role="university_admin", is_active=True, is_verified=verified)
        dbs.add(u)
        dbs.commit()
    finally:
        dbs.close()


def test_login_blocked_when_unverified(client):
    _make_login_user("unverified@test.com", verified=False)
    r = client.post("/auth/login", json={"email": "unverified@test.com", "password": "password123"})
    assert r.status_code == 403
    assert "not verified" in r.json()["detail"].lower()


def test_login_ok_when_verified(client):
    _make_login_user("verified@test.com", verified=True)
    r = client.post("/auth/login", json={"email": "verified@test.com", "password": "password123"})
    assert r.status_code == 200
```

- [ ] **Step 2: Run to verify the unverified test fails**

Run: `cd backend && ./.venv/Scripts/python.exe -m pytest tests/test_auth.py -k "unverified or verified" -v`
Expected: `test_login_blocked_when_unverified` FAILS (currently returns 200, no gating).

- [ ] **Step 3: Add login gating**

In `backend/app/routers/auth.py`, in `login`, after the `is_active` check add:

```python
    if not user.is_verified:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Email not verified. Check your inbox or request a new activation link.",
        )
```

- [ ] **Step 4: Update conftest so the suite stays green**

In `backend/tests/conftest.py`:

Add the `is_verified=True` kwarg to the `admin_user` fixture's `User(...)` construction.

Add these helpers (near `make_university`):

```python
def activate_user(email, password="password123"):
    """Test helper: mark an account verified and give it a known password, so a
    test that created it via the API can then log in."""
    dbs = TestingSessionLocal()
    try:
        u = dbs.query(User).filter(User.email == email).first()
        if u:
            u.is_verified = True
            u.hashed_password = get_password_hash(password)
            dbs.commit()
    finally:
        dbs.close()
```

(`get_password_hash` is already imported in conftest.)

Change `make_university` to activate its bundled admin before returning:

```python
def make_university(client, auth_headers, name="UB", slug="ub"):
    resp = client.post("/universities/", json={
        "name": name,
        "slug": slug,
        "admin_full_name": f"{slug.upper()} Admin",
        "admin_email": f"admin_{slug}@test.com",
        "admin_password": "password123",
    }, headers=auth_headers).json()
    activate_user(f"admin_{slug}@test.com")
    return resp
```

Add the email-capture fixture:

```python
@pytest.fixture
def sent_emails():
    """Capture emails instead of sending. Yields a list of dicts:
    {to, subject, html, text}."""
    from app.services.email import get_email_sender
    box = []

    class _Capture:
        def send(self, to, subject, html, text):
            box.append({"to": to, "subject": subject, "html": html, "text": text})

    app.dependency_overrides[get_email_sender] = lambda: _Capture()
    yield box
    app.dependency_overrides.pop(get_email_sender, None)
```

- [ ] **Step 5: Make the whole suite green**

Run: `cd backend && ./.venv/Scripts/python.exe -m pytest -q 2>&1 | tail -30`

Expected: some tests that create an account via the API and then log in now fail with 403 (not verified). For EACH such failure, add an `activate_user(<that email>)` call after the account is created and before the login in that test (import it: `from tests.conftest import activate_user`). Likely files: `tests/test_users.py`, `tests/test_run_management_permissions.py`, `tests/test_run_visibility.py`, `tests/test_readiness_scoping.py`, and any other test that does `POST /users/` (or a role-specific account) then `POST /auth/login`. Do NOT weaken the gating; fix the tests to activate. Re-run until green (159 + 2 new = 161 target, adjust for any tests you edited).

- [ ] **Step 6: Commit**

```bash
git add backend/app/routers/auth.py backend/tests/conftest.py backend/tests/test_auth.py backend/tests/
git commit -m "email verification: gate login on verified email; update test helpers to activate"
```

---

### Task 4: Activation and resend endpoints

**Files:**
- Modify: `backend/app/routers/auth.py`
- Test: `backend/tests/test_activation.py`

**Interfaces:**
- Consumes: `issue_token`, `verify_token`, `get_email_sender`, `build_activation_email`, `create_access_token`, token settings.
- Produces:
  - `POST /auth/activate` `{token, new_password}` → sets password, `is_verified=True`, `is_active=True`, deletes token, returns `TokenResponse` (auto-login).
  - `POST /auth/resend-activation` `{email}` → reissue+send if account exists and is unverified; always `{"ok": true}`.
  - A reusable helper `send_activation(db, sender, user)` that issues a token, builds the link, and sends the email — used here and by Task 5's creation paths.

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_activation.py`:

```python
import re
from datetime import timedelta
from tests.conftest import TestingSessionLocal
from app.models.user import User
from app.core.security import get_password_hash
from app.services.verification import issue_token
from app.config import settings


def _pending_user(email="pending@test.com"):
    dbs = TestingSessionLocal()
    try:
        u = User(email=email, full_name="Pending", role="university_admin",
                 is_active=True, is_verified=False,
                 hashed_password=get_password_hash("unusable-xyz"))
        dbs.add(u); dbs.commit(); dbs.refresh(u)
        return u.id
    finally:
        dbs.close()


def _token_for(user_id, purpose="activation", ttl=timedelta(days=7), new_email=None):
    dbs = TestingSessionLocal()
    try:
        raw = issue_token(dbs, user_id, purpose, ttl, new_email=new_email)
        dbs.commit()
        return raw
    finally:
        dbs.close()


def test_activate_sets_password_and_verifies_and_logs_in(client):
    uid = _pending_user()
    raw = _token_for(uid)
    r = client.post("/auth/activate", json={"token": raw, "new_password": "mynewpass"})
    assert r.status_code == 200
    assert "access_token" in r.json()
    # can now log in with the chosen password
    login = client.post("/auth/login", json={"email": "pending@test.com", "password": "mynewpass"})
    assert login.status_code == 200


def test_activate_is_single_use(client):
    uid = _pending_user("single@test.com")
    raw = _token_for(uid)
    assert client.post("/auth/activate", json={"token": raw, "new_password": "pw12345"}).status_code == 200
    again = client.post("/auth/activate", json={"token": raw, "new_password": "pw12345"})
    assert again.status_code == 400


def test_activate_rejects_short_password(client):
    uid = _pending_user("short@test.com")
    raw = _token_for(uid)
    r = client.post("/auth/activate", json={"token": raw, "new_password": "123"})
    assert r.status_code == 400


def test_activate_rejects_bad_token(client):
    r = client.post("/auth/activate", json={"token": "nope", "new_password": "pw12345"})
    assert r.status_code == 400


def test_resend_activation_sends_email_for_unverified(client, sent_emails):
    _pending_user("resend@test.com")
    r = client.post("/auth/resend-activation", json={"email": "resend@test.com"})
    assert r.status_code == 200 and r.json()["ok"] is True
    assert any(m["to"] == "resend@test.com" for m in sent_emails)
    # the email carries an activation link with a token
    assert any(re.search(r"/activate\?token=\S+", m["text"]) for m in sent_emails)


def test_resend_activation_generic_for_unknown_email(client, sent_emails):
    r = client.post("/auth/resend-activation", json={"email": "ghost@test.com"})
    assert r.status_code == 200 and r.json()["ok"] is True
    assert sent_emails == []
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd backend && ./.venv/Scripts/python.exe -m pytest tests/test_activation.py -v`
Expected: FAIL — 404 on `/auth/activate` and `/auth/resend-activation`.

- [ ] **Step 3: Implement the endpoints + shared helper**

In `backend/app/routers/auth.py`, add imports at the top:

```python
from datetime import timedelta
from app.config import settings
from app.services.verification import issue_token, verify_token
from app.services.email import (
    get_email_sender, build_activation_email, build_email_change_email,
)
```

Add the shared helper and endpoints:

```python
def send_activation(db: Session, sender, user: User) -> str:
    """Issue an activation token for `user`, email the link, and return the raw
    token. Email failures are logged, not raised, so account creation is robust.
    Returns the raw token so callers (e.g. university bootstrap) can surface the
    link directly."""
    raw = issue_token(db, user.id, "activation",
                      timedelta(days=settings.activation_token_days))
    link = f"{settings.app_base_url}/activate?token={raw}"
    subject, html, text = build_activation_email(link)
    try:
        sender.send(user.email, subject, html, text)
    except Exception:  # pragma: no cover - delivery failures must not strand accounts
        import logging
        logging.getLogger("email").exception("activation email send failed for %s", user.email)
    return raw


class ActivateRequest(BaseModel):
    token: str
    new_password: str


@router.post("/activate", response_model=TokenResponse)
def activate(payload: ActivateRequest, db: Session = Depends(get_db)):
    if len(payload.new_password) < 6:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="New password must be at least 6 characters")
    row = verify_token(db, payload.token, "activation")
    if row is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="This activation link is invalid or has expired. Request a new one.")
    user = db.get(User, row.user_id)
    if user is None:
        db.delete(row); db.commit()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="This activation link is invalid or has expired. Request a new one.")
    user.hashed_password = get_password_hash(payload.new_password)
    user.is_verified = True
    user.is_active = True
    db.delete(row)
    db.commit()
    db.refresh(user)
    token = create_access_token({"sub": str(user.id)})
    return TokenResponse(access_token=token, user=UserOut.model_validate(user))


class ResendActivationRequest(BaseModel):
    email: str


@router.post("/resend-activation")
def resend_activation(payload: ResendActivationRequest, db: Session = Depends(get_db),
                      sender=Depends(get_email_sender)):
    user = db.query(User).filter(User.email == payload.email.strip()).first()
    if user and not user.is_verified:
        send_activation(db, sender, user)
        db.commit()
    # Always generic: do not reveal whether the account exists.
    return {"ok": True}
```

- [ ] **Step 4: Run to verify they pass**

Run: `cd backend && ./.venv/Scripts/python.exe -m pytest tests/test_activation.py -v`
Expected: PASS (6 passed).

- [ ] **Step 5: Commit**

```bash
git add backend/app/routers/auth.py backend/tests/test_activation.py
git commit -m "email verification: activation and resend-activation endpoints"
```

---

### Task 5: Creation paths create pending accounts and send invitations

**Files:**
- Modify: `backend/app/schemas/user.py`, `backend/app/schemas/university.py`
- Modify: `backend/app/routers/users.py`, `backend/app/routers/universities.py`
- Test: `backend/tests/test_activation.py` (new cases), and update existing creation/login tests.

**Interfaces:**
- Consumes: `send_activation` (Task 4), `get_email_sender`, `issue_token`.
- Produces:
  - `UserCreate` no longer has `password`. `create_user` creates a pending account (unusable password) and sends an activation email.
  - `UniversityWithAdminCreate` no longer has `admin_password`. `create_university` creates a pending admin, sends activation, and returns `admin_activation_link` on `UniversityCreateResponse`.
  - Lecturer bulk import creates pending lecturers, sends activation; result entries drop `temp_password`/`will_generate_password`.

- [ ] **Step 1: Write the failing tests**

Add to `backend/tests/test_activation.py`:

```python
from tests.conftest import make_university


def test_create_user_makes_pending_account_and_sends_invite(client, auth_headers, sent_emails):
    uni = make_university(client, auth_headers)
    r = client.post("/users/", json={
        "email": "newofficer@test.com", "full_name": "New Officer",
        "role": "timetable_officer", "university_id": uni["id"],
    }, headers=auth_headers)
    assert r.status_code == 201
    # cannot log in yet (pending)
    assert client.post("/auth/login", json={
        "email": "newofficer@test.com", "password": "whatever"}).status_code in (401, 403)
    # invitation was emailed
    assert any(m["to"] == "newofficer@test.com" for m in sent_emails)


def test_create_university_returns_admin_activation_link(client, auth_headers, sent_emails):
    r = client.post("/universities/", json={
        "name": "New Uni", "slug": "newuni",
        "admin_full_name": "New Admin", "admin_email": "admin_newuni@test.com",
    }, headers=auth_headers)
    assert r.status_code == 201
    assert "/activate?token=" in r.json()["admin_activation_link"]


def test_bulk_import_lecturers_sends_invites_no_passwords(client, auth_headers, sent_emails):
    uni = make_university(client, auth_headers)
    fac = client.post("/faculties/", json={"name": "FET", "code": "FET", "university_id": uni["id"]},
                      headers=auth_headers).json()
    client.post("/departments/", json={"name": "CE", "code": "CE", "faculty_id": fac["id"]},
                headers=auth_headers)
    # log in as the university admin (bulk import is admin-run)
    admin_headers = {"Authorization": "Bearer " + client.post("/auth/login", json={
        "email": "admin_ub@test.com", "password": "password123"}).json()["access_token"]}
    import io
    csv_text = "name,email,faculty,department\nJane Doe,jane@ub.cm,FET,CE\n"
    r = client.post("/users/bulk-import/", params={"dry_run": False},
                    files={"file": ("l.csv", io.BytesIO(csv_text.encode()), "text/csv")},
                    headers=admin_headers)
    assert r.status_code == 200
    created = r.json()["created"]
    assert created and all("temp_password" not in c for c in created)
    assert any(m["to"] == "jane@ub.cm" for m in sent_emails)
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd backend && ./.venv/Scripts/python.exe -m pytest tests/test_activation.py -k "pending or activation_link or invites" -v`
Expected: FAIL — `admin_activation_link` missing / `temp_password` still present / login still possible.

- [ ] **Step 3: Update schemas**

In `backend/app/schemas/user.py`, remove the `password` field from `UserCreate`:

```python
class UserCreate(BaseModel):
    email: EmailStr
    full_name: str
    role: str
    university_id: Optional[int] = None
    department_id: Optional[int] = None
    faculty_id: Optional[int] = None
```

In `backend/app/schemas/university.py`: remove `admin_password` from `UniversityWithAdminCreate`, and add `admin_activation_link: str` to `UniversityCreateResponse`. (Open the file to see exact field lists; keep all other fields.)

- [ ] **Step 4: Update `create_user`**

In `backend/app/routers/users.py`, add imports:

```python
from app.services.email import get_email_sender
from app.routers.auth import send_activation
```

Replace the body of `create_user` that builds/saves the user with pending creation:

```python
    data = payload.model_dump()
    user = User(
        **data,
        hashed_password=get_password_hash(secrets.token_urlsafe(16)),
        is_verified=False,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    send_activation(db, sender, user)
    db.commit()
    return user
```

and add `sender=Depends(get_email_sender)` to the `create_user` signature. (`secrets` is already imported in `users.py`.)

- [ ] **Step 5: Update `create_university`**

In `backend/app/routers/universities.py`, add imports:

```python
from app.services.email import get_email_sender
from app.routers.auth import send_activation
```

Add `sender=Depends(get_email_sender)` to `create_university`. Replace the admin creation + response so the admin is pending and the link is returned:

```python
    admin = User(
        email=payload.admin_email,
        full_name=payload.admin_full_name,
        hashed_password=get_password_hash(secrets.token_urlsafe(16)),
        role="university_admin",
        university_id=university.id,
        is_active=True,
        is_verified=False,
    )
    db.add(admin)
    db.flush()
    db.commit()
    db.refresh(university)
    db.refresh(admin)

    raw = send_activation(db, sender, admin)
    db.commit()
    link = f"{settings.app_base_url}/activate?token={raw}"

    return UniversityCreateResponse(
        id=university.id,
        name=university.name,
        slug=university.slug,
        overflow_threshold=university.overflow_threshold,
        admin_id=admin.id,
        admin_email=admin.email,
        admin_full_name=admin.full_name,
        admin_activation_link=link,
    )
```

Add imports for `secrets` and `settings` at the top of `universities.py` if not present (`import secrets`, `from app.config import settings`).

- [ ] **Step 6: Update lecturer bulk import**

In `backend/app/routers/users.py` `bulk_import_lecturers`: add `sender=Depends(get_email_sender)` to the signature. Remove the `password`/`temp_password`/`will_generate_password` logic. For each created lecturer (non-dry-run), create the user with an unusable password and `is_verified=False`, add the `Lecturer` profile as today, then call `send_activation(db, sender, user)`. The `created` entry becomes `{"name": name, "email": email}` (no password). The dry-run entry drops `will_generate_password`. Keep all the faculty/department matching and skip logic unchanged. Commit once after the loop (before returning) as today.

- [ ] **Step 7: Fix any existing tests broken by dropped passwords**

Run: `cd backend && ./.venv/Scripts/python.exe -m pytest -q 2>&1 | tail -30`
Existing tests that posted `password`/`admin_password` at creation or asserted `temp_password` now fail. Fix them: remove the dropped fields from payloads; for tests that then log in as the created user, either activate via `activate_user(email)` then log in, OR (for lecturer-import assertions) assert on the new no-password shape. Update `test_users.py` and the lecturer bulk-import test accordingly. Re-run until green.

- [ ] **Step 8: Run the targeted + full suite**

Run: `cd backend && ./.venv/Scripts/python.exe -m pytest tests/test_activation.py -v` (all pass), then `./.venv/Scripts/python.exe -m pytest -q` (full suite green).

- [ ] **Step 9: Commit**

```bash
git add backend/app/schemas/user.py backend/app/schemas/university.py backend/app/routers/users.py backend/app/routers/universities.py backend/tests/
git commit -m "email verification: creation paths make pending accounts and email invitations"
```

---

### Task 6: Email-change confirmation

**Files:**
- Modify: `backend/app/routers/auth.py`
- Test: `backend/tests/test_email_change.py`

**Interfaces:**
- Consumes: `issue_token`, `verify_token`, `get_email_sender`, `build_email_change_email`, `email_change_token_hours`.
- Produces:
  - `POST /auth/change-email` (authenticated) now issues an `email_change` token carrying `new_email`, emails a confirm link to the new address, and returns `{"ok": true, "pending_email": <new_email>}` WITHOUT changing the current email.
  - `POST /auth/confirm-email` `{token}` → swaps the email if still free, deletes the token, returns `UserOut`.

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_email_change.py`:

```python
import re
from tests.conftest import make_university


def _admin_headers(client, auth_headers):
    make_university(client, auth_headers)
    tok = client.post("/auth/login", json={
        "email": "admin_ub@test.com", "password": "password123"}).json()["access_token"]
    return {"Authorization": f"Bearer {tok}"}


def _token_from_emails(sent_emails):
    for m in sent_emails:
        match = re.search(r"/confirm-email\?token=(\S+)", m["text"])
        if match:
            return match.group(1)
    return None


def test_change_email_sends_confirmation_and_does_not_swap(client, auth_headers, sent_emails):
    headers = _admin_headers(client, auth_headers)
    r = client.post("/auth/change-email", json={"email": "brandnew@test.com"}, headers=headers)
    assert r.status_code == 200
    assert r.json()["pending_email"] == "brandnew@test.com"
    # confirmation went to the NEW address
    assert any(m["to"] == "brandnew@test.com" for m in sent_emails)
    # current email unchanged
    me = client.get("/auth/me", headers=headers).json()
    assert me["email"] == "admin_ub@test.com"


def test_confirm_email_swaps_address(client, auth_headers, sent_emails):
    headers = _admin_headers(client, auth_headers)
    client.post("/auth/change-email", json={"email": "confirmed@test.com"}, headers=headers)
    token = _token_from_emails(sent_emails)
    assert token
    r = client.post("/auth/confirm-email", json={"token": token})
    assert r.status_code == 200
    assert r.json()["email"] == "confirmed@test.com"


def test_confirm_email_rejects_bad_token(client, auth_headers, sent_emails):
    r = client.post("/auth/confirm-email", json={"token": "nope"})
    assert r.status_code == 400
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd backend && ./.venv/Scripts/python.exe -m pytest tests/test_email_change.py -v`
Expected: FAIL — old change-email swaps immediately (no `pending_email`), `/auth/confirm-email` is 404.

- [ ] **Step 3: Rework change-email and add confirm-email**

In `backend/app/routers/auth.py`, replace the `change_email` endpoint body so it issues a token and emails instead of swapping:

```python
@router.post("/change-email")
def change_email(
    payload: ChangeEmailRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    sender=Depends(get_email_sender),
):
    new_email = payload.email.strip()
    if "@" not in new_email or "." not in new_email or " " in new_email:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="Enter a valid email address")
    clash = db.query(User).filter(User.email == new_email, User.id != current_user.id).first()
    if clash:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="That email address is already in use")
    raw = issue_token(db, current_user.id, "email_change",
                      timedelta(hours=settings.email_change_token_hours), new_email=new_email)
    link = f"{settings.app_base_url}/confirm-email?token={raw}"
    subject, html, text = build_email_change_email(link)
    try:
        sender.send(new_email, subject, html, text)
    except Exception:  # pragma: no cover
        import logging
        logging.getLogger("email").exception("email-change send failed for %s", new_email)
    db.commit()
    return {"ok": True, "pending_email": new_email}


class ConfirmEmailRequest(BaseModel):
    token: str


@router.post("/confirm-email", response_model=UserOut)
def confirm_email(payload: ConfirmEmailRequest, db: Session = Depends(get_db)):
    row = verify_token(db, payload.token, "email_change")
    if row is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="This confirmation link is invalid or has expired. Request a new one.")
    user = db.get(User, row.user_id)
    clash = db.query(User).filter(User.email == row.new_email, User.id != row.user_id).first()
    if user is None or clash:
        db.delete(row); db.commit()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="That email address is no longer available.")
    user.email = row.new_email
    db.delete(row)
    db.commit()
    db.refresh(user)
    return UserOut.model_validate(user)
```

The `change_email` response is no longer `response_model=UserOut` — remove that decorator argument (it now returns a plain dict). Keep `ChangeEmailRequest` where it is.

- [ ] **Step 4: Run to verify they pass**

Run: `cd backend && ./.venv/Scripts/python.exe -m pytest tests/test_email_change.py -v`
Expected: PASS (3 passed).

- [ ] **Step 5: Fix any existing change-email test**

If `test_auth.py` (or similar) asserted the old immediate-swap behavior, update it to the new confirmation flow. Run `./.venv/Scripts/python.exe -m pytest tests/test_auth.py -q` and fix.

- [ ] **Step 6: Full suite + commit**

Run: `cd backend && ./.venv/Scripts/python.exe -m pytest -q` (green).

```bash
git add backend/app/routers/auth.py backend/tests/test_email_change.py backend/tests/
git commit -m "email verification: email-change confirmation flow"
```

---

## Self-Review Notes

- **Spec coverage:** email infra + settings (T1); token table/model/service + migration + `is_verified` (T2); login gating + grandfathering via migration + test-helper ripple (T2 migration backfill, T3); activation + resend (T4); pending creation across `create_user`/`create_university`/bulk import + bootstrap link (T5); email-change confirmation (T6). Testing list in the spec maps onto T1–T6 test files.
- **Deferred to the Phase D frontend plan:** activation/confirm pages, login resend affordance, create-user/university-creation/bulk-import/change-email UI. Called out at the top.
- **Type/name consistency:** `issue_token(db, user_id, purpose, ttl, new_email=None) -> raw`, `verify_token(db, raw, purpose) -> row|None`, `send_activation(db, sender, user) -> raw`, `get_email_sender()` used consistently across tasks. Purposes are the exact strings `"activation"` / `"email_change"`.
- **Known cross-task ripple (intentional):** T3 and T5 both edit existing tests. T3 handles the verification precondition (add `activate_user` calls); T5 handles dropped-password payloads and the bulk-import shape. Each task ends on a green full suite.
