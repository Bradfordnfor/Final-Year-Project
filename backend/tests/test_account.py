"""Self-service account email change (My Account dialog)."""
from app.models.user import User
from app.core.security import get_password_hash


def test_change_email_succeeds(client, auth_headers, db, admin_user):
    resp = client.post("/auth/change-email",
                       json={"email": "newadmin@test.com"}, headers=auth_headers)
    assert resp.status_code == 200
    assert resp.json()["email"] == "newadmin@test.com"
    db.expire_all()
    assert db.get(User, admin_user.id).email == "newadmin@test.com"


def test_change_email_rejects_duplicate(client, auth_headers, db, admin_user):
    db.add(User(email="taken@test.com", hashed_password=get_password_hash("x"),
                full_name="T", role="lecturer", is_active=True))
    db.commit()
    resp = client.post("/auth/change-email",
                       json={"email": "taken@test.com"}, headers=auth_headers)
    assert resp.status_code == 400


def test_change_email_rejects_invalid(client, auth_headers):
    resp = client.post("/auth/change-email",
                       json={"email": "notanemail"}, headers=auth_headers)
    assert resp.status_code == 400
