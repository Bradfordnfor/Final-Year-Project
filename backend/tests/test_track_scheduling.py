"""A track-specific course (class_id set) schedules for only its own class;
a whole-level course (class_id NULL) covers every class at the level, so the
two tracks can be taught in parallel."""
from app.models.university import University, Faculty, Department
from app.models.academic import Level, Class, Semester, TimeSlot
from app.models.building import Building
from app.models.room import Room
from app.models.course import Course
from app.models.user import User, Lecturer
from app.models.timetable import TimetableRun, TimetableRunFaculty, TimetableRunBuilding
from app.solver.db_preprocessor import build_solver_input


def _setup(db):
    uni = University(name="UB", slug="ub-track", overflow_threshold=0.2)
    db.add(uni); db.flush()
    fac = Faculty(name="FET", code="FET", sessions_per_week=2,
                  session_duration_hours=2, university_id=uni.id)
    db.add(fac); db.flush()
    dept = Department(name="CE", code="CE", faculty_id=fac.id)
    db.add(dept); db.flush()
    level = Level(number=400, department_id=dept.id)
    db.add(level); db.flush()
    sw = Class(name="CE400 Software", population=120, level_id=level.id, track="Software")
    net = Class(name="CE400 Networking", population=80, level_id=level.id, track="Networking")
    db.add(sw); db.add(net); db.flush()
    sem = Semester(name="S", start_date="2025-09-01", end_date="2026-01-31",
                   university_id=uni.id, term=1)
    db.add(sem); db.flush()
    db.add(TimeSlot(day_of_week="Monday", start_time="07:00",
                    end_time="09:00", semester_id=sem.id)); db.flush()
    bld = Building(name="Block", university_id=uni.id)
    db.add(bld); db.flush()
    db.add(Room(name="Hall", capacity=250, room_type="lecture_hall",
                is_active=True, building_id=bld.id)); db.flush()
    luser = User(email="lt@ub.cm", hashed_password="x", full_name="Dr X",
                 role="lecturer", is_active=True)
    db.add(luser); db.flush()
    lect = Lecturer(user_id=luser.id, department_id=dept.id)
    db.add(lect); db.flush()

    def course(code, class_id):
        c = Course(code=code, name=code, room_type_required="lecture_hall",
                   level_id=level.id, department_id=dept.id, class_id=class_id,
                   lecturer_id=lect.id, weekly_hours=1, semester=1)
        db.add(c); db.flush()
        return c

    sw_course = course("CE401SW", sw.id)      # Software only
    net_course = course("CE402NET", net.id)   # Networking only
    common = course("CE400C", None)           # whole level

    run = TimetableRun(name="Run", semester_id=sem.id, created_by=luser.id, status="draft")
    db.add(run); db.flush()
    db.add(TimetableRunFaculty(run_id=run.id, faculty_id=fac.id))
    db.add(TimetableRunBuilding(run_id=run.id, building_id=bld.id))
    db.commit(); db.refresh(run)
    return run, sem, fac, bld, sw, net, sw_course, net_course, common


def test_track_specific_course_targets_one_class(db):
    run, sem, fac, bld, sw, net, sw_course, net_course, common = _setup(db)
    solver_input, _ = build_solver_input(
        run_id=run.id, semester_id=sem.id,
        faculty_ids=[fac.id], building_ids=[bld.id], db=db,
    )
    sw_sessions = [s for s in solver_input.sessions if s.course_id == sw_course.id]
    assert sw_sessions, "Software course produced no session"
    for s in sw_sessions:
        assert set(s.class_ids) == {sw.id}     # only Software class


def test_whole_level_course_covers_all_classes(db):
    run, sem, fac, bld, sw, net, sw_course, net_course, common = _setup(db)
    solver_input, _ = build_solver_input(
        run_id=run.id, semester_id=sem.id,
        faculty_ids=[fac.id], building_ids=[bld.id], db=db,
    )
    common_sessions = [s for s in solver_input.sessions if s.course_id == common.id]
    assert common_sessions, "Common course produced no session"
    covered = set()
    for s in common_sessions:
        covered.update(s.class_ids)
    assert covered == {sw.id, net.id}          # both tracks
