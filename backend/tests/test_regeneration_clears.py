"""Regenerating a run replaces its result instead of stacking on top.

Regression: generation appended entries without clearing the previous result,
so generating twice produced duplicate sessions and same-class time clashes.
"""
from app.routers.timetable import clear_run_result
from app.models.timetable import (
    TimetableRun, TimetableEntry, TimetableEntryClass, TimetableConflict,
)


def _seed_run_with_result(db, creator_id, name):
    run = TimetableRun(name=name, semester_id=1, created_by=creator_id,
                       status="draft")
    db.add(run); db.flush()
    entry = TimetableEntry(run_id=run.id, course_id=1, lecturer_id=1,
                           room_id=1, time_slot_id=1, week_pattern="every_week")
    db.add(entry); db.flush()
    db.add(TimetableEntryClass(entry_id=entry.id, class_id=10))
    db.add(TimetableConflict(run_id=run.id, conflict_type="x",
                             details="{}", resolved=False))
    db.commit()
    return run


def test_clear_run_result_removes_only_that_runs_data(db, admin_user):
    run1 = _seed_run_with_result(db, admin_user.id, "R1")
    run2 = _seed_run_with_result(db, admin_user.id, "R2")

    clear_run_result(run1.id, db)

    # run1 is wiped clean
    assert db.query(TimetableEntry).filter(
        TimetableEntry.run_id == run1.id).count() == 0
    assert db.query(TimetableConflict).filter(
        TimetableConflict.run_id == run1.id).count() == 0
    # the link rows for run1 are gone too (no orphans / FK errors)
    assert db.query(TimetableEntryClass).count() == 1  # only run2's link left

    # run2 is untouched
    assert db.query(TimetableEntry).filter(
        TimetableEntry.run_id == run2.id).count() == 1
    assert db.query(TimetableConflict).filter(
        TimetableConflict.run_id == run2.id).count() == 1
