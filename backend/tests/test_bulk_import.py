"""Redesigned lecturer bulk import: name/email/faculty/department CSV.

Faculty and department are matched by name within the importing admin's own
university; every created account is pending (no password) and gets an
activation invitation emailed to it; bad rows are skipped with a reason
instead of aborting or crashing.
"""
from app.models.university import University, Faculty, Department
from app.models.user import User, Lecturer
from app.core.security import get_password_hash
from tests.conftest import activate_user


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
    activate_user("ua@ub.cm", password="pass123")
    token = client.post("/auth/login", json={
        "email": "ua@ub.cm", "password": "pass123"}).json()["access_token"]
    return uni, {"Authorization": f"Bearer {token}"}


def _post_csv(client, headers, text, dry_run=False):
    return client.post(
        "/users/bulk-import/",
        params={"dry_run": "true"} if dry_run else None,
        files={"file": ("staff.csv", text, "text/csv")},
        headers=headers,
    )


def test_import_creates_pending_lecturers_and_sends_invites(client, db, sent_emails):
    _uni, headers = _setup_admin(db, client)
    csv_text = (
        "name,email,faculty,department\n"
        "John Doe,jdoe@ub.cm,Faculty of Engineering and Technology,Computer Engineering\n"
        # second row uses different casing to prove case-insensitive matching
        "Jane Smith,jsmith@ub.cm,faculty of engineering and technology,electrical engineering\n"
    )
    resp = _post_csv(client, headers, csv_text)
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["created"]) == 2
    assert body["skipped"] == []
    assert all("temp_password" not in c for c in body["created"])

    # Both accounts exist as lecturers with a profile, pending activation
    for email in ("jdoe@ub.cm", "jsmith@ub.cm"):
        user = db.query(User).filter(User.email == email).first()
        assert user is not None and user.role == "lecturer"
        assert user.is_verified is False
        assert db.query(Lecturer).filter(Lecturer.user_id == user.id).first()
        assert any(m["to"] == email for m in sent_emails)

    # cannot log in until activated
    login = client.post("/auth/login", json={
        "email": "jsmith@ub.cm", "password": "whatever"})
    assert login.status_code in (401, 403)


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


def test_import_unreadable_file_is_friendly_400(client, db):
    """A binary / non-UTF-8 upload returns a clear 400, not a 500 exception."""
    _uni, headers = _setup_admin(db, client)
    resp = client.post(
        "/users/bulk-import/",
        files={"file": ("staff.xlsx",
                        b"PK\x03\x04\x14\x00\x00\x00\x08\x00\xff\xfe\x00bad",
                        "text/csv")},
        headers=headers,
    )
    assert resp.status_code == 400
    assert "csv" in resp.json()["detail"].lower()


# ─── Preview (dry-run) before committing ──────────────────────────────────────

def test_preview_validates_without_creating_anyone(client, db):
    _uni, headers = _setup_admin(db, client)
    csv_text = (
        "name,email,faculty,department\n"
        "John Doe,jdoe@ub.cm,Faculty of Engineering and Technology,Computer Engineering\n"
        "Bad Dept,bd@ub.cm,Faculty of Engineering and Technology,Astronomy\n"
    )
    body = _post_csv(client, headers, csv_text, dry_run=True).json()
    assert body["dry_run"] is True
    # One creatable candidate, one skipped — but nothing written.
    assert len(body["created"]) == 1
    john = body["created"][0]
    assert john["email"] == "jdoe@ub.cm"
    assert "temp_password" not in john              # nothing is minted during preview
    assert len(body["skipped"]) == 1
    assert db.query(User).filter(User.email == "jdoe@ub.cm").first() is None


def test_preview_then_commit_creates_accounts(client, db):
    _uni, headers = _setup_admin(db, client)
    csv_text = (
        "name,email,faculty,department\n"
        "John Doe,jdoe@ub.cm,Faculty of Engineering and Technology,Computer Engineering\n"
    )
    _post_csv(client, headers, csv_text, dry_run=True)
    assert db.query(User).filter(User.email == "jdoe@ub.cm").first() is None  # preview wrote nothing

    body = _post_csv(client, headers, csv_text).json()                       # real commit
    assert body["dry_run"] is False
    assert len(body["created"]) == 1
    assert "temp_password" not in body["created"][0]
    created_user = db.query(User).filter(User.email == "jdoe@ub.cm").first()
    assert created_user is not None
    assert created_user.is_verified is False


def test_preview_flags_duplicate_rows_within_the_file(client, db):
    _uni, headers = _setup_admin(db, client)
    csv_text = (
        "name,email,faculty,department,password\n"
        "One,dup@ub.cm,Faculty of Engineering and Technology,Computer Engineering,\n"
        "Two,dup@ub.cm,Faculty of Engineering and Technology,Computer Engineering,\n"
    )
    body = _post_csv(client, headers, csv_text, dry_run=True).json()
    assert len(body["created"]) == 1
    assert len(body["skipped"]) == 1
    assert "duplicate" in body["skipped"][0]["reason"].lower()
