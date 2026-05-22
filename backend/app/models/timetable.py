# backend/app/models/timetable.py
from datetime import datetime
from typing import Optional
from sqlalchemy import String, Integer, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class TimetableRun(Base):
    __tablename__ = "timetable_runs"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    status: Mapped[str] = mapped_column(String(20), default="draft")
    # draft | under_review | approved | published
    semester_id: Mapped[int] = mapped_column(ForeignKey("semesters.id"))
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    generated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    semester: Mapped["Semester"] = relationship()
    creator: Mapped["User"] = relationship()
    faculties: Mapped[list["TimetableRunFaculty"]] = relationship(
        back_populates="run", cascade="all, delete-orphan"
    )
    buildings: Mapped[list["TimetableRunBuilding"]] = relationship(
        back_populates="run", cascade="all, delete-orphan"
    )
    entries: Mapped[list["TimetableEntry"]] = relationship(
        back_populates="run", cascade="all, delete-orphan"
    )
    conflicts: Mapped[list["TimetableConflict"]] = relationship(
        back_populates="run", cascade="all, delete-orphan"
    )
    jobs: Mapped[list["GenerationJob"]] = relationship(
        back_populates="run", cascade="all, delete-orphan"
    )
    approvals: Mapped[list["FacultyHeadApproval"]] = relationship(
        back_populates="run", cascade="all, delete-orphan"
    )


class TimetableRunFaculty(Base):
    __tablename__ = "timetable_run_faculties"

    id: Mapped[int] = mapped_column(primary_key=True)
    run_id: Mapped[int] = mapped_column(ForeignKey("timetable_runs.id"))
    faculty_id: Mapped[int] = mapped_column(ForeignKey("faculties.id"))

    run: Mapped["TimetableRun"] = relationship(back_populates="faculties")
    faculty: Mapped["Faculty"] = relationship()


class TimetableRunBuilding(Base):
    __tablename__ = "timetable_run_buildings"

    id: Mapped[int] = mapped_column(primary_key=True)
    run_id: Mapped[int] = mapped_column(ForeignKey("timetable_runs.id"))
    building_id: Mapped[int] = mapped_column(ForeignKey("buildings.id"))

    run: Mapped["TimetableRun"] = relationship(back_populates="buildings")
    building: Mapped["Building"] = relationship()


class TimetableEntry(Base):
    __tablename__ = "timetable_entries"

    id: Mapped[int] = mapped_column(primary_key=True)
    run_id: Mapped[int] = mapped_column(ForeignKey("timetable_runs.id"))
    course_id: Mapped[int] = mapped_column(ForeignKey("courses.id"))
    lecturer_id: Mapped[int] = mapped_column(ForeignKey("lecturers.id"))
    room_id: Mapped[int] = mapped_column(ForeignKey("rooms.id"))
    time_slot_id: Mapped[int] = mapped_column(ForeignKey("time_slots.id"))
    group_id: Mapped[Optional[int]] = mapped_column(ForeignKey("class_groups.id"), nullable=True)
    week_pattern: Mapped[str] = mapped_column(String(20), default="every_week")
    rotation_sequence: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    is_overcapacity: Mapped[bool] = mapped_column(Boolean, default=False)
    is_merged: Mapped[bool] = mapped_column(Boolean, default=False)

    run: Mapped["TimetableRun"] = relationship(back_populates="entries")
    course: Mapped["Course"] = relationship()
    lecturer: Mapped["Lecturer"] = relationship()
    room: Mapped["Room"] = relationship()
    time_slot: Mapped["TimeSlot"] = relationship()
    group: Mapped[Optional["ClassGroup"]] = relationship()
    entry_classes: Mapped[list["TimetableEntryClass"]] = relationship(
        back_populates="entry", cascade="all, delete-orphan"
    )


class TimetableEntryClass(Base):
    __tablename__ = "timetable_entry_classes"

    id: Mapped[int] = mapped_column(primary_key=True)
    entry_id: Mapped[int] = mapped_column(ForeignKey("timetable_entries.id"))
    class_id: Mapped[int] = mapped_column(ForeignKey("classes.id"))

    entry: Mapped["TimetableEntry"] = relationship(back_populates="entry_classes")
    student_class: Mapped["Class"] = relationship()


class TimetableConflict(Base):
    __tablename__ = "timetable_conflicts"

    id: Mapped[int] = mapped_column(primary_key=True)
    run_id: Mapped[int] = mapped_column(ForeignKey("timetable_runs.id"))
    conflict_type: Mapped[str] = mapped_column(String(50))
    course_id: Mapped[Optional[int]] = mapped_column(ForeignKey("courses.id"), nullable=True)
    class_id: Mapped[Optional[int]] = mapped_column(ForeignKey("classes.id"), nullable=True)
    details: Mapped[str] = mapped_column(Text, default="{}")
    resolved: Mapped[bool] = mapped_column(Boolean, default=False)
    resolution: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)

    run: Mapped["TimetableRun"] = relationship(back_populates="conflicts")
    course: Mapped[Optional["Course"]] = relationship()
    student_class: Mapped[Optional["Class"]] = relationship()


class GenerationJob(Base):
    __tablename__ = "generation_jobs"

    id: Mapped[int] = mapped_column(primary_key=True)
    run_id: Mapped[int] = mapped_column(ForeignKey("timetable_runs.id"))
    status: Mapped[str] = mapped_column(String(20), default="pending")
    error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    started_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

    run: Mapped["TimetableRun"] = relationship(back_populates="jobs")


class FacultyHeadApproval(Base):
    __tablename__ = "faculty_head_approvals"

    id: Mapped[int] = mapped_column(primary_key=True)
    run_id: Mapped[int] = mapped_column(ForeignKey("timetable_runs.id"))
    faculty_id: Mapped[int] = mapped_column(ForeignKey("faculties.id"))
    faculty_head_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    status: Mapped[str] = mapped_column(String(20), default="pending")
    # pending | approved | rejected
    comment: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    decided_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

    run: Mapped["TimetableRun"] = relationship(back_populates="approvals")
    faculty: Mapped["Faculty"] = relationship()
    faculty_head: Mapped["User"] = relationship()


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    message: Mapped[str] = mapped_column(String(500))
    notification_type: Mapped[str] = mapped_column(String(50))
    # timetable_published | slot_changed | conflict_flagged | generation_complete
    # timetable_review | timetable_approved | timetable_rejected
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    user: Mapped["User"] = relationship()
