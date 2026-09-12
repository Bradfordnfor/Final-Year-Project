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


def test_university_admin_renames_faculty(client, auth_headers):
    uni = make_university(client, auth_headers, name="UB", slug="ub")
    admin = _login(client, "admin_ub@test.com")
    created = client.post("/faculties/", json={
        "name": "Faculty of Engineering", "code": "FET",
        "sessions_per_week": 2, "session_duration_hours": 2,
        "university_id": uni["id"],
    }, headers=admin)
    assert created.status_code == 201
    fac = created.json()
    resp = client.put(f"/faculties/{fac['id']}", json={
        "name": "Faculty of Engineering and Technology", "code": fac["code"],
        "sessions_per_week": fac["sessions_per_week"],
        "session_duration_hours": fac["session_duration_hours"],
        "university_id": fac["university_id"],
    }, headers=admin)
    assert resp.status_code == 200
    assert resp.json()["name"] == "Faculty of Engineering and Technology"


# ─── Fix 1: PUT /faculties/{id} must be scoped to caller's own university ────

def test_university_admin_cannot_rename_other_university_faculty(client, auth_headers, db):
    make_university(client, auth_headers, name="UD", slug="ud")
    uni_b = make_university(client, auth_headers, name="UE", slug="ue")
    fac_b = Faculty(name="FacE", code="FE", university_id=uni_b["id"])
    db.add(fac_b)
    db.commit()
    admin_a = _login(client, "admin_ud@test.com")
    resp = client.put(f"/faculties/{fac_b.id}", json={
        "name": "Hacked", "code": fac_b.code,
        "sessions_per_week": 2, "session_duration_hours": 2,
        "university_id": fac_b.university_id,
    }, headers=admin_a)
    assert resp.status_code == 404


# ─── Fix 3: faculty rename must reject a blank/whitespace-only name ─────────

def test_faculty_rename_rejects_blank_name(client, auth_headers):
    uni = make_university(client, auth_headers, name="UF", slug="uf")
    admin = _login(client, "admin_uf@test.com")
    created = client.post("/faculties/", json={
        "name": "Faculty X", "code": "FX",
        "sessions_per_week": 2, "session_duration_hours": 2,
        "university_id": uni["id"],
    }, headers=admin)
    fac = created.json()
    resp = client.put(f"/faculties/{fac['id']}", json={
        "name": "   ", "code": fac["code"],
        "sessions_per_week": fac["sessions_per_week"],
        "session_duration_hours": fac["session_duration_hours"],
        "university_id": fac["university_id"],
    }, headers=admin)
    assert resp.status_code == 422


# ─── Fix 2: admin-supplied ?faculty_id in faculty-setup must be validated ───

def test_university_admin_cannot_target_other_university_faculty_id(client, auth_headers, db):
    make_university(client, auth_headers, name="UA2", slug="ua2")
    uni_b = make_university(client, auth_headers, name="UB2", slug="ub2")
    fac_b = Faculty(name="FacB", code="FB", university_id=uni_b["id"])
    db.add(fac_b)
    db.flush()
    dept_b = Department(name="DeptB", code="DB", faculty_id=fac_b.id)
    db.add(dept_b)
    db.commit()
    admin_a = _login(client, "admin_ua2@test.com")
    resp = client.patch(
        f"/faculty-setup/departments/{dept_b.id}?faculty_id={fac_b.id}",
        json={"name": "Hacked"}, headers=admin_a,
    )
    assert resp.status_code == 404


def test_university_admin_renames_department_in_own_faculty(client, auth_headers, db):
    uni = make_university(client, auth_headers, name="UC2", slug="uc2")
    admin = _login(client, "admin_uc2@test.com")
    fac = Faculty(name="FacC", code="FC", university_id=uni["id"])
    db.add(fac)
    db.flush()
    dept = Department(name="DeptC", code="DC", faculty_id=fac.id)
    db.add(dept)
    db.commit()
    resp = client.patch(
        f"/faculty-setup/departments/{dept.id}?faculty_id={fac.id}",
        json={"name": "Renamed"}, headers=admin,
    )
    assert resp.status_code == 200
    assert resp.json()["name"] == "Renamed"
