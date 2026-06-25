"""
Pre-generation readiness checks.

Before a timetable run is allowed to generate, the data it depends on must
actually be in place. This module inspects a run exactly the way the
preprocessor does (same faculty -> department -> course scoping, same
building -> room scoping) and reports a checklist. If any check fails, the
run is not ready and generation is blocked.
"""
from dataclasses import dataclass
from sqlalchemy import or_, and_
from sqlalchemy.orm import Session

from app.models.university import Department, Faculty
from app.models.academic import TimeSlot, Semester, Level, Class
from app.models.course import Course
from app.models.room import Room


@dataclass
class ReadinessItem:
    key: str
    label: str
    ok: bool
    detail: str = ""


def check_run_readiness(run, db: Session) -> list[ReadinessItem]:
    """Return one ReadinessItem per check. A run is ready when all are ok."""
    faculty_ids = [rf.faculty_id for rf in run.faculties]
    building_ids = [rb.building_id for rb in run.buildings]
    items: list[ReadinessItem] = []

    # 1. At least one faculty selected
    items.append(ReadinessItem(
        key="faculties",
        label="At least one faculty is selected",
        ok=bool(faculty_ids),
        detail="" if faculty_ids else "This run has no faculties. Add faculties to the run.",
    ))

    # 2. At least one building selected
    items.append(ReadinessItem(
        key="buildings",
        label="At least one building is selected",
        ok=bool(building_ids),
        detail="" if building_ids else "This run has no buildings. Add buildings to the run.",
    ))

    # 3. Selected buildings contain at least one active room
    active_rooms = (
        db.query(Room)
        .filter(Room.building_id.in_(building_ids), Room.is_active == True)  # noqa: E712
        .all()
        if building_ids else []
    )
    items.append(ReadinessItem(
        key="rooms",
        label="Selected buildings have at least one active room",
        ok=bool(active_rooms),
        detail="" if active_rooms else "No active rooms found in the selected buildings.",
    ))

    # 4. The semester has time slots
    slot_count = (
        db.query(TimeSlot).filter(TimeSlot.semester_id == run.semester_id).count()
    )
    items.append(ReadinessItem(
        key="time_slots",
        label="The semester has time slots defined",
        ok=slot_count > 0,
        detail="" if slot_count else "This semester has no time slots. Define the weekly slots first.",
    ))

    # 5. The selected faculties contain at least one class. Without classes there
    #    is nothing to schedule — even university-wide courses need classes to
    #    sit them — so a faculty with no departments/levels/classes (e.g. one not
    #    yet set up) can never produce a real timetable. Scoped exactly as the
    #    preprocessor scopes its classes (Class -> Level -> Department -> faculty).
    class_count = (
        db.query(Class)
        .join(Level, Level.id == Class.level_id)
        .join(Department, Department.id == Level.department_id)
        .filter(Department.faculty_id.in_(faculty_ids))
        .count()
        if faculty_ids else 0
    )
    items.append(ReadinessItem(
        key="classes",
        label="The selected faculties have at least one class",
        ok=class_count > 0,
        detail="" if class_count else
        "The selected faculties have no classes. Add departments, levels and "
        "classes (with their student populations) before generating.",
    ))

    # Courses in scope: same as the preprocessor (departments of selected faculties)
    dept_ids = [
        d.id for d in
        db.query(Department).filter(Department.faculty_id.in_(faculty_ids)).all()
    ] if faculty_ids else []
    # Match the generator: only this semester's courses (term, plus year-long).
    # Includes department courses of the selected faculties AND the university's
    # university-wide courses (no department), which every class sits.
    semester = db.get(Semester, run.semester_id)
    term = semester.term if semester else 1
    university_id = None
    if faculty_ids:
        fac = db.query(Faculty).filter(Faculty.id.in_(faculty_ids)).first()
        university_id = fac.university_id if fac else None
    scope_conditions = []
    if dept_ids:
        scope_conditions.append(Course.department_id.in_(dept_ids))
    if university_id is not None:
        scope_conditions.append(
            and_(Course.university_id == university_id, Course.department_id.is_(None))
        )
    courses = (
        db.query(Course)
        .filter(Course.semester.in_([term, 0]), or_(*scope_conditions))
        .all()
        if scope_conditions else []
    )

    # 5. There are courses to schedule
    items.append(ReadinessItem(
        key="courses",
        label="The selected faculties have courses for this semester",
        ok=bool(courses),
        detail="" if courses else "No courses found for the selected faculties in this semester.",
    ))

    # 6. Every course has a lecturer assigned
    unassigned = [c for c in courses if not c.lecturer_id]
    items.append(ReadinessItem(
        key="lecturers",
        label="Every course has a lecturer assigned",
        ok=not unassigned,
        detail="" if not unassigned else
        "These courses have no lecturer: " + ", ".join(sorted(c.code for c in unassigned)),
    ))

    # 7. A room exists for each room type the courses require. Outdoor courses
    #    are excluded: they run off-site and need no building room at all.
    # With no classes there are no sessions, hence no room demand — don't nag
    # about a missing room type until there is actually something to place.
    required_types = {
        c.room_type_required for c in courses
        if c.room_type_required and c.room_type_required != "outdoor"
    } if class_count else set()
    available_types = {r.room_type for r in active_rooms}
    missing_types = sorted(required_types - available_types)
    items.append(ReadinessItem(
        key="room_types",
        label="A matching room exists for every required room type",
        ok=not missing_types,
        detail="" if not missing_types else
        "No active room of type: " + ", ".join(missing_types),
    ))

    return items


def is_ready(items: list[ReadinessItem]) -> bool:
    return all(i.ok for i in items)
