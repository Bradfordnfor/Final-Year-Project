"""
Tests for the new realism guards:
  - pre-generation readiness checklist (app/solver/readiness.py)
  - the generate endpoint hard-blocks an unready run
  - a faculty head must be assigned to a faculty at creation
  - a faculty head only lists runs that include their faculty
"""
from app.models.university import University, Faculty, Department
from app.models.academic import Level, Class, Semester, TimeSlot
from app.models.building import Building
from app.models.room import Room
from app.models.course import Course
from app.models.user import User, Lecturer
from app.models.timetable import TimetableRun, TimetableRunFaculty, TimetableRunBuilding
from app.core.security import get_password_hash
from app.solver.readiness import check_run_readiness, is_ready
from tests.conftest import activate_user


def _failed_keys(items):
    return {i.key for i in items if not i.ok}


def _build_ready_run(db, creator_id):
    """Create a fully-prepared run and return (run, course, room)."""
    uni = University(name="UB", slug="ub-ready", overflow_threshold=0.2)
    db.add(uni); db.flush()
    fac = Faculty(name="FET", code="FET", sessions_per_week=2,
                  session_duration_hours=2, university_id=uni.id)
    db.add(fac); db.flush()
    dept = Department(name="EE", code="EE", faculty_id=fac.id)
    db.add(dept); db.flush()
    level = Level(number=300, department_id=dept.id)
    db.add(level); db.flush()
    db.add(Class(name="EE300", population=100, level_id=level.id)); db.flush()
    sem = Semester(name="S1", start_date="2025-09-01", end_date="2026-01-31",
                   is_active=True, university_id=uni.id)
    db.add(sem); db.flush()
    db.add(TimeSlot(day_of_week="Monday", start_time="07:00",
                    end_time="09:00", semester_id=sem.id)); db.flush()
    bld = Building(name="Tech Block", university_id=uni.id)
    db.add(bld); db.flush()
    room = Room(name="Hall 1", capacity=200, room_type="lecture_hall",
                is_active=True, building_id=bld.id)
    db.add(room); db.flush()
    luser = User(email="lect@ub.cm", hashed_password="x", full_name="Dr X",
                 role="lecturer", is_active=True)
    db.add(luser); db.flush()
    lect = Lecturer(user_id=luser.id, department_id=dept.id)
    db.add(lect); db.flush()
    course = Course(code="EE301", name="Circuits", room_type_required="lecture_hall",
                    level_id=level.id, department_id=dept.id,
                    lecturer_id=lect.id, weekly_hours=2)
    db.add(course); db.flush()
    run = TimetableRun(name="Run 1", semester_id=sem.id,
                       created_by=creator_id, status="draft")
    db.add(run); db.flush()
    db.add(TimetableRunFaculty(run_id=run.id, faculty_id=fac.id))
    db.add(TimetableRunBuilding(run_id=run.id, building_id=bld.id))
    db.commit(); db.refresh(run)
    return run, course, room


# ─── Readiness function ───────────────────────────────────────────────────────

def test_ready_when_everything_is_in_place(db, admin_user):
    run, _course, _room = _build_ready_run(db, admin_user.id)
    items = check_run_readiness(run, db)
    assert is_ready(items), _failed_keys(items)


def test_not_ready_without_a_lecturer(db, admin_user):
    run, course, _room = _build_ready_run(db, admin_user.id)
    course.lecturer_id = None
    db.commit()
    items = check_run_readiness(run, db)
    assert not is_ready(items)
    assert "lecturers" in _failed_keys(items)


def test_not_ready_without_active_rooms(db, admin_user):
    run, _course, room = _build_ready_run(db, admin_user.id)
    room.is_active = False
    db.commit()
    items = check_run_readiness(run, db)
    failed = _failed_keys(items)
    assert "rooms" in failed
    assert "room_types" in failed  # no lecture_hall available either


def test_not_ready_without_time_slots(db, admin_user):
    run, _course, _room = _build_ready_run(db, admin_user.id)
    db.query(TimeSlot).delete()
    db.commit()
    items = check_run_readiness(run, db)
    assert "time_slots" in _failed_keys(items)


def test_empty_run_reports_missing_faculties_and_buildings(db, admin_user):
    sem = Semester(name="S", start_date="2025-09-01", end_date="2026-01-31",
                   university_id=1)
    db.add(sem); db.flush()
    run = TimetableRun(name="Empty", semester_id=sem.id,
                       created_by=admin_user.id, status="draft")
    db.add(run); db.commit(); db.refresh(run)
    failed = _failed_keys(check_run_readiness(run, db))
    assert {"faculties", "buildings", "courses"}.issubset(failed)


# ─── A faculty with no classes is not ready ───────────────────────────────────

def test_not_ready_when_faculty_has_no_classes(db, admin_user):
    """FHS-style: a faculty with no departments/classes, while the university
    has a university-wide course (with a lecturer). The checklist must flag the
    missing classes and must NOT nag about room types — with no classes there
    are no sessions, so there is no room demand to satisfy yet."""
    uni = University(name="UB", slug="ub-noclass", overflow_threshold=0.2)
    db.add(uni); db.flush()
    fac = Faculty(name="FHS", code="FHS", sessions_per_week=2,
                  session_duration_hours=2, university_id=uni.id)
    db.add(fac); db.flush()                       # no departments / levels / classes
    sem = Semester(name="S1", start_date="2025-09-01", end_date="2026-01-31",
                   is_active=True, university_id=uni.id)
    db.add(sem); db.flush()
    db.add(TimeSlot(day_of_week="Monday", start_time="07:00",
                    end_time="09:00", semester_id=sem.id)); db.flush()
    bld = Building(name="Health Block", university_id=uni.id)
    db.add(bld); db.flush()
    # The only room is a lab, but the university-wide course needs a lecture hall.
    db.add(Room(name="Lab 1", capacity=60, room_type="lab",
                is_active=True, building_id=bld.id)); db.flush()
    luser = User(email="lect_uw@ub.cm", hashed_password="x", full_name="Dr UW",
                 role="lecturer", is_active=True)
    db.add(luser); db.flush()
    # A department is needed only to hang the lecturer off; it has no classes.
    dept = Department(name="GS", code="GS", faculty_id=fac.id)
    db.add(dept); db.flush()
    lect = Lecturer(user_id=luser.id, department_id=dept.id)
    db.add(lect); db.flush()
    db.add(Course(code="GST101", name="Use of English",
                  room_type_required="lecture_hall", level_id=None,
                  department_id=None, university_id=uni.id,
                  lecturer_id=lect.id, weekly_hours=2)); db.flush()
    run = TimetableRun(name="FHS Run", semester_id=sem.id,
                       created_by=admin_user.id, status="draft")
    db.add(run); db.flush()
    db.add(TimetableRunFaculty(run_id=run.id, faculty_id=fac.id))
    db.add(TimetableRunBuilding(run_id=run.id, building_id=bld.id))
    db.commit(); db.refresh(run)

    items = check_run_readiness(run, db)
    failed = _failed_keys(items)
    assert "classes" in failed, failed
    # The room-type nag is gone: no classes means no sessions, no room demand.
    assert "room_types" not in failed, failed


# ─── Outdoor courses need no building room ────────────────────────────────────

def test_outdoor_course_is_ready_without_a_matching_room(db, admin_user):
    # The only room is a lecture hall, but an outdoor course needs no room.
    run, course, _room = _build_ready_run(db, admin_user.id)
    course.room_type_required = "outdoor"
    db.commit()
    items = check_run_readiness(run, db)
    assert is_ready(items), _failed_keys(items)
    assert "room_types" not in _failed_keys(items)


def test_outdoor_session_is_scheduled_with_no_room(db, admin_user):
    from app.solver.db_preprocessor import build_solver_input
    from app.solver.solver import solve_timetable
    from app.solver.postprocessor import save_solver_result
    from app.models.timetable import TimetableEntry

    run, course, _room = _build_ready_run(db, admin_user.id)
    course.room_type_required = "outdoor"
    course.weekly_hours = 1  # one session fits the single time slot
    db.commit()

    faculty_ids = [rf.faculty_id for rf in run.faculties]
    building_ids = [rb.building_id for rb in run.buildings]
    solver_input, _conflicts = build_solver_input(
        run_id=run.id, semester_id=run.semester_id,
        faculty_ids=faculty_ids, building_ids=building_ids, db=db,
    )
    # A virtual outdoor room (negative id) was injected for the outdoor session.
    assert any(r["id"] < 0 and r["room_type"] == "outdoor"
               for r in solver_input.rooms)

    result = solve_timetable(solver_input)
    assert result.status in ("optimal", "feasible")
    save_solver_result(run, result, db)

    entries = db.query(TimetableEntry).filter(
        TimetableEntry.run_id == run.id).all()
    assert entries, "the outdoor course should have been scheduled"
    assert all(e.room_id is None for e in entries), \
        "outdoor sessions must be stored with no room"


# ─── Generate endpoint guard ──────────────────────────────────────────────────

def test_generate_blocked_when_not_ready(client, auth_headers, db, admin_user):
    sem = Semester(name="S", start_date="2025-09-01", end_date="2026-01-31",
                   university_id=1)
    db.add(sem); db.flush()
    run = TimetableRun(name="Bare", semester_id=sem.id,
                       created_by=admin_user.id, status="draft")
    db.add(run); db.commit(); db.refresh(run)
    resp = client.post(f"/runs/{run.id}/generate", headers=auth_headers)
    assert resp.status_code == 400
    assert "not ready" in resp.json()["detail"].lower()


def test_readiness_endpoint_returns_checklist(client, auth_headers, db, admin_user):
    run, _course, _room = _build_ready_run(db, admin_user.id)
    resp = client.get(f"/runs/{run.id}/readiness", headers=auth_headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["ready"] is True
    assert any(c["key"] == "lecturers" for c in body["checks"])


# ─── Faculty head must have a faculty ──────────────────────────────────────────

def _make_faculty(db):
    uni = University(name="UB", slug="ub-fac", overflow_threshold=0.2)
    db.add(uni); db.flush()
    fac = Faculty(name="COT", code="COT", sessions_per_week=2,
                  session_duration_hours=2, university_id=uni.id)
    db.add(fac); db.commit(); db.refresh(fac)
    return fac


def test_faculty_head_requires_a_faculty(client, auth_headers, db):
    resp = client.post("/users/", json={
        "email": "head_nofac@ub.cm",
        "full_name": "No Faculty Head", "role": "faculty_head",
    }, headers=auth_headers)
    assert resp.status_code == 400


def test_faculty_head_created_with_faculty(client, auth_headers, db):
    fac = _make_faculty(db)
    resp = client.post("/users/", json={
        "email": "head_cot@ub.cm",
        "full_name": "COT Head", "role": "faculty_head", "faculty_id": fac.id,
    }, headers=auth_headers)
    assert resp.status_code == 201
    assert resp.json()["faculty_id"] == fac.id


def test_second_head_for_same_faculty_rejected(client, auth_headers, db):
    fac = _make_faculty(db)
    client.post("/users/", json={
        "email": "head1@ub.cm",
        "full_name": "Head One", "role": "faculty_head", "faculty_id": fac.id,
    }, headers=auth_headers)
    resp = client.post("/users/", json={
        "email": "head2@ub.cm",
        "full_name": "Head Two", "role": "faculty_head", "faculty_id": fac.id,
    }, headers=auth_headers)
    assert resp.status_code == 400


# ─── Faculty head run scoping ─────────────────────────────────────────────────

def test_faculty_head_only_sees_runs_for_their_faculty(client, db, admin_user):
    run, _course, _room = _build_ready_run(db, admin_user.id)
    run_faculty_id = run.faculties[0].faculty_id
    # A faculty head only sees a run once it is under review or published, so put
    # both runs in a head-visible state to isolate the faculty-scoping check.
    run.status = "under_review"

    # A second faculty + a run that does NOT include the head's faculty
    other_uni = University(name="UB2", slug="ub2-scope", overflow_threshold=0.2)
    db.add(other_uni); db.flush()
    other_fac = Faculty(name="FS", code="FS", sessions_per_week=2,
                        session_duration_hours=2, university_id=other_uni.id)
    db.add(other_fac); db.flush()
    other_run = TimetableRun(name="Other", semester_id=run.semester_id,
                             created_by=admin_user.id, status="under_review")
    db.add(other_run); db.flush()
    db.add(TimetableRunFaculty(run_id=other_run.id, faculty_id=other_fac.id))

    head = User(email="scoped_head@ub.cm", hashed_password=get_password_hash("pass123"),
                full_name="Scoped Head", role="faculty_head",
                faculty_id=run_faculty_id, is_active=True)
    db.add(head); db.commit()
    activate_user("scoped_head@ub.cm", password="pass123")

    token = client.post("/auth/login", json={
        "email": "scoped_head@ub.cm", "password": "pass123",
    }).json()["access_token"]
    resp = client.get("/runs/", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    ids = {r["id"] for r in resp.json()}
    assert run.id in ids
    assert other_run.id not in ids
