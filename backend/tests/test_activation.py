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
    assert any(re.search(r"/#/activate\?token=\S+", m["text"]) for m in sent_emails)


def test_resend_activation_generic_for_unknown_email(client, sent_emails):
    r = client.post("/auth/resend-activation", json={"email": "ghost@test.com"})
    assert r.status_code == 200 and r.json()["ok"] is True
    assert sent_emails == []


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
    assert "/#/activate?token=" in r.json()["admin_activation_link"]


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
