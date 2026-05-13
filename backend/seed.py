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

        building_main = models.Building(
            name="FET Main Block",
            university_id=university.id,
        )
        db.add(building_main)
        db.flush()

        room_amp = models.Room(
            name="Amphi 750", capacity=750,
            room_type="lecture_hall", building_id=building_main.id,
        )
        room_lab = models.Room(
            name="EE Lab 1", capacity=30,
            room_type="lab", building_id=building_main.id,
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

        super_admin = models.User(
            email="superadmin@ub.cm",
            hashed_password=get_password_hash("super123"),
            full_name="Super Admin",
            role="super_admin",
            is_active=True,
            university_id=university.id,
        )
        admin = models.User(
            email="admin@ub.cm",
            hashed_password=get_password_hash("admin123"),
            full_name="UB Admin",
            role="university_admin",
            is_active=True,
            university_id=university.id,
        )
        fet_head = models.User(
            email="fethead@ub.cm",
            hashed_password=get_password_hash("fethead123"),
            full_name="FET Faculty Head",
            role="faculty_head",
            is_active=True,
            university_id=university.id,
            faculty_id=faculty.id,
        )
        officer = models.User(
            email="officer@ub.cm",
            hashed_password=get_password_hash("officer123"),
            full_name="Timetable Officer",
            role="timetable_officer",
            is_active=True,
            university_id=university.id,
            faculty_id=faculty.id,
        )
        lecturer = models.User(
            email="lecturer@ub.cm",
            hashed_password=get_password_hash("lecturer123"),
            full_name="Dr. Test Lecturer",
            role="lecturer",
            is_active=True,
            university_id=university.id,
            department_id=dept_ee.id,
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
        db.add_all([super_admin, admin, fet_head, officer, lecturer, student_user])
        db.commit()
        print("Seed complete.")
        print("  Super Admin:  superadmin@ub.cm / super123")
        print("  Admin:        admin@ub.cm / admin123")
        print("  FET Head:     fethead@ub.cm / fethead123")
        print("  Officer:      officer@ub.cm / officer123")
        print("  Lecturer:     lecturer@ub.cm / lecturer123")
        print("  Student:      student@ub.cm / student123")
    except Exception as e:
        db.rollback()
        raise e
    finally:
        db.close()


if __name__ == "__main__":
    seed()
