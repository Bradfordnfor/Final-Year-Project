from typing import Optional
from sqlalchemy import String, Integer, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class Course(Base):
    __tablename__ = "courses"

    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(String(20))
    name: Mapped[str] = mapped_column(String(200))
    room_type_required: Mapped[str] = mapped_column(String(20), default="lecture_hall")
    # lecture_hall | lab | studio
    level_id: Mapped[Optional[int]] = mapped_column(ForeignKey("levels.id"), nullable=True)
    department_id: Mapped[Optional[int]] = mapped_column(ForeignKey("departments.id"), nullable=True)
    university_id: Mapped[Optional[int]] = mapped_column(ForeignKey("universities.id"), nullable=True)
    # university_id is set for university-wide courses (no department)
    lecturer_id: Mapped[Optional[int]] = mapped_column(ForeignKey("lecturers.id"), nullable=True)
    weekly_hours: Mapped[int] = mapped_column(Integer, default=2)
    semester: Mapped[int] = mapped_column(Integer, default=1)
    # which semester of study this course runs in: 1 = first, 2 = second, 0 = both (year-long)

    level: Mapped[Optional["Level"]] = relationship()
    department: Mapped[Optional["Department"]] = relationship(back_populates="courses")
    university: Mapped[Optional["University"]] = relationship()
    lecturer: Mapped[Optional["Lecturer"]] = relationship()
    shared_with: Mapped[list["SharedCourse"]] = relationship(
        back_populates="course", cascade="all, delete-orphan"
    )


class SharedCourse(Base):
    __tablename__ = "shared_courses"

    id: Mapped[int] = mapped_column(primary_key=True)
    course_id: Mapped[int] = mapped_column(ForeignKey("courses.id"))
    class_id: Mapped[int] = mapped_column(ForeignKey("classes.id"))

    course: Mapped["Course"] = relationship(back_populates="shared_with")
    student_class: Mapped["Class"] = relationship()
