from datetime import datetime
from typing import Optional
from sqlalchemy import String, Integer, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class Timetable(Base):
    __tablename__ = "timetables"

    id: Mapped[int] = mapped_column(primary_key=True)
    status: Mapped[str] = mapped_column(String(20), default="draft")
    # draft | under_review | approved | published
    semester_id: Mapped[int] = mapped_column(ForeignKey("semesters.id"))
    department_id: Mapped[int] = mapped_column(ForeignKey("departments.id"))
    generated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    semester: Mapped["Semester"] = relationship()
    department: Mapped["Department"] = relationship()
    entries: Mapped[list["TimetableEntry"]] = relationship(
        back_populates="timetable", cascade="all, delete-orphan"
    )
    conflicts: Mapped[list["TimetableConflict"]] = relationship(
        back_populates="timetable", cascade="all, delete-orphan"
    )
    jobs: Mapped[list["GenerationJob"]] = relationship(
        back_populates="timetable", cascade="all, delete-orphan"
    )


class TimetableEntry(Base):
    __tablename__ = "timetable_entries"

    id: Mapped[int] = mapped_column(primary_key=True)
    timetable_id: Mapped[int] = mapped_column(ForeignKey("timetables.id"))
    course_id: Mapped[int] = mapped_column(ForeignKey("courses.id"))
    lecturer_id: Mapped[int] = mapped_column(ForeignKey("lecturers.id"))
    room_id: Mapped[int] = mapped_column(ForeignKey("rooms.id"))
    time_slot_id: Mapped[int] = mapped_column(ForeignKey("time_slots.id"))
    group_id: Mapped[Optional[int]] = mapped_column(ForeignKey("class_groups.id"), nullable=True)
    week_pattern: Mapped[str] = mapped_column(String(20), default="every_week")
    # every_week | odd_weeks | even_weeks | rotation_group
    rotation_sequence: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    # JSON array string e.g. '["A","B","C"]' — group rotation order
    is_overcapacity: Mapped[bool] = mapped_column(Boolean, default=False)
    is_merged: Mapped[bool] = mapped_column(Boolean, default=False)

    timetable: Mapped["Timetable"] = relationship(back_populates="entries")
    course: Mapped["Course"] = relationship()
    lecturer: Mapped["Lecturer"] = relationship()
    room: Mapped["Room"] = relationship()
    time_slot: Mapped["TimeSlot"] = relationship()
    group: Mapped[Optional["ClassGroup"]] = relationship()
    entry_classes: Mapped[list["TimetableEntryClass"]] = relationship(
        back_populates="entry", cascade="all, delete-orphan"
    )


class TimetableEntryClass(Base):
    """Junction: one TimetableEntry can cover multiple Classes (merged sessions)."""
    __tablename__ = "timetable_entry_classes"

    id: Mapped[int] = mapped_column(primary_key=True)
    entry_id: Mapped[int] = mapped_column(ForeignKey("timetable_entries.id"))
    class_id: Mapped[int] = mapped_column(ForeignKey("classes.id"))

    entry: Mapped["TimetableEntry"] = relationship(back_populates="entry_classes")
    student_class: Mapped["Class"] = relationship()


class TimetableConflict(Base):
    __tablename__ = "timetable_conflicts"

    id: Mapped[int] = mapped_column(primary_key=True)
    timetable_id: Mapped[int] = mapped_column(ForeignKey("timetables.id"))
    conflict_type: Mapped[str] = mapped_column(String(50))
    # lab_split_conflict | no_room_available | solver_infeasible
    course_id: Mapped[Optional[int]] = mapped_column(ForeignKey("courses.id"), nullable=True)
    class_id: Mapped[Optional[int]] = mapped_column(ForeignKey("classes.id"), nullable=True)
    details: Mapped[str] = mapped_column(Text, default="{}")
    resolved: Mapped[bool] = mapped_column(Boolean, default=False)
    resolution: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    # add_session | rotate_groups

    timetable: Mapped["Timetable"] = relationship(back_populates="conflicts")
    course: Mapped[Optional["Course"]] = relationship()
    student_class: Mapped[Optional["Class"]] = relationship()


class GenerationJob(Base):
    __tablename__ = "generation_jobs"

    id: Mapped[int] = mapped_column(primary_key=True)
    timetable_id: Mapped[int] = mapped_column(ForeignKey("timetables.id"))
    status: Mapped[str] = mapped_column(String(20), default="pending")
    # pending | running | completed | failed
    error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    started_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

    timetable: Mapped["Timetable"] = relationship(back_populates="jobs")


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    message: Mapped[str] = mapped_column(String(500))
    notification_type: Mapped[str] = mapped_column(String(50))
    # timetable_published | slot_changed | conflict_flagged | generation_complete
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    user: Mapped["User"] = relationship()
