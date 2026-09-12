from tests.conftest import make_university
from app.models.user import User
from app.core.security import get_password_hash


def _login(client, email, password="password123"):
    resp = client.post("/auth/login", json={"email": email, "password": password})
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}


def test_university_admin_updates_own_overflow(client, auth_headers):
    make_university(client, auth_headers, name="UB", slug="ub")
    admin = _login(client, "admin_ub@test.com")
    resp = client.patch("/universities/me/overflow-threshold",
                        json={"overflow_threshold": 0.0}, headers=admin)
    assert resp.status_code == 200
    assert resp.json()["overflow_threshold"] == 0.0


def test_overflow_rejects_out_of_range(client, auth_headers):
    make_university(client, auth_headers, name="UB", slug="ub")
    admin = _login(client, "admin_ub@test.com")
    assert client.patch("/universities/me/overflow-threshold",
                        json={"overflow_threshold": 1.5}, headers=admin).status_code == 422
    assert client.patch("/universities/me/overflow-threshold",
                        json={"overflow_threshold": -0.1}, headers=admin).status_code == 422


def test_overflow_forbidden_for_lecturer(client, auth_headers, db):
    uni = make_university(client, auth_headers, name="UB", slug="ub")
    lect = User(email="lect@test.com", hashed_password=get_password_hash("password123"),
                full_name="L", role="lecturer", is_active=True, is_verified=True,
                university_id=uni["id"])
    db.add(lect)
    db.commit()
    headers = _login(client, "lect@test.com")
    resp = client.patch("/universities/me/overflow-threshold",
                        json={"overflow_threshold": 0.1}, headers=headers)
    assert resp.status_code == 403
