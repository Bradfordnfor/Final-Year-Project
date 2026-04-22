from sqlalchemy.orm import Session
from app.solver.models import SolverResult
from app.models.timetable import TimetableRun, TimetableEntry, TimetableEntryClass


def save_solver_result(
    run: TimetableRun,
    result: SolverResult,
    db: Session,
) -> None:
    for assignment in result.assignments:
        entry = TimetableEntry(
            run_id=run.id,
            course_id=assignment.session.course_id,
            lecturer_id=assignment.session.lecturer_id,
            room_id=assignment.room_id,
            time_slot_id=assignment.time_slot_id,
            group_id=assignment.session.group_id,
            week_pattern="every_week",
            is_overcapacity=assignment.is_overcapacity,
            is_merged=assignment.session.is_merged,
        )
        db.add(entry)
        db.flush()

        for class_id in assignment.session.class_ids:
            db.add(TimetableEntryClass(entry_id=entry.id, class_id=class_id))

    db.commit()
