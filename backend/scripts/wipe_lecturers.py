"""Wipe all lecturers so a fresh set can be uploaded, keeping everything else.

This clears lecturer accounts and their profiles (faculties, departments,
levels, classes, courses, and rooms are all preserved) so you can re-run the
bulk import or scripts/load_lecturers.py with a new roster.

Deletion order matters because foreign keys point at the rows we remove:
  1. Timetable runs go first. Every run entry carries a (required) lecturer_id,
     so a run that references a lecturer would block the delete. Deleting a run
     cascades to its entries, conflicts, jobs, approvals, and building links.
  2. Course.lecturer_id is set back to NULL. Courses stay; they just become
     unassigned and can be linked to the new lecturers later.
  3. Lecturer profiles go next. This cascades to each lecturer's availability.
  4. Verification tokens and notifications for lecturer accounts are removed,
     since both point at the user row we are about to delete.
  5. The lecturer user accounts themselves are deleted.

Safety: nothing is deleted unless you pass --confirm. Without it the script
just prints what it would delete (a dry run).

Run from the backend/ directory:
    ./venv/Scripts/python.exe scripts/wipe_lecturers.py            # dry run
    ./venv/Scripts/python.exe scripts/wipe_lecturers.py --confirm  # do it
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.database import SessionLocal
from app.models.user import User, Lecturer, LecturerAvailability
from app.models.course import Course
from app.models.timetable import TimetableRun, TimetableEntry, Notification
from app.models.verification import VerificationToken


def counts(db):
    lecturer_user_ids = [
        uid for (uid,) in
        db.query(User.id).filter(User.role == "lecturer").all()
    ]
    return {
        "lecturer accounts": db.query(User).filter(User.role == "lecturer").count(),
        "lecturer profiles": db.query(Lecturer).count(),
        "availability rows": db.query(LecturerAvailability).count(),
        "courses assigned": db.query(Course).filter(Course.lecturer_id.isnot(None)).count(),
        "timetable runs": db.query(TimetableRun).count(),
        "timetable entries": db.query(TimetableEntry).count(),
        "verification tokens": (
            db.query(VerificationToken)
            .filter(VerificationToken.user_id.in_(lecturer_user_ids)).count()
            if lecturer_user_ids else 0
        ),
        "notifications": (
            db.query(Notification)
            .filter(Notification.user_id.in_(lecturer_user_ids)).count()
            if lecturer_user_ids else 0
        ),
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

    lecturer_user_ids = [
        uid for (uid,) in
        db.query(User.id).filter(User.role == "lecturer").all()
    ]

    # 1. Runs first: their entries carry a required lecturer_id. Deleting the
    #    run cascades entries, conflicts, jobs, approvals, and building links.
    for run in db.query(TimetableRun).all():
        db.delete(run)
    db.flush()

    # 2. Unassign courses so the lecturer FK no longer blocks the delete.
    db.query(Course).filter(Course.lecturer_id.isnot(None)).update(
        {Course.lecturer_id: None}, synchronize_session=False
    )
    db.flush()

    # 3. Lecturer profiles: cascades clear each lecturer's availability.
    for lecturer in db.query(Lecturer).all():
        db.delete(lecturer)
    db.flush()

    # 4. Verification tokens and notifications point at the user rows.
    if lecturer_user_ids:
        db.query(VerificationToken).filter(
            VerificationToken.user_id.in_(lecturer_user_ids)
        ).delete(synchronize_session=False)
        db.query(Notification).filter(
            Notification.user_id.in_(lecturer_user_ids)
        ).delete(synchronize_session=False)
        db.flush()

    # 5. Finally the lecturer accounts themselves.
    db.query(User).filter(User.role == "lecturer").delete(
        synchronize_session=False
    )

    db.commit()

    after = counts(db)
    print()
    print("Done. Counts after wipe:")
    for k, v in after.items():
        print(f"  {k:22}: {v}")

    # "courses assigned" and "timetable runs" are expected to be 0 now, so the
    # only rows we warn about are lecturer accounts/profiles that somehow remain.
    leftover = {
        k: v for k, v in after.items()
        if v and k in ("lecturer accounts", "lecturer profiles", "availability rows")
    }
    if leftover:
        print()
        print(f"WARNING: some lecturer rows remain: {leftover}")
    db.close()


if __name__ == "__main__":
    main()
