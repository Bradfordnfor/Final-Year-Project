from sqlalchemy import String, Integer, Float, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class University(Base):
    __tablename__ = "universities"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200), unique=True)
    slug: Mapped[str] = mapped_column(String(100), unique=True)
    overflow_threshold: Mapped[float] = mapped_column(Float, default=0.20)

    faculties: Mapped[list["Faculty"]] = relationship(back_populates="university")
    buildings: Mapped[list["Building"]] = relationship(back_populates="university")
    semesters: Mapped[list["Semester"]] = relationship(back_populates="university")


class Faculty(Base):
    __tablename__ = "faculties"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    code: Mapped[str] = mapped_column(String(20))
    sessions_per_week: Mapped[int] = mapped_column(Integer, default=2)
    session_duration_hours: Mapped[int] = mapped_column(Integer, default=2)
    university_id: Mapped[int] = mapped_column(ForeignKey("universities.id"))

    university: Mapped["University"] = relationship(back_populates="faculties")
    departments: Mapped[list["Department"]] = relationship(back_populates="faculty")


class Department(Base):
    __tablename__ = "departments"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    code: Mapped[str] = mapped_column(String(20))
    faculty_id: Mapped[int] = mapped_column(ForeignKey("faculties.id"))

    faculty: Mapped["Faculty"] = relationship(back_populates="departments")
    levels: Mapped[list["Level"]] = relationship(back_populates="department")
    courses: Mapped[list["Course"]] = relationship(back_populates="department")
