from tests.conftest import make_university
from app.models.user import User
from app.core.security import get_password_hash
from app.models.university import University, Faculty, Department


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


def _make_head_with_dept(db, slug="ub"):
    uni = University(name=f"U-{slug}", slug=slug, overflow_threshold=0.2)
    db.add(uni)
    db.flush()
    fac = Faculty(name="FET", code="FET", university_id=uni.id)
    db.add(fac)
    db.flush()
    dept = Department(name="Electrical", code="EE", faculty_id=fac.id)
    db.add(dept)
    db.flush()
    head = User(email=f"head_{slug}@test.com",
                hashed_password=get_password_hash("password123"),
                full_name="Head", role="faculty_head", is_active=True,
                is_verified=True, university_id=uni.id, faculty_id=fac.id)
    db.add(head)
    db.commit()
    return uni, fac, dept, head


def test_faculty_head_renames_own_department(client, db):
    _, _, dept, head = _make_head_with_dept(db)
    headers = _login(client, head.email)
    resp = client.patch(f"/faculty-setup/departments/{dept.id}",
                        json={"name": "Electrical Engineering"}, headers=headers)
    assert resp.status_code == 200
    assert resp.json()["name"] == "Electrical Engineering"


def test_faculty_head_cannot_rename_other_faculty_department(client, db):
    _, _, _, head = _make_head_with_dept(db, slug="ub")
    # A department in a different faculty/university.
    other_fac = Faculty(name="FS", code="FS", university_id=head.university_id)
    db.add(other_fac)
    db.flush()
    other_dept = Department(name="Physics", code="PHY", faculty_id=other_fac.id)
    db.add(other_dept)
    db.commit()
    headers = _login(client, head.email)
    resp = client.patch(f"/faculty-setup/departments/{other_dept.id}",
                        json={"name": "Hacked"}, headers=headers)
    assert resp.status_code == 404


def test_lecturer_cannot_rename_department(client, db):
    _, _, dept, head = _make_head_with_dept(db)
    lect = User(email="lect2@test.com", hashed_password=get_password_hash("password123"),
                full_name="L", role="lecturer", is_active=True, is_verified=True,
                university_id=head.university_id)
    db.add(lect)
    db.commit()
    headers = _login(client, "lect2@test.com")
    resp = client.patch(f"/faculty-setup/departments/{dept.id}",
                        json={"name": "Nope"}, headers=headers)
    assert resp.status_code == 403
