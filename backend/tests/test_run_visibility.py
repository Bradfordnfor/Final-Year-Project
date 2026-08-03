"""Run-list visibility by role and status.

Officer / university admin see every state; a faculty head sees a run only when
it is under review or published; a lecturer likewise. Drafts are private to the
officer and admins.
"""
from app.models.university import University, Faculty
from app.models.academic import Semester
from app.models.timetable import TimetableRun, TimetableRunFaculty
from app.models.user import User
from app.core.security import get_password_hash
from tests.conftest import activate_user


def _make_world(db, creator_id):
    uni = University(name="UB", slug="ub-vis", overflow_threshold=0.2)
    db.add(uni); db.flush()
    fac = Faculty(name="FET", code="FET", sessions_per_week=2,
                  session_duration_hours=2, university_id=uni.id)
    db.add(fac); db.flush()
    sem = Semester(name="S", start_date="2025-09-01", end_date="2026-01-31",
                   is_active=True, university_id=uni.id)
    db.add(sem); db.flush()
    for st in ("draft", "under_review", "approved", "published"):
        run = TimetableRun(name=st, semester_id=sem.id,
                           created_by=creator_id, status=st)
        db.add(run); db.flush()
        db.add(TimetableRunFaculty(run_id=run.id, faculty_id=fac.id))
    db.commit()
    return uni, fac


def _headers(client, db, email, role, **kw):
    db.add(User(email=email, hashed_password=get_password_hash("pass123"),
                full_name=role, role=role, is_active=True, **kw))
    db.commit()
    activate_user(email, password="pass123")
    resp = client.post("/auth/login", json={"email": email, "password": "pass123"})
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}


def _seen_statuses(client, headers):
    return {r["status"] for r in client.get("/runs/", headers=headers).json()}


def test_officer_sees_all_statuses(client, db, admin_user):
    uni, _fac = _make_world(db, admin_user.id)
    headers = _headers(client, db, "off@test.com", "timetable_officer",
                       university_id=uni.id)
    assert _seen_statuses(client, headers) == {
        "draft", "under_review", "approved", "published"}


def test_university_admin_sees_all_statuses(client, db, admin_user):
    uni, _fac = _make_world(db, admin_user.id)
    headers = _headers(client, db, "ua@test.com", "university_admin",
                       university_id=uni.id)
    assert _seen_statuses(client, headers) == {
        "draft", "under_review", "approved", "published"}


def test_faculty_head_sees_only_under_review_and_published(client, db, admin_user):
    uni, fac = _make_world(db, admin_user.id)
    headers = _headers(client, db, "head@test.com", "faculty_head",
                       university_id=uni.id, faculty_id=fac.id)
    assert _seen_statuses(client, headers) == {"under_review", "published"}


def test_lecturer_sees_only_under_review_and_published(client, db, admin_user):
    uni, _fac = _make_world(db, admin_user.id)
    headers = _headers(client, db, "lec@test.com", "lecturer",
                       university_id=uni.id)
    assert _seen_statuses(client, headers) == {"under_review", "published"}
