def test_login_success(client, admin_user):
    response = client.post("/auth/login", json={
        "email": "admin@test.com",
        "password": "password123",
    })
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["user"]["role"] == "super_admin"


def test_login_wrong_password(client, admin_user):
    response = client.post("/auth/login", json={
        "email": "admin@test.com",
        "password": "wrongpassword",
    })
    assert response.status_code == 401


def test_login_unknown_email(client):
    response = client.post("/auth/login", json={
        "email": "nobody@test.com",
        "password": "password123",
    })
    assert response.status_code == 401


def test_get_me(client, auth_headers, admin_user):
    response = client.get("/auth/me", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["email"] == "admin@test.com"


def test_get_me_no_token(client):
    response = client.get("/auth/me")
    assert response.status_code == 403


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
