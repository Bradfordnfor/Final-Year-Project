"""Redesigned lecturer bulk import: name/email/faculty/department/password CSV.

Faculty and department are matched by name within the importing admin's own
university; password is optional (generated when blank); bad rows are skipped
with a reason instead of aborting or crashing.
"""
from app.models.university import University, Faculty, Department
from app.models.user import User, Lecturer
from app.core.security import get_password_hash


def _setup_admin(db, client, *, with_university=True):
    uni = University(name="UB", slug="ub-bulk", overflow_threshold=0.2)
    db.add(uni); db.flush()
    fac = Faculty(name="Faculty of Engineering and Technology", code="FET",
                  sessions_per_week=2, session_duration_hours=2,
                  university_id=uni.id)
    db.add(fac); db.flush()
    db.add(Department(name="Computer Engineering", code="CE", faculty_id=fac.id))
    db.add(Department(name="Electrical Engineering", code="EE", faculty_id=fac.id))
    db.add(User(
        email="ua@ub.cm", hashed_password=get_password_hash("pass123"),
        full_name="UA", role="university_admin", is_active=True,
        university_id=uni.id if with_university else None,
    ))
    db.commit()
    token = client.post("/auth/login", json={
        "email": "ua@ub.cm", "password": "pass123"}).json()["access_token"]
    return uni, {"Authorization": f"Bearer {token}"}


def _post_csv(client, headers, text):
    return client.post(
        "/users/bulk-import/",
        files={"file": ("staff.csv", text, "text/csv")},
        headers=headers,
    )


def test_import_creates_with_generated_and_supplied_passwords(client, db):
    _uni, headers = _setup_admin(db, client)
    csv_text = (
        "name,email,faculty,department,password\n"
        "John Doe,jdoe@ub.cm,Faculty of Engineering and Technology,Computer Engineering,\n"
        # second row uses different casing to prove case-insensitive matching
        "Jane Smith,jsmith@ub.cm,faculty of engineering and technology,electrical engineering,Start123\n"
    )
    resp = _post_csv(client, headers, csv_text)
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["created"]) == 2
    assert body["skipped"] == []

    john = next(c for c in body["created"] if c["email"] == "jdoe@ub.cm")
    jane = next(c for c in body["created"] if c["email"] == "jsmith@ub.cm")
    assert "temp_password" in john          # blank -> generated and returned
    assert "temp_password" not in jane      # supplied -> not echoed

    # Both accounts exist as lecturers with a profile
    for email in ("jdoe@ub.cm", "jsmith@ub.cm"):
        user = db.query(User).filter(User.email == email).first()
        assert user is not None and user.role == "lecturer"
        assert db.query(Lecturer).filter(Lecturer.user_id == user.id).first()

    # Jane can log in with the password from the file
    login = client.post("/auth/login", json={
        "email": "jsmith@ub.cm", "password": "Start123"})
    assert login.status_code == 200


def test_import_skips_unknown_faculty_and_department(client, db):
    _uni, headers = _setup_admin(db, client)
    csv_text = (
        "name,email,faculty,department,password\n"
        "Bad Fac,bf@ub.cm,Faculty of Law,Computer Engineering,\n"
        "Bad Dept,bd@ub.cm,Faculty of Engineering and Technology,Astronomy,\n"
    )
    body = _post_csv(client, headers, csv_text).json()
    assert body["created"] == []
    reasons = {s["email"]: s["reason"] for s in body["skipped"]}
    assert "not found" in reasons["bf@ub.cm"]
    assert "not found" in reasons["bd@ub.cm"]


def test_import_skips_duplicate_email(client, db):
    _uni, headers = _setup_admin(db, client)
    csv_text = (
        "name,email,faculty,department,password\n"
        "Dup,ua@ub.cm,Faculty of Engineering and Technology,Computer Engineering,\n"
    )
    body = _post_csv(client, headers, csv_text).json()
    assert body["created"] == []
    assert body["skipped"][0]["reason"] == "already exists"


def test_import_requires_university_admin_with_university(client, db):
    _uni, headers = _setup_admin(db, client, with_university=False)
    csv_text = (
        "name,email,faculty,department,password\n"
        "X,x@ub.cm,Faculty of Engineering and Technology,Computer Engineering,\n"
    )
    resp = _post_csv(client, headers, csv_text)
    assert resp.status_code == 400


def test_import_missing_columns_is_400(client, db):
    _uni, headers = _setup_admin(db, client)
    resp = _post_csv(client, headers, "name,email\nX,x@ub.cm\n")
    assert resp.status_code == 400
