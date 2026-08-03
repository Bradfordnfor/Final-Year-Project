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
