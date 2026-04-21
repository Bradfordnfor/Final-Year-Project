from sqlalchemy import String, Integer, Boolean, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class Semester(Base):
    __tablename__ = "semesters"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100))
    start_date: Mapped[str] = mapped_column(String(20))
    end_date: Mapped[str] = mapped_column(String(20))
    is_active: Mapped[bool] = mapped_column(Boolean, default=False)
    university_id: Mapped[int] = mapped_column(ForeignKey("universities.id"))

    university: Mapped["University"] = relationship(back_populates="semesters")
    time_slots: Mapped[list["TimeSlot"]] = relationship(back_populates="semester")


class TimeSlot(Base):
    __tablename__ = "time_slots"

    id: Mapped[int] = mapped_column(primary_key=True)
    day_of_week: Mapped[str] = mapped_column(String(20))
    start_time: Mapped[str] = mapped_column(String(10))
    end_time: Mapped[str] = mapped_column(String(10))
    semester_id: Mapped[int] = mapped_column(ForeignKey("semesters.id"))

    semester: Mapped["Semester"] = relationship(back_populates="time_slots")


class Level(Base):
    __tablename__ = "levels"

    id: Mapped[int] = mapped_column(primary_key=True)
    number: Mapped[int] = mapped_column(Integer)
    # e.g. 100, 200, 300, 400, 500
    department_id: Mapped[int] = mapped_column(ForeignKey("departments.id"))

    department: Mapped["Department"] = relationship(back_populates="levels")
    classes: Mapped[list["Class"]] = relationship(back_populates="level")


class Class(Base):
    __tablename__ = "classes"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(50))
    # e.g. "EE300", "CE300"
    population: Mapped[int] = mapped_column(Integer, default=0)
    level_id: Mapped[int] = mapped_column(ForeignKey("levels.id"))

    level: Mapped["Level"] = relationship(back_populates="classes")
    groups: Mapped[list["ClassGroup"]] = relationship(back_populates="student_class")


class ClassGroup(Base):
    __tablename__ = "class_groups"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(10))
    # e.g. "A", "B", "C"
    size: Mapped[int] = mapped_column(Integer, default=0)
    class_id: Mapped[int] = mapped_column(ForeignKey("classes.id"))

    student_class: Mapped["Class"] = relationship(back_populates="groups")
