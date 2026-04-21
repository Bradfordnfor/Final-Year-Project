from typing import Optional
from sqlalchemy import String, Boolean, Integer, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(200), unique=True)
    hashed_password: Mapped[str] = mapped_column(String(200))
    full_name: Mapped[str] = mapped_column(String(200))
    role: Mapped[str] = mapped_column(String(30))
    # super_admin | university_admin | department_head | timetable_officer | lecturer | student
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    university_id: Mapped[Optional[int]] = mapped_column(ForeignKey("universities.id"), nullable=True)
    department_id: Mapped[Optional[int]] = mapped_column(ForeignKey("departments.id"), nullable=True)

    lecturer: Mapped[Optional["Lecturer"]] = relationship(back_populates="user", uselist=False)
    student: Mapped[Optional["Student"]] = relationship(back_populates="user", uselist=False)


class Lecturer(Base):
    __tablename__ = "lecturers"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True)
    department_id: Mapped[int] = mapped_column(ForeignKey("departments.id"))

    user: Mapped["User"] = relationship(back_populates="lecturer")
    availability: Mapped[list["LecturerAvailability"]] = relationship(
        back_populates="lecturer", cascade="all, delete-orphan"
    )


class LecturerAvailability(Base):
    __tablename__ = "lecturer_availability"

    id: Mapped[int] = mapped_column(primary_key=True)
    lecturer_id: Mapped[int] = mapped_column(ForeignKey("lecturers.id"))
    time_slot_id: Mapped[int] = mapped_column(ForeignKey("time_slots.id"))

    lecturer: Mapped["Lecturer"] = relationship(back_populates="availability")


class Student(Base):
    __tablename__ = "students"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True)
    class_id: Mapped[Optional[int]] = mapped_column(ForeignKey("classes.id"), nullable=True)
    group_id: Mapped[Optional[int]] = mapped_column(ForeignKey("class_groups.id"), nullable=True)

    user: Mapped["User"] = relationship(back_populates="student")
