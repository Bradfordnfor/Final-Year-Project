from typing import Optional
from sqlalchemy import String, Integer, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class Course(Base):
    __tablename__ = "courses"

    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(String(20))
    # Formal academic code e.g. "ENG 116", "CSC 201"
    name: Mapped[str] = mapped_column(String(200))
    room_type_required: Mapped[str] = mapped_column(String(20), default="lecture_hall")
    # lecture_hall | lab | studio
    department_id: Mapped[int] = mapped_column(ForeignKey("departments.id"))
    lecturer_id: Mapped[Optional[int]] = mapped_column(ForeignKey("lecturers.id"), nullable=True)

    department: Mapped["Department"] = relationship(back_populates="courses")
    lecturer: Mapped[Optional["Lecturer"]] = relationship()
    shared_with: Mapped[list["SharedCourse"]] = relationship(
        back_populates="course", cascade="all, delete-orphan"
    )


class SharedCourse(Base):
    """Records that a course is shared between multiple classes."""
    __tablename__ = "shared_courses"

    id: Mapped[int] = mapped_column(primary_key=True)
    course_id: Mapped[int] = mapped_column(ForeignKey("courses.id"))
    class_id: Mapped[int] = mapped_column(ForeignKey("classes.id"))

    course: Mapped["Course"] = relationship(back_populates="shared_with")
    student_class: Mapped["Class"] = relationship()
