"""University-wide courses are sat by every class and packed into shared halls.

A university-wide course (university_id set, no department) was being skipped by
the generator. It must be scheduled for every class in the run's faculties, with
classes grouped so several sit it together in one hall.
"""
from app.solver.preprocessor import compute_university_wide_sessions
from app.solver.db_preprocessor import build_solver_input
from app.models.university import Faculty
from app.models.course import Course
from tests.test_readiness_scoping import _build_ready_run


def test_bin_packs_classes_into_halls():
    course = {"id": 1, "code": "GST101", "room_type_required": "lecture_hall"}
    classes = [{"id": i, "population": 150} for i in range(1, 5)]  # 4 × 150
    rooms = [{"id": 1, "capacity": 300, "room_type": "lecture_hall"}]

    # cap = 300 * 1.2 = 360 → two 150-classes per group → 2 groups, 1 wk each
    sessions = compute_university_wide_sessions(
        course, classes, rooms, lecturer_id=9,
        sessions_per_week=1, overflow_threshold=0.2,
    )
    assert len(sessions) == 2
    for s in sessions:
        assert len(s.class_ids) == 2
        assert s.population == 300
        assert s.is_merged
    # every class is covered exactly once
    covered = [cid for s in sessions for cid in s.class_ids]
    assert sorted(covered) == [1, 2, 3, 4]


def test_weekly_hours_repeat_per_group():
    course = {"id": 2, "code": "GST102", "room_type_required": "lecture_hall"}
    classes = [{"id": 1, "population": 50}]
    rooms = [{"id": 1, "capacity": 300, "room_type": "lecture_hall"}]
    sessions = compute_university_wide_sessions(
        course, classes, rooms, lecturer_id=9,
        sessions_per_week=3, overflow_threshold=0.2,
    )
    assert len(sessions) == 3  # one group × 3 weekly sessions


def test_build_solver_input_includes_university_wide_course(db, admin_user):
    run, dept_course, _room = _build_ready_run(db, admin_user.id)
    fac = db.query(Faculty).filter(Faculty.code == "FET").first()

    uw = Course(
        code="GST101", name="Use of English",
        room_type_required="lecture_hall",
        university_id=fac.university_id, department_id=None, level_id=None,
        lecturer_id=dept_course.lecturer_id, weekly_hours=1, semester=0,
    )
    db.add(uw); db.commit()

    faculty_ids = [rf.faculty_id for rf in run.faculties]
    building_ids = [rb.building_id for rb in run.buildings]
    solver_input, _conflicts = build_solver_input(
        run_id=run.id, semester_id=run.semester_id,
        faculty_ids=faculty_ids, building_ids=building_ids, db=db,
    )

    uw_sessions = [s for s in solver_input.sessions if s.course_id == uw.id]
    assert uw_sessions, "university-wide course should be scheduled"
    covered = {cid for s in uw_sessions for cid in s.class_ids}
    assert covered, "the run's class should attend the university-wide course"
