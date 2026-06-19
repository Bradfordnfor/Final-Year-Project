"""Generation must only schedule courses belonging to the run's semester:
a first-semester run pulls first-semester (and year-long) courses, never the
second-semester ones."""
from app.models.university import University, Faculty, Department
from app.models.academic import Level, Class, Semester, TimeSlot
from app.models.building import Building
from app.models.room import Room
from app.models.course import Course
from app.models.user import User, Lecturer
from app.models.timetable import TimetableRun, TimetableRunFaculty, TimetableRunBuilding
from app.solver.db_preprocessor import build_solver_input


def _setup(db, term):
    uni = University(name="UB", slug=f"ub-sem-{term}", overflow_threshold=0.2)
    db.add(uni); db.flush()
    fac = Faculty(name="FET", code="FET", sessions_per_week=2,
                  session_duration_hours=2, university_id=uni.id)
    db.add(fac); db.flush()
    dept = Department(name="EE", code="EE", faculty_id=fac.id)
    db.add(dept); db.flush()
    level = Level(number=300, department_id=dept.id)
    db.add(level); db.flush()
    db.add(Class(name="EE300", population=50, level_id=level.id)); db.flush()
    sem = Semester(name="S", start_date="2025-09-01", end_date="2026-01-31",
                   university_id=uni.id, term=term)
    db.add(sem); db.flush()
    db.add(TimeSlot(day_of_week="Monday", start_time="07:00",
                    end_time="09:00", semester_id=sem.id)); db.flush()
    bld = Building(name="Block", university_id=uni.id)
    db.add(bld); db.flush()
    db.add(Room(name="Hall", capacity=200, room_type="lecture_hall",
                is_active=True, building_id=bld.id)); db.flush()
    luser = User(email=f"l{term}@ub.cm", hashed_password="x", full_name="Dr X",
                 role="lecturer", is_active=True)
    db.add(luser); db.flush()
    lect = Lecturer(user_id=luser.id, department_id=dept.id)
    db.add(lect); db.flush()

    def course(code, semester):
        c = Course(code=code, name=code, room_type_required="lecture_hall",
                   level_id=level.id, department_id=dept.id,
                   lecturer_id=lect.id, weekly_hours=1, semester=semester)
        db.add(c); db.flush()
        return c

    first = course("EE301", 1)
    second = course("EE302", 2)
    annual = course("EE300A", 0)

    run = TimetableRun(name="Run", semester_id=sem.id, created_by=luser.id, status="draft")
    db.add(run); db.flush()
    db.add(TimetableRunFaculty(run_id=run.id, faculty_id=fac.id))
    db.add(TimetableRunBuilding(run_id=run.id, building_id=bld.id))
    db.commit(); db.refresh(run)
    return run, sem, fac, bld, first, second, annual


def test_first_semester_run_excludes_second_semester_courses(db):
    run, sem, fac, bld, first, second, annual = _setup(db, term=1)
    solver_input, _ = build_solver_input(
        run_id=run.id, semester_id=sem.id,
        faculty_ids=[fac.id], building_ids=[bld.id], db=db,
    )
    scheduled = {s.course_id for s in solver_input.sessions}
    assert first.id in scheduled          # first-semester course present
    assert annual.id in scheduled         # year-long course present
    assert second.id not in scheduled     # second-semester course excluded


def test_second_semester_run_excludes_first_semester_courses(db):
    run, sem, fac, bld, first, second, annual = _setup(db, term=2)
    solver_input, _ = build_solver_input(
        run_id=run.id, semester_id=sem.id,
        faculty_ids=[fac.id], building_ids=[bld.id], db=db,
    )
    scheduled = {s.course_id for s in solver_input.sessions}
    assert second.id in scheduled
    assert annual.id in scheduled
    assert first.id not in scheduled
