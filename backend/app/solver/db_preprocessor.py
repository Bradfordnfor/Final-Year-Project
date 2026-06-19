from sqlalchemy.orm import Session
from app.models.university import Department, Faculty
from app.models.academic import Level, Class, Semester, TimeSlot
from app.models.building import Building
from app.models.course import Course, SharedCourse
from app.models.room import Room
from app.models.user import Lecturer, LecturerAvailability
from app.solver.models import SolverInput, ConflictFlag
from app.solver.preprocessor import compute_merge_decision, compute_lab_split


def build_solver_input(
    run_id: int,
    semester_id: int,
    faculty_ids: list[int],
    building_ids: list[int],
    db: Session,
) -> tuple[SolverInput, list[ConflictFlag]]:
    # overflow_threshold from first faculty; sessions_per_week is now per-course
    faculty = db.query(Faculty).filter(Faculty.id.in_(faculty_ids)).first()
    overflow_threshold = faculty.university.overflow_threshold if faculty else 0.20

    # Time slots for this semester
    raw_slots = db.query(TimeSlot).filter(TimeSlot.semester_id == semester_id).all()
    time_slots = [
        {"id": ts.id, "day": ts.day_of_week,
         "start": str(ts.start_time), "end": str(ts.end_time)}
        for ts in raw_slots
    ]

    # Rooms from selected buildings only
    raw_rooms = (
        db.query(Room)
        .filter(Room.building_id.in_(building_ids), Room.is_active == True)  # noqa: E712
        .all()
    )
    rooms = [
        {"id": r.id, "capacity": r.capacity, "room_type": r.room_type}
        for r in raw_rooms
    ]
    labs = [r for r in rooms if r["room_type"] == "lab"]

    # Lecturer unavailability
    unavailability: dict[int, list[int]] = {}
    avail_records = (
        db.query(LecturerAvailability)
        .join(TimeSlot, TimeSlot.id == LecturerAvailability.time_slot_id)
        .filter(TimeSlot.semester_id == semester_id)
        .all()
    )
    for rec in avail_records:
        unavailability.setdefault(rec.lecturer_id, []).append(rec.time_slot_id)

    # Get all departments across selected faculties
    dept_ids = [
        d.id for d in
        db.query(Department).filter(Department.faculty_id.in_(faculty_ids)).all()
    ]

    # Only schedule courses that belong to this run's semester. A semester's
    # `term` (1 or 2) is matched against each course's `semester` (1 or 2, or 0
    # for year-long courses that run in both). This keeps a first-semester run
    # from pulling in second-semester courses.
    semester = db.get(Semester, semester_id)
    term = semester.term if semester else 1
    courses = (
        db.query(Course)
        .filter(
            Course.department_id.in_(dept_ids),
            Course.semester.in_([term, 0]),
        )
        .all()
    )

    all_sessions = []
    all_conflicts: list[ConflictFlag] = []

    for course in courses:
        if not course.lecturer_id:
            continue

        sessions_per_week = course.weekly_hours

        shared_entries = db.query(SharedCourse).filter(SharedCourse.course_id == course.id).all()
        shared_class_ids = [s.class_id for s in shared_entries]

        # Classes at this course's level
        level_classes = (
            db.query(Class)
            .filter(Class.level_id == course.level_id)
            .all()
        )
        own_class_ids = [c.id for c in level_classes]
        attending_class_ids = list(set(own_class_ids + shared_class_ids))
        attending_classes = db.query(Class).filter(Class.id.in_(attending_class_ids)).all()

        classes_as_dicts = [{"id": c.id, "population": c.population} for c in attending_classes]
        course_dict = {
            "id": course.id, "code": course.code,
            "room_type_required": course.room_type_required,
        }

        if course.room_type_required == "lab":
            for cls in attending_classes:
                sessions, conflict = compute_lab_split(
                    course=course_dict,
                    student_class={"id": cls.id, "population": cls.population},
                    labs=labs,
                    sessions_per_week=sessions_per_week,
                    lecturer_id=course.lecturer_id,
                )
                all_sessions.extend(sessions)
                if conflict:
                    all_conflicts.append(conflict)
        else:
            sessions, conflict = compute_merge_decision(
                course=course_dict,
                classes=classes_as_dicts,
                rooms=rooms,
                lecturer_id=course.lecturer_id,
                sessions_per_week=sessions_per_week,
                overflow_threshold=overflow_threshold,
            )
            all_sessions.extend(sessions)
            if conflict:
                all_conflicts.append(conflict)

    return (
        SolverInput(
            sessions=all_sessions,
            time_slots=time_slots,
            rooms=rooms,
            lecturer_unavailability=unavailability,
        ),
        all_conflicts,
    )
