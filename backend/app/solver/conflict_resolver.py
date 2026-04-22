import json
from math import ceil
from sqlalchemy.orm import Session
from app.models.timetable import TimetableConflict, TimetableEntry, TimetableEntryClass


def apply_resolution(conflict: TimetableConflict, resolution: str, db: Session) -> None:
    details = json.loads(conflict.details) if conflict.details else {}

    if resolution == "rotate_groups":
        entries = db.query(TimetableEntry).filter(
            TimetableEntry.timetable_id == conflict.timetable_id,
            TimetableEntry.course_id == conflict.course_id,
        ).all()
        group_names = [chr(65 + i) for i in range(len(entries))]
        rotation_seq = json.dumps(group_names)
        for entry in entries:
            entry.week_pattern = "rotation_group"
            entry.rotation_sequence = rotation_seq
        db.commit()

    elif resolution == "add_session":
        from app.models.timetable import Timetable
        from app.models.academic import TimeSlot, Class
        from app.models.course import Course
        from app.models.building import Building
        from app.models.room import Room

        course = db.query(Course).filter(Course.id == conflict.course_id).first()
        if not course or not course.lecturer_id:
            return

        timetable = db.query(Timetable).filter(Timetable.id == conflict.timetable_id).first()
        all_slots = db.query(TimeSlot).filter(TimeSlot.semester_id == timetable.semester_id).all()

        used_by_lecturer = {
            e.time_slot_id for e in db.query(TimetableEntry).filter(
                TimetableEntry.timetable_id == conflict.timetable_id,
                TimetableEntry.lecturer_id == course.lecturer_id,
            ).all()
        }
        used_by_class = set()
        if conflict.class_id:
            used_by_class = {
                e.time_slot_id for e in
                db.query(TimetableEntry)
                .join(TimetableEntryClass, TimetableEntryClass.entry_id == TimetableEntry.id)
                .filter(
                    TimetableEntry.timetable_id == conflict.timetable_id,
                    TimetableEntryClass.class_id == conflict.class_id,
                ).all()
            }

        blocked = used_by_lecturer | used_by_class
        free_slot = next((s for s in all_slots if s.id not in blocked), None)
        if not free_slot:
            return

        from app.models.university import Faculty, Department
        dept = db.query(Department).filter(Department.id == timetable.department_id).first()
        uni_id = dept.faculty.university_id if dept and dept.faculty else None
        if not uni_id:
            return

        lab = (
            db.query(Room)
            .join(Building, Building.id == Room.building_id)
            .filter(Building.university_id == uni_id, Room.room_type == "lab")
            .order_by(Room.capacity.desc())
            .first()
        )
        if not lab:
            return

        groups_needed = details.get("groups_needed", 2)
        sessions_available = details.get("sessions_available", 2)
        extra_groups = groups_needed - sessions_available

        total_population = 0
        if conflict.class_id:
            cls = db.query(Class).filter(Class.id == conflict.class_id).first()
            total_population = cls.population if cls else 0
        group_size = ceil(total_population / groups_needed) if groups_needed else total_population

        for _ in range(extra_groups):
            new_entry = TimetableEntry(
                timetable_id=conflict.timetable_id,
                course_id=conflict.course_id,
                lecturer_id=course.lecturer_id,
                room_id=lab.id,
                time_slot_id=free_slot.id,
                week_pattern="every_week",
                is_overcapacity=group_size > lab.capacity,
            )
            db.add(new_entry)
            db.flush()
            if conflict.class_id:
                db.add(TimetableEntryClass(entry_id=new_entry.id, class_id=conflict.class_id))
        db.commit()
