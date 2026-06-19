"""
Pre-generation readiness checks.

Before a timetable run is allowed to generate, the data it depends on must
actually be in place. This module inspects a run exactly the way the
preprocessor does (same faculty -> department -> course scoping, same
building -> room scoping) and reports a checklist. If any check fails, the
run is not ready and generation is blocked.
"""
from dataclasses import dataclass
from sqlalchemy.orm import Session

from app.models.university import Department
from app.models.academic import TimeSlot, Semester
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

    # Courses in scope: same as the preprocessor (departments of selected faculties)
    dept_ids = [
        d.id for d in
        db.query(Department).filter(Department.faculty_id.in_(faculty_ids)).all()
    ] if faculty_ids else []
    # Match the generator: only this semester's courses (term, plus year-long).
    semester = db.get(Semester, run.semester_id)
    term = semester.term if semester else 1
    courses = (
        db.query(Course)
        .filter(Course.department_id.in_(dept_ids), Course.semester.in_([term, 0]))
        .all()
        if dept_ids else []
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

    # 7. A room exists for each room type the courses require
    required_types = {c.room_type_required for c in courses if c.room_type_required}
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
