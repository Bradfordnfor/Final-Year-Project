"""Wipe all courses and all timetable runs, keeping everything else.

This clears the demo course data so real courses can be loaded, while
preserving faculties, departments, levels, classes, lecturers, and rooms.

Deletion order matters because PostgreSQL enforces foreign keys:
  1. Timetable runs go first. Deleting a run cascades to its entries,
     conflicts, jobs, approvals, and run-faculty/run-building links, which
     removes every row that points at a course from those tables.
  2. Courses go next. Deleting a course cascades to its shared-course links.

Safety: nothing is deleted unless you pass --confirm. Without it the script
just prints what it would delete (a dry run).

Run from the backend/ directory:
    ./venv/Scripts/python.exe scripts/wipe_courses.py            # dry run
    ./venv/Scripts/python.exe scripts/wipe_courses.py --confirm  # do it
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.database import SessionLocal
from app.models.course import Course, SharedCourse
from app.models.timetable import (
    TimetableRun, TimetableEntry, TimetableConflict,
)


def counts(db):
    return {
        "courses": db.query(Course).count(),
        "shared_course links": db.query(SharedCourse).count(),
        "timetable runs": db.query(TimetableRun).count(),
        "timetable entries": db.query(TimetableEntry).count(),
        "timetable conflicts": db.query(TimetableConflict).count(),
    }


def main():
    confirm = "--confirm" in sys.argv
    db = SessionLocal()

    before = counts(db)
    print("Current counts:")
    for k, v in before.items():
        print(f"  {k:22}: {v}")

    if not confirm:
        print()
        print("DRY RUN - nothing deleted. Re-run with --confirm to wipe.")
        db.close()
        return

    # 1. Runs first: cascades clear entries, conflicts, jobs, approvals, links.
    for run in db.query(TimetableRun).all():
        db.delete(run)
    db.flush()

    # 2. Courses next: cascades clear shared-course links.
    for course in db.query(Course).all():
        db.delete(course)

    db.commit()

    after = counts(db)
    print()
    print("Done. Counts after wipe:")
    for k, v in after.items():
        print(f"  {k:22}: {v}")

    leftover = {k: v for k, v in after.items() if v}
    if leftover:
        print()
        print(f"WARNING: some rows remain: {leftover}")
    db.close()


if __name__ == "__main__":
    main()
