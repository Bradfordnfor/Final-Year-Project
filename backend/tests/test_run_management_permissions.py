"""A timetable officer can view analytics and resolve conflicts.

Regression: these endpoints required require_faculty_head, which excludes the
timetable_officer role, so the officer got 403 on the analytics page and when
resolving a conflict.
"""
from tests.conftest import make_university
from app.models.user import User
from app.models.timetable import TimetableConflict
from app.core.security import get_password_hash


def _officer_headers(client, db, university_id):
    db.add(User(
        email="officer@test.com", hashed_password=get_password_hash("pass123"),
        full_name="Officer", role="timetable_officer", is_active=True,
        university_id=university_id,
    ))
    db.commit()
    resp = client.post("/auth/login", json={
        "email": "officer@test.com", "password": "pass123"})
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}


def _make_run(client, auth_headers):
    uni = make_university(client, auth_headers, slug="ub-perm")
    sem = client.post("/semesters/", json={
        "name": "S1", "start_date": "2025-09-01", "end_date": "2026-01-31",
        "university_id": uni["id"],
    }, headers=auth_headers).json()
    run = client.post("/runs/", json={
        "name": "Run", "semester_id": sem["id"],
        "faculty_ids": [], "building_ids": [],
    }, headers=auth_headers).json()
    return uni, run


def test_officer_cannot_view_analytics(client, auth_headers, db):
    # Analytics is for admins and faculty heads, not the timetable officer.
    uni, run = _make_run(client, auth_headers)
    headers = _officer_headers(client, db, uni["id"])
    resp = client.get(f"/runs/{run['id']}/analytics", headers=headers)
    assert resp.status_code == 403


def test_admin_sees_whole_run_analytics(client, auth_headers, db):
    # auth_headers is the super admin — sees the whole run.
    _uni, run = _make_run(client, auth_headers)
    resp = client.get(f"/runs/{run['id']}/analytics", headers=auth_headers)
    assert resp.status_code == 200
    assert "total_entries" in resp.json()


def test_faculty_head_analytics_scoped_to_their_faculty(client, auth_headers, db, admin_user):
    from app.models.university import University, Faculty, Department
    from app.models.academic import Semester
    from app.models.course import Course
    from app.models.timetable import TimetableRun, TimetableEntry
    from app.models.user import User
    from app.core.security import get_password_hash

    uni = University(name="UB", slug="ub-an", overflow_threshold=0.2)
    db.add(uni); db.flush()
    fac_a = Faculty(name="FA", code="FA", sessions_per_week=2,
                    session_duration_hours=2, university_id=uni.id)
    fac_b = Faculty(name="FB", code="FB", sessions_per_week=2,
                    session_duration_hours=2, university_id=uni.id)
    db.add_all([fac_a, fac_b]); db.flush()
    dept_a = Department(name="DA", code="DA", faculty_id=fac_a.id)
    dept_b = Department(name="DB", code="DB", faculty_id=fac_b.id)
    db.add_all([dept_a, dept_b]); db.flush()
    course_a = Course(code="CA1", name="Course A",
                      room_type_required="lecture_hall",
                      department_id=dept_a.id, weekly_hours=1)
    course_b = Course(code="CB1", name="Course B",
                      room_type_required="lecture_hall",
                      department_id=dept_b.id, weekly_hours=1)
    db.add_all([course_a, course_b]); db.flush()
    sem = Semester(name="S", start_date="2025-09-01", end_date="2026-01-31",
                   is_active=True, university_id=uni.id)
    db.add(sem); db.flush()
    run = TimetableRun(name="R", semester_id=sem.id,
                       created_by=admin_user.id, status="draft")
    db.add(run); db.flush()
    db.add(TimetableEntry(run_id=run.id, course_id=course_a.id, lecturer_id=1,
                          room_id=1, time_slot_id=1, week_pattern="every_week"))
    db.add(TimetableEntry(run_id=run.id, course_id=course_b.id, lecturer_id=2,
                          room_id=1, time_slot_id=2, week_pattern="every_week"))
    db.add(User(email="head_a@test.com",
                hashed_password=get_password_hash("pass123"),
                full_name="Head A", role="faculty_head", is_active=True,
                university_id=uni.id, faculty_id=fac_a.id))
    db.commit()

    login = client.post("/auth/login", json={
        "email": "head_a@test.com", "password": "pass123"})
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}

    body = client.get(f"/runs/{run.id}/analytics", headers=headers).json()
    assert body["total_entries"] == 1  # only faculty A's session, not B's


def test_officer_can_resolve_conflict(client, auth_headers, db):
    uni, run = _make_run(client, auth_headers)
    headers = _officer_headers(client, db, uni["id"])
    conflict = TimetableConflict(
        run_id=run["id"], conflict_type="lab_split_conflict",
        details='{"groups_needed": 2, "sessions_available": 2}', resolved=False,
    )
    db.add(conflict); db.commit(); db.refresh(conflict)

    resp = client.post(
        f"/runs/{run['id']}/conflicts/{conflict.id}/resolve",
        json={"resolution": "rotate_groups"}, headers=headers)
    assert resp.status_code == 200
    assert resp.json()["resolved"] is True
