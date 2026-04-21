import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from app.database import SessionLocal, engine, Base
from app import models
from app.core.security import get_password_hash

Base.metadata.create_all(bind=engine)


def seed():
    db = SessionLocal()
    try:
        if db.query(models.University).first():
            print("Database already seeded — skipping.")
            return

        university = models.University(
            name="University of Buea",
            slug="ub",
            overflow_threshold=0.20,
        )
        db.add(university)
        db.flush()

        faculty = models.Faculty(
            name="Faculty of Engineering and Technology",
            code="FET",
            sessions_per_week=2,
            session_duration_hours=2,
            university_id=university.id,
        )
        db.add(faculty)
        db.flush()

        dept_ee = models.Department(
            name="Electrical Engineering", code="EE", faculty_id=faculty.id
        )
        dept_ce = models.Department(
            name="Computer Engineering", code="CE", faculty_id=faculty.id
        )
        db.add_all([dept_ee, dept_ce])
        db.flush()

        room_amp = models.Room(
            name="Amphi 750", capacity=750,
            room_type="lecture_hall", university_id=university.id,
        )
        room_lab = models.Room(
            name="EE Lab 1", capacity=30,
            room_type="lab", university_id=university.id,
        )
        db.add_all([room_amp, room_lab])
        db.flush()

        semester = models.Semester(
            name="First Semester 2025/2026",
            start_date="2025-10-06",
            end_date="2026-02-06",
            is_active=True,
            university_id=university.id,
        )
        db.add(semester)
        db.flush()

        days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        slot_times = [
            ("07:00", "09:00"), ("09:00", "11:00"),
            ("11:00", "13:00"), ("14:00", "16:00"),
        ]
        for day in days:
            for start, end in slot_times:
                db.add(models.TimeSlot(
                    day_of_week=day, start_time=start,
                    end_time=end, semester_id=semester.id,
                ))

        admin = models.User(
            email="admin@ub.cm",
            hashed_password=get_password_hash("admin123"),
            full_name="UB Admin",
            role="university_admin",
            is_active=True,
            university_id=university.id,
        )
        student_user = models.User(
            email="student@ub.cm",
            hashed_password=get_password_hash("student123"),
            full_name="Test Student",
            role="student",
            is_active=True,
            university_id=university.id,
            department_id=dept_ee.id,
        )
        db.add_all([admin, student_user])
        db.commit()
        print("Seed complete.")
        print("  Admin:   admin@ub.cm / admin123")
        print("  Student: student@ub.cm / student123")
    except Exception as e:
        db.rollback()
        raise e
    finally:
        db.close()


if __name__ == "__main__":
    seed()
