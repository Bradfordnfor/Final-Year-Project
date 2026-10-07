"""Read-only snapshot of what a course wipe would touch.

Run from the backend/ directory:
    ./venv/Scripts/python.exe scripts/inspect_db.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.database import SessionLocal
from app.models.course import Course, SharedCourse
from app.models.user import Lecturer, User
from app.models.timetable import (
    TimetableRun, TimetableEntry, TimetableConflict,
)
from app.models.university import Faculty, Department


def main():
    db = SessionLocal()

    courses = db.query(Course).count()
    dept_courses = db.query(Course).filter(Course.department_id.isnot(None)).count()
    uni_courses = db.query(Course).filter(Course.university_id.isnot(None)).count()
    shared = db.query(SharedCourse).count()

    runs = db.query(TimetableRun).count()
    entries = db.query(TimetableEntry).count()
    conflicts = db.query(TimetableConflict).count()

    lecturers = db.query(Lecturer).count()
    faculties = db.query(Faculty).count()
    departments = db.query(Department).count()

    print("=== WILL BE DELETED by the wipe ===")
    print(f"courses (total)          : {courses}")
    print(f"  - departmental         : {dept_courses}")
    print(f"  - university-wide       : {uni_courses}")
    print(f"shared_course links      : {shared}")
    print(f"timetable runs           : {runs}")
    print(f"  timetable entries      : {entries}")
    print(f"  timetable conflicts    : {conflicts}")
    print()
    print("=== WILL BE KEPT ===")
    print(f"lecturers                : {lecturers}")
    print(f"faculties                : {faculties}")
    print(f"departments              : {departments}")

    if lecturers:
        print()
        print("--- lecturers (first 60) ---")
        rows = (
            db.query(Lecturer, User, Department)
            .join(User, Lecturer.user_id == User.id)
            .join(Department, Lecturer.department_id == Department.id)
            .order_by(Department.name, User.full_name)
            .limit(60)
            .all()
        )
        for lect, u, dept in rows:
            print(f"  [{dept.name}] {u.full_name}  <{u.email}>  verified={u.is_verified}")

    db.close()


if __name__ == "__main__":
    main()
