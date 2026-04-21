# Timetable Generation Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the constraint-solver engine that auto-generates clash-free timetables, handles shared courses (merge/split), lab group splits, overcapacity warnings, conflict resolution (add session / weekly rotation), and the timetable status workflow (draft → published).

**Architecture:** The solver runs as a FastAPI BackgroundTask. A `Preprocessor` converts database entities into `ScheduleSession` objects, feeds them to an OR-Tools CP-SAT model, and a `Postprocessor` converts the solver output into `TimetableEntry` database rows. Conflicts that need head resolution are stored as `TimetableConflict` rows and exposed via a resolution endpoint.

**Tech Stack:** OR-Tools 9.10 (CP-SAT solver), FastAPI BackgroundTasks, SQLAlchemy 2.0, ReportLab (PDF export), Python csv (CSV export)

> **Note:** This is Plan 2 of 3. Requires Plan 1 (Backend Foundation) to be fully implemented first.

> **Git workflow:** Plan 2 lives on the **`backend` branch** — same branch as Plan 1. It adds Python files to the same `backend/` directory and the same FastAPI app. No new branch needed. Commit steps in this plan are **proposals only** — I will tell you when it's a good time to commit and suggest the message. You run `git add` and `git commit` yourself.

---

## File Structure

```
backend/
├── app/
│   ├── models/
│   │   └── timetable.py              # Timetable, TimetableEntry, TimetableEntryClass,
│   │                                 # TimetableConflict, GenerationJob, Notification
│   ├── schemas/
│   │   └── timetable.py              # Pydantic schemas for all timetable entities
│   ├── routers/
│   │   └── timetable.py              # CRUD + generate + approve + export endpoints
│   └── solver/
│       ├── __init__.py
│       ├── models.py                 # ScheduleSession, SolverInput, SolverResult dataclasses
│       ├── preprocessor.py           # DB → ScheduleSession conversion, merge + split logic
│       ├── solver.py                 # OR-Tools CP-SAT model and constraint definitions
│       ├── postprocessor.py          # SolverResult → TimetableEntry DB rows
│       └── conflict_resolver.py     # Head resolution: add_session, rotate_groups
├── tests/
│   ├── test_timetable_api.py         # API endpoint tests
│   ├── test_preprocessor.py          # Unit tests for merge + lab split logic
│   └── test_solver.py                # Integration tests for the solver
└── requirements.txt                  # Add ortools, reportlab
```

---

## Task 1: Add OR-Tools & ReportLab to Dependencies

**Files:**
- Modify: `backend/requirements.txt`

- [ ] **Step 1: Add new packages to `requirements.txt`**

```
fastapi==0.115.0
uvicorn[standard]==0.30.6
sqlalchemy==2.0.35
alembic==1.13.3
psycopg2-binary==2.9.9
pydantic==2.8.2
pydantic-settings==2.5.2
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-multipart==0.0.12
httpx==0.27.2
pytest==8.3.3
pytest-asyncio==0.24.0
ortools==9.10.4067
reportlab==4.2.2
```

- [ ] **Step 2: Install new packages**

```bash
cd backend
source venv/Scripts/activate
pip install ortools==9.10.4067 reportlab==4.2.2
```

Expected: both packages install without errors.

- [ ] **Step 3: Verify OR-Tools works**

```bash
python -c "from ortools.sat.python import cp_model; print('OR-Tools OK')"
```

Expected output: `OR-Tools OK`

- [ ] **Step 4: Commit checkpoint**

> **Suggested commit message:** "feat: add OR-Tools and ReportLab dependencies"

```bash
git add backend/requirements.txt
```

---

## Task 2: Timetable Database Models

**Files:**
- Create: `backend/app/models/timetable.py`
- Modify: `backend/app/models/__init__.py`

- [ ] **Step 1: Create `app/models/timetable.py`**

```python
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
    """Junction table: one TimetableEntry can cover multiple Classes (merged sessions)."""
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
    # JSON: {"groups_needed": 3, "sessions_available": 2}
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
```

- [ ] **Step 2: Update `app/models/__init__.py`**

```python
from app.models.university import University, Faculty, Department
from app.models.room import Room
from app.models.academic import Level, Class, ClassGroup, Semester, TimeSlot
from app.models.user import User, Lecturer, Student, LecturerAvailability
from app.models.course import Course, SharedCourse
from app.models.timetable import (
    Timetable, TimetableEntry, TimetableEntryClass,
    TimetableConflict, GenerationJob, Notification,
)
```

- [ ] **Step 3: Generate and apply the migration**

```bash
cd backend
source venv/Scripts/activate
alembic revision --autogenerate -m "add timetable models"
alembic upgrade head
```

Expected: migration file created and applied without errors.

- [ ] **Step 4: Commit checkpoint**

> **Suggested commit message:** "feat: add Timetable, TimetableEntry, Conflict, GenerationJob, Notification models"

```bash
git add backend/app/models/timetable.py backend/app/models/__init__.py backend/alembic/versions/
```

---

## Task 3: Solver Data Classes

**Files:**
- Create: `backend/app/solver/__init__.py`
- Create: `backend/app/solver/models.py`

- [ ] **Step 1: Create `app/solver/__init__.py`** (empty)

```python
```

- [ ] **Step 2: Create `app/solver/models.py`**

```python
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class ScheduleSession:
    """One meeting to schedule (one course session for one week)."""
    id: str                        # unique key e.g. "course_5_class_3_session_1"
    course_id: int
    course_code: str
    lecturer_id: int
    room_type_required: str        # lecture_hall | lab | studio
    class_ids: list[int]           # which classes attend this session
    population: int                # total headcount for room assignment
    session_number: int            # 1st or 2nd session of the week for this course
    group_id: Optional[int] = None # set when this session is for a lab group
    is_merged: bool = False        # True when multiple classes share one session


@dataclass
class ConflictFlag:
    """A problem found during preprocessing that needs head resolution."""
    conflict_type: str             # lab_split_conflict | no_room_available
    course_id: int
    class_id: Optional[int] = None
    groups_needed: int = 0
    sessions_available: int = 0
    details: str = ""


@dataclass
class SolverInput:
    sessions: list[ScheduleSession]
    time_slots: list[dict]         # [{"id": 1, "day": "Monday", "start": "07:00", "end": "09:00"}]
    rooms: list[dict]              # [{"id": 1, "capacity": 700, "room_type": "lecture_hall"}]
    lecturer_unavailability: dict[int, list[int]]  # lecturer_id -> [timeslot_ids]


@dataclass
class SolverAssignment:
    session: ScheduleSession
    time_slot_id: int
    room_id: int
    is_overcapacity: bool = False


@dataclass
class SolverResult:
    assignments: list[SolverAssignment]
    solve_time_seconds: float
    status: str                    # optimal | feasible | infeasible | unknown
```

- [ ] **Step 3: Commit checkpoint**

> **Suggested commit message:** "feat: add solver data classes"

```bash
git add backend/app/solver/
```

---

## Task 4: Preprocessor — Merge Decision & Lab Split

**Files:**
- Create: `backend/app/solver/preprocessor.py`
- Create: `backend/tests/test_preprocessor.py`

- [ ] **Step 1: Write `tests/test_preprocessor.py`**

```python
from app.solver.models import ScheduleSession, ConflictFlag
from app.solver.preprocessor import compute_merge_decision, compute_lab_split


def make_class(id_, population):
    return {"id": id_, "population": population}


def make_room(id_, capacity, room_type="lecture_hall"):
    return {"id": id_, "capacity": capacity, "room_type": room_type}


def make_course(id_, room_type="lecture_hall"):
    return {"id": id_, "code": f"C{id_}", "room_type_required": room_type}


# --- Merge decision tests ---

def test_merge_when_combined_fits_in_room():
    course = make_course(1)
    classes = [make_class(1, 60), make_class(2, 50)]  # combined = 110
    rooms = [make_room(1, 120)]  # fits
    sessions, conflict = compute_merge_decision(
        course=course, classes=classes, rooms=rooms,
        lecturer_id=10, sessions_per_week=2, overflow_threshold=0.20
    )
    assert conflict is None
    assert len(sessions) == 2  # 2 sessions per week, merged
    assert sessions[0].is_merged is True
    assert sessions[0].population == 110
    assert set(sessions[0].class_ids) == {1, 2}


def test_separate_when_combined_too_large():
    course = make_course(1)
    classes = [make_class(1, 200), make_class(2, 200)]  # combined = 400
    rooms = [make_room(1, 300)]  # doesn't fit even with overflow
    sessions, conflict = compute_merge_decision(
        course=course, classes=classes, rooms=rooms,
        lecturer_id=10, sessions_per_week=2, overflow_threshold=0.20
    )
    assert conflict is None
    # Each class gets its own sessions
    assert len(sessions) == 4  # 2 classes × 2 sessions each
    assert all(not s.is_merged for s in sessions)
    assert all(len(s.class_ids) == 1 for s in sessions)


def test_single_class_no_merge_needed():
    course = make_course(1)
    classes = [make_class(1, 80)]
    rooms = [make_room(1, 100)]
    sessions, conflict = compute_merge_decision(
        course=course, classes=classes, rooms=rooms,
        lecturer_id=5, sessions_per_week=2, overflow_threshold=0.20
    )
    assert conflict is None
    assert len(sessions) == 2  # 2 sessions, not merged
    assert sessions[0].is_merged is False


# --- Lab split tests ---

def test_no_split_when_population_fits():
    course = make_course(1, room_type="lab")
    student_class = make_class(1, 30)
    labs = [make_room(1, 40, "lab")]
    sessions, conflict = compute_lab_split(
        course=course, student_class=student_class,
        labs=labs, sessions_per_week=2, lecturer_id=7
    )
    assert conflict is None
    assert len(sessions) == 2
    assert sessions[0].group_id is None


def test_split_when_population_exceeds_lab():
    course = make_course(1, room_type="lab")
    student_class = make_class(1, 80)
    labs = [make_room(1, 40, "lab")]  # needs 2 groups
    sessions, conflict = compute_lab_split(
        course=course, student_class=student_class,
        labs=labs, sessions_per_week=2, lecturer_id=7
    )
    assert conflict is None
    assert len(sessions) == 2  # 2 groups, 1 session each
    assert all(s.population <= 40 for s in sessions)
    assert sessions[0].session_number != sessions[1].session_number


def test_flag_when_groups_exceed_sessions():
    course = make_course(1, room_type="lab")
    student_class = make_class(1, 130)
    labs = [make_room(1, 40, "lab")]  # needs 4 groups but only 2 sessions
    sessions, conflict = compute_lab_split(
        course=course, student_class=student_class,
        labs=labs, sessions_per_week=2, lecturer_id=7
    )
    assert len(sessions) == 0
    assert conflict is not None
    assert conflict.conflict_type == "lab_split_conflict"
    assert conflict.groups_needed == 4
    assert conflict.sessions_available == 2


def test_no_labs_available():
    course = make_course(1, room_type="lab")
    student_class = make_class(1, 50)
    labs = []
    sessions, conflict = compute_lab_split(
        course=course, student_class=student_class,
        labs=labs, sessions_per_week=2, lecturer_id=7
    )
    assert len(sessions) == 0
    assert conflict is not None
    assert conflict.conflict_type == "no_room_available"
```

- [ ] **Step 2: Run to confirm failures**

```bash
cd backend
pytest tests/test_preprocessor.py -v
```

Expected: `ImportError` — module doesn't exist yet.

- [ ] **Step 3: Create `app/solver/preprocessor.py`**

```python
from math import ceil
from typing import Optional
from app.solver.models import ScheduleSession, ConflictFlag


def compute_merge_decision(
    course: dict,
    classes: list[dict],
    rooms: list[dict],
    lecturer_id: int,
    sessions_per_week: int,
    overflow_threshold: float,
) -> tuple[list[ScheduleSession], Optional[ConflictFlag]]:
    """
    Decide whether to merge classes sharing a course into one session
    or schedule them separately.
    Returns (sessions, conflict). conflict is None when no problem.
    """
    if len(classes) <= 1:
        # No merge decision needed — single class
        return _make_sessions(course, classes[0], lecturer_id, sessions_per_week, is_merged=False), None

    compatible_rooms = [r for r in rooms if r["room_type"] == course["room_type_required"]]
    if not compatible_rooms:
        sessions = []
        for cls in classes:
            sessions.extend(_make_sessions(course, cls, lecturer_id, sessions_per_week))
        return sessions, None

    largest_capacity = max(r["capacity"] for r in compatible_rooms)
    combined_population = sum(c["population"] for c in classes)
    merge_threshold = largest_capacity * (1 + overflow_threshold)

    if combined_population <= merge_threshold:
        # Merge: all classes attend the same session
        sessions = []
        for session_num in range(1, sessions_per_week + 1):
            sessions.append(ScheduleSession(
                id=f"course_{course['id']}_merged_session_{session_num}",
                course_id=course["id"],
                course_code=course["code"],
                lecturer_id=lecturer_id,
                room_type_required=course["room_type_required"],
                class_ids=[c["id"] for c in classes],
                population=combined_population,
                session_number=session_num,
                is_merged=True,
            ))
        return sessions, None
    else:
        # Separate: each class gets its own sessions
        sessions = []
        for cls in classes:
            sessions.extend(_make_sessions(course, cls, lecturer_id, sessions_per_week))
        return sessions, None


def compute_lab_split(
    course: dict,
    student_class: dict,
    labs: list[dict],
    sessions_per_week: int,
    lecturer_id: int,
) -> tuple[list[ScheduleSession], Optional[ConflictFlag]]:
    """
    Determine how to split a lab course where population > lab capacity.
    Returns (sessions, conflict). conflict is None when scheduling is possible.
    """
    if not labs:
        return [], ConflictFlag(
            conflict_type="no_room_available",
            course_id=course["id"],
            class_id=student_class["id"],
            details=f"No lab rooms exist for course {course['code']}",
        )

    largest_lab = max(labs, key=lambda r: r["capacity"])
    population = student_class["population"]

    if population <= largest_lab["capacity"]:
        # No split needed
        return _make_sessions(course, student_class, lecturer_id, sessions_per_week), None

    groups_needed = ceil(population / largest_lab["capacity"])

    if groups_needed > sessions_per_week:
        return [], ConflictFlag(
            conflict_type="lab_split_conflict",
            course_id=course["id"],
            class_id=student_class["id"],
            groups_needed=groups_needed,
            sessions_available=sessions_per_week,
            details=(
                f"{course['code']}: {population} students need {groups_needed} groups "
                f"but only {sessions_per_week} sessions/week available."
            ),
        )

    # Create one session per group, evenly distributed
    group_size = ceil(population / groups_needed)
    sessions = []
    for i in range(groups_needed):
        actual_size = min(group_size, population - i * group_size)
        if actual_size <= 0:
            break
        sessions.append(ScheduleSession(
            id=f"course_{course['id']}_class_{student_class['id']}_group_{i + 1}",
            course_id=course["id"],
            course_code=course["code"],
            lecturer_id=lecturer_id,
            room_type_required="lab",
            class_ids=[student_class["id"]],
            population=actual_size,
            session_number=i + 1,
        ))
    return sessions, None


def _make_sessions(
    course: dict,
    student_class: dict,
    lecturer_id: int,
    sessions_per_week: int,
    is_merged: bool = False,
) -> list[ScheduleSession]:
    return [
        ScheduleSession(
            id=f"course_{course['id']}_class_{student_class['id']}_session_{n}",
            course_id=course["id"],
            course_code=course["code"],
            lecturer_id=lecturer_id,
            room_type_required=course["room_type_required"],
            class_ids=[student_class["id"]],
            population=student_class["population"],
            session_number=n,
            is_merged=is_merged,
        )
        for n in range(1, sessions_per_week + 1)
    ]
```

- [ ] **Step 4: Run tests**

```bash
pytest tests/test_preprocessor.py -v
```

Expected: all 7 tests pass.

- [ ] **Step 5: Commit checkpoint**

> **Suggested commit message:** "feat: add preprocessor with merge decision and lab split logic"

```bash
git add backend/app/solver/preprocessor.py backend/tests/test_preprocessor.py
```

---

## Task 5: OR-Tools Constraint Solver

**Files:**
- Create: `backend/app/solver/solver.py`
- Create: `backend/tests/test_solver.py`

- [ ] **Step 1: Write `tests/test_solver.py`**

```python
from app.solver.models import ScheduleSession, SolverInput
from app.solver.solver import solve_timetable


def make_session(id_, course_id, lecturer_id, class_ids, population, session_num=1, room_type="lecture_hall"):
    return ScheduleSession(
        id=id_, course_id=course_id, course_code=f"C{course_id}",
        lecturer_id=lecturer_id, room_type_required=room_type,
        class_ids=class_ids, population=population, session_number=session_num,
    )


def make_slot(id_, day, start="07:00", end="09:00"):
    return {"id": id_, "day": day, "start": start, "end": end}


def make_room(id_, capacity, room_type="lecture_hall"):
    return {"id": id_, "capacity": capacity, "room_type": room_type}


def test_simple_two_session_schedule():
    sessions = [
        make_session("s1", course_id=1, lecturer_id=1, class_ids=[1], population=50),
        make_session("s2", course_id=2, lecturer_id=2, class_ids=[2], population=40),
    ]
    slots = [make_slot(1, "Monday"), make_slot(2, "Wednesday")]
    rooms = [make_room(1, 100), make_room(2, 60)]
    result = solve_timetable(SolverInput(
        sessions=sessions, time_slots=slots, rooms=rooms,
        lecturer_unavailability={},
    ))
    assert result.status in ("optimal", "feasible")
    assert len(result.assignments) == 2
    # No two sessions share the same room and timeslot
    slot_room_pairs = [(a.time_slot_id, a.room_id) for a in result.assignments]
    assert len(slot_room_pairs) == len(set(slot_room_pairs))


def test_no_lecturer_double_booking():
    # Same lecturer teaching two courses — must be in different slots
    sessions = [
        make_session("s1", course_id=1, lecturer_id=99, class_ids=[1], population=30),
        make_session("s2", course_id=2, lecturer_id=99, class_ids=[2], population=30),
    ]
    slots = [make_slot(1, "Monday"), make_slot(2, "Tuesday")]
    rooms = [make_room(1, 50), make_room(2, 50)]
    result = solve_timetable(SolverInput(
        sessions=sessions, time_slots=slots, rooms=rooms,
        lecturer_unavailability={},
    ))
    assert result.status in ("optimal", "feasible")
    slot_ids = [a.time_slot_id for a in result.assignments]
    assert slot_ids[0] != slot_ids[1]  # different slots


def test_no_class_double_booking():
    # Same class has two courses — must be in different slots
    sessions = [
        make_session("s1", course_id=1, lecturer_id=1, class_ids=[10], population=60),
        make_session("s2", course_id=2, lecturer_id=2, class_ids=[10], population=60),
    ]
    slots = [make_slot(1, "Monday"), make_slot(2, "Wednesday")]
    rooms = [make_room(1, 100), make_room(2, 100)]
    result = solve_timetable(SolverInput(
        sessions=sessions, time_slots=slots, rooms=rooms,
        lecturer_unavailability={},
    ))
    assert result.status in ("optimal", "feasible")
    slot_ids = [a.time_slot_id for a in result.assignments]
    assert slot_ids[0] != slot_ids[1]


def test_room_type_constraint():
    # Lab course must be assigned to a lab room, not a lecture hall
    sessions = [make_session("s1", 1, 1, [1], 20, room_type="lab")]
    slots = [make_slot(1, "Monday")]
    rooms = [make_room(1, 100, "lecture_hall"), make_room(2, 30, "lab")]
    result = solve_timetable(SolverInput(
        sessions=sessions, time_slots=slots, rooms=rooms,
        lecturer_unavailability={},
    ))
    assert result.status in ("optimal", "feasible")
    assert result.assignments[0].room_id == 2  # must use the lab


def test_lecturer_unavailability_respected():
    sessions = [make_session("s1", 1, 5, [1], 30)]
    slots = [make_slot(1, "Friday"), make_slot(2, "Monday")]
    rooms = [make_room(1, 50)]
    result = solve_timetable(SolverInput(
        sessions=sessions, time_slots=slots, rooms=rooms,
        lecturer_unavailability={5: [1]},  # lecturer 5 unavailable on slot 1 (Friday)
    ))
    assert result.status in ("optimal", "feasible")
    assert result.assignments[0].time_slot_id == 2  # must use Monday


def test_overcapacity_flagged():
    sessions = [make_session("s1", 1, 1, [1], population=800)]
    slots = [make_slot(1, "Monday")]
    rooms = [make_room(1, 700)]  # 800 > 700
    result = solve_timetable(SolverInput(
        sessions=sessions, time_slots=slots, rooms=rooms,
        lecturer_unavailability={},
    ))
    assert result.status in ("optimal", "feasible")
    assert result.assignments[0].is_overcapacity is True


def test_infeasible_returns_infeasible_status():
    # 2 sessions, 1 slot, same lecturer — impossible to schedule
    sessions = [
        make_session("s1", 1, 99, [1], 30),
        make_session("s2", 2, 99, [2], 30),
    ]
    slots = [make_slot(1, "Monday")]  # only 1 slot
    rooms = [make_room(1, 50), make_room(2, 50)]
    result = solve_timetable(SolverInput(
        sessions=sessions, time_slots=slots, rooms=rooms,
        lecturer_unavailability={},
    ))
    assert result.status == "infeasible"
```

- [ ] **Step 2: Run to confirm failures**

```bash
pytest tests/test_solver.py -v
```

Expected: `ImportError` — solver module doesn't exist.

- [ ] **Step 3: Create `app/solver/solver.py`**

```python
from collections import defaultdict
from ortools.sat.python import cp_model
from app.solver.models import SolverInput, SolverAssignment, SolverResult


def solve_timetable(solver_input: SolverInput) -> SolverResult:
    model = cp_model.CpModel()

    sessions = solver_input.sessions
    timeslots = solver_input.time_slots
    rooms = solver_input.rooms

    n_s = len(sessions)
    n_t = len(timeslots)
    n_r = len(rooms)

    if n_s == 0:
        return SolverResult(assignments=[], solve_time_seconds=0.0, status="optimal")

    # Decision variables: assign[(s, t, r)] = True if session s uses slot t in room r
    assign = {}
    for s in range(n_s):
        for t in range(n_t):
            for r in range(n_r):
                assign[(s, t, r)] = model.NewBoolVar(f"a_{s}_{t}_{r}")

    # Hard constraint 1: Each session is scheduled exactly once
    for s in range(n_s):
        model.AddExactlyOne(
            assign[(s, t, r)]
            for t in range(n_t)
            for r in range(n_r)
        )

    # Hard constraint 2: At most one session per room per timeslot
    for t in range(n_t):
        for r in range(n_r):
            model.AddAtMostOne(assign[(s, t, r)] for s in range(n_s))

    # Hard constraint 3: Lecturer teaches at most one session per timeslot
    lecturer_sessions = defaultdict(list)
    for s, session in enumerate(sessions):
        lecturer_sessions[session.lecturer_id].append(s)

    for lect_id, s_indices in lecturer_sessions.items():
        for t in range(n_t):
            model.AddAtMostOne(
                assign[(s, t, r)]
                for s in s_indices
                for r in range(n_r)
            )

    # Hard constraint 4: Class attends at most one session per timeslot
    class_sessions = defaultdict(list)
    for s, session in enumerate(sessions):
        for class_id in session.class_ids:
            class_sessions[class_id].append(s)

    for class_id, s_indices in class_sessions.items():
        for t in range(n_t):
            model.AddAtMostOne(
                assign[(s, t, r)]
                for s in s_indices
                for r in range(n_r)
            )

    # Hard constraint 5: Room type must match session requirement
    for s, session in enumerate(sessions):
        for t in range(n_t):
            for r, room in enumerate(rooms):
                if room["room_type"] != session.room_type_required:
                    model.Add(assign[(s, t, r)] == 0)

    # Hard constraint 6: Lecturer unavailability
    unavailability = solver_input.lecturer_unavailability
    for s, session in enumerate(sessions):
        blocked_slots = unavailability.get(session.lecturer_id, [])
        for t, timeslot in enumerate(timeslots):
            if timeslot["id"] in blocked_slots:
                for r in range(n_r):
                    model.Add(assign[(s, t, r)] == 0)

    # Solve
    cp_solver = cp_model.CpSolver()
    cp_solver.parameters.max_time_in_seconds = 60.0
    status_code = cp_solver.Solve(model)

    status_map = {
        cp_model.OPTIMAL: "optimal",
        cp_model.FEASIBLE: "feasible",
        cp_model.INFEASIBLE: "infeasible",
        cp_model.UNKNOWN: "unknown",
    }
    status = status_map.get(status_code, "unknown")

    assignments = []
    if status_code in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        for s, session in enumerate(sessions):
            for t in range(n_t):
                for r, room in enumerate(rooms):
                    if cp_solver.Value(assign[(s, t, r)]):
                        assignments.append(SolverAssignment(
                            session=session,
                            time_slot_id=timeslots[t]["id"],
                            room_id=room["id"],
                            is_overcapacity=session.population > room["capacity"],
                        ))

    return SolverResult(
        assignments=assignments,
        solve_time_seconds=cp_solver.WallTime(),
        status=status,
    )
```

- [ ] **Step 4: Run tests**

```bash
pytest tests/test_solver.py -v
```

Expected: all 7 tests pass.

- [ ] **Step 5: Commit checkpoint**

> **Suggested commit message:** "feat: add OR-Tools CP-SAT constraint solver with hard constraints"

```bash
git add backend/app/solver/solver.py backend/tests/test_solver.py
```

---

## Task 6: Postprocessor — Solver Output to DB Rows

**Files:**
- Create: `backend/app/solver/postprocessor.py`

- [ ] **Step 1: Create `app/solver/postprocessor.py`**

```python
from sqlalchemy.orm import Session
from app.solver.models import SolverResult, SolverAssignment
from app.models.timetable import Timetable, TimetableEntry, TimetableEntryClass


def save_solver_result(
    timetable: Timetable,
    result: SolverResult,
    db: Session,
) -> None:
    """Convert SolverResult assignments into TimetableEntry rows and save to DB."""
    for assignment in result.assignments:
        entry = TimetableEntry(
            timetable_id=timetable.id,
            course_id=assignment.session.course_id,
            lecturer_id=assignment.session.lecturer_id,
            room_id=assignment.room_id,
            time_slot_id=assignment.time_slot_id,
            group_id=assignment.session.group_id,
            week_pattern="every_week",
            is_overcapacity=assignment.is_overcapacity,
            is_merged=assignment.session.is_merged,
        )
        db.add(entry)
        db.flush()  # get entry.id before adding children

        for class_id in assignment.session.class_ids:
            db.add(TimetableEntryClass(entry_id=entry.id, class_id=class_id))

    db.commit()
```

- [ ] **Step 2: Commit checkpoint**

> **Suggested commit message:** "feat: add postprocessor to save solver results to database"

```bash
git add backend/app/solver/postprocessor.py
```

---

## Task 7: Full Preprocessor — DB to SolverInput

**Files:**
- Create: `backend/app/solver/db_preprocessor.py`

This bridges the DB (SQLAlchemy models) to the pure-Python preprocessor from Task 4.

- [ ] **Step 1: Create `app/solver/db_preprocessor.py`**

```python
from sqlalchemy.orm import Session
from app.models.university import Department, Faculty
from app.models.academic import Level, Class, Semester, TimeSlot
from app.models.course import Course, SharedCourse
from app.models.room import Room
from app.models.user import Lecturer, LecturerAvailability
from app.models.timetable import TimetableConflict
from app.solver.models import SolverInput, ConflictFlag
from app.solver.preprocessor import compute_merge_decision, compute_lab_split


def build_solver_input(
    timetable_id: int,
    semester_id: int,
    department_id: int,
    db: Session,
) -> tuple[SolverInput, list[ConflictFlag]]:
    """
    Load all data for a department + semester from the DB and return a SolverInput.
    Also returns a list of ConflictFlags for issues that need head resolution.
    """
    semester = db.query(Semester).filter(Semester.id == semester_id).first()
    faculty = (
        db.query(Faculty)
        .join(Department, Department.faculty_id == Faculty.id)
        .filter(Department.id == department_id)
        .first()
    )
    sessions_per_week = faculty.sessions_per_week if faculty else 2
    overflow_threshold = (
        db.query(Department)
        .filter(Department.id == department_id)
        .first()
        .faculty.university.overflow_threshold
    )

    # Time slots
    raw_slots = db.query(TimeSlot).filter(TimeSlot.semester_id == semester_id).all()
    time_slots = [
        {"id": ts.id, "day": ts.day_of_week,
         "start": str(ts.start_time), "end": str(ts.end_time)}
        for ts in raw_slots
    ]

    # Rooms (university-wide)
    uni_id = (
        db.query(Faculty)
        .join(Department, Department.faculty_id == Faculty.id)
        .filter(Department.id == department_id)
        .first().university_id
    )
    raw_rooms = db.query(Room).filter(Room.university_id == uni_id).all()
    rooms = [
        {"id": r.id, "capacity": r.capacity, "room_type": r.room_type}
        for r in raw_rooms
    ]
    labs = [r for r in rooms if r["room_type"] == "lab"]

    # Lecturer unavailability
    unavailability: dict[int, list[int]] = {}
    avail_records = (
        db.query(LecturerAvailability)
        .filter(LecturerAvailability.semester_id == semester_id,
                LecturerAvailability.is_available == False)  # noqa: E712
        .all()
    )
    slot_by_day_time: dict[str, int] = {
        f"{ts.day_of_week}_{ts.start_time}": ts.id for ts in raw_slots
    }
    for rec in avail_records:
        blocked_key = f"{rec.day_of_week}_{rec.start_time}"
        slot_id = slot_by_day_time.get(blocked_key)
        if slot_id:
            unavailability.setdefault(rec.lecturer_id, []).append(slot_id)

    # Courses for this department
    courses = db.query(Course).filter(Course.department_id == department_id).all()

    all_sessions = []
    all_conflicts: list[ConflictFlag] = []

    for course in courses:
        if not course.lecturer_id:
            continue  # skip unassigned courses

        # Find all classes that take this course
        shared_entries = (
            db.query(SharedCourse).filter(SharedCourse.course_id == course.id).all()
        )
        shared_class_ids = [s.class_id for s in shared_entries]

        # Get all classes in this department that have this course
        dept_classes = (
            db.query(Class)
            .join(Level, Level.id == Class.level_id)
            .filter(Level.department_id == department_id)
            .all()
        )
        own_class_ids = [c.id for c in dept_classes]

        attending_class_ids = list(set(own_class_ids + shared_class_ids))
        attending_classes = db.query(Class).filter(Class.id.in_(attending_class_ids)).all()
        classes_as_dicts = [{"id": c.id, "population": c.population} for c in attending_classes]
        course_dict = {
            "id": course.id, "code": course.code,
            "room_type_required": course.room_type_required,
        }

        if course.room_type_required == "lab":
            for cls in attending_classes:
                sessions, conflict = compute_lab_split(
                    course=course_dict,
                    student_class={"id": cls.id, "population": cls.population},
                    labs=labs,
                    sessions_per_week=sessions_per_week,
                    lecturer_id=course.lecturer_id,
                )
                all_sessions.extend(sessions)
                if conflict:
                    all_conflicts.append(conflict)
        else:
            sessions, conflict = compute_merge_decision(
                course=course_dict,
                classes=classes_as_dicts,
                rooms=rooms,
                lecturer_id=course.lecturer_id,
                sessions_per_week=sessions_per_week,
                overflow_threshold=overflow_threshold,
            )
            all_sessions.extend(sessions)
            if conflict:
                all_conflicts.append(conflict)

    return (
        SolverInput(
            sessions=all_sessions,
            time_slots=time_slots,
            rooms=rooms,
            lecturer_unavailability=unavailability,
        ),
        all_conflicts,
    )
```

- [ ] **Step 2: Commit checkpoint**

> **Suggested commit message:** "feat: add DB-to-SolverInput bridge (db_preprocessor)"

```bash
git add backend/app/solver/db_preprocessor.py
```

---

## Task 8: Timetable Schemas & CRUD API

**Files:**
- Create: `backend/app/schemas/timetable.py`
- Create: `backend/app/routers/timetable.py`
- Create: `backend/tests/test_timetable_api.py`
- Modify: `backend/app/main.py`

- [ ] **Step 1: Write `tests/test_timetable_api.py`**

```python
def get_admin_token(client):
    client.post("/auth/register", json={
        "email": "ttadmin@ub.cm", "password": "admin123",
        "full_name": "Admin", "role": "super_admin"
    })
    resp = client.post("/auth/login", json={"email": "ttadmin@ub.cm", "password": "admin123"})
    return resp.json()["access_token"]


def setup_semester_and_department(client, token):
    uni = client.post("/universities/", json={"name": "UB TT", "slug": "ub-tt"},
                      headers={"Authorization": f"Bearer {token}"}).json()
    fac = client.post("/faculties/", json={"name": "FET", "code": "FET-TT", "university_id": uni["id"]},
                      headers={"Authorization": f"Bearer {token}"}).json()
    dept = client.post("/departments/", json={"name": "EE", "code": "EE-TT", "faculty_id": fac["id"]},
                       headers={"Authorization": f"Bearer {token}"}).json()
    sem = client.post("/semesters/", json={
        "name": "S1 2025", "start_date": "2025-09-01",
        "end_date": "2026-01-31", "university_id": uni["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    return sem, dept


def test_create_timetable(client):
    token = get_admin_token(client)
    sem, dept = setup_semester_and_department(client, token)
    response = client.post("/timetables/", json={
        "semester_id": sem["id"], "department_id": dept["id"]
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 201
    data = response.json()
    assert data["status"] == "draft"
    assert data["semester_id"] == sem["id"]


def test_list_timetables(client):
    token = get_admin_token(client)
    response = client.get("/timetables/", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_get_timetable(client):
    token = get_admin_token(client)
    sem, dept = setup_semester_and_department(client, token)
    tt = client.post("/timetables/", json={
        "semester_id": sem["id"], "department_id": dept["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    response = client.get(f"/timetables/{tt['id']}", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200


def test_advance_timetable_status(client):
    token = get_admin_token(client)
    sem, dept = setup_semester_and_department(client, token)
    tt = client.post("/timetables/", json={
        "semester_id": sem["id"], "department_id": dept["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    # draft -> under_review
    response = client.post(f"/timetables/{tt['id']}/advance-status",
                           headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.json()["status"] == "under_review"


def test_cannot_skip_status(client):
    token = get_admin_token(client)
    sem, dept = setup_semester_and_department(client, token)
    tt = client.post("/timetables/", json={
        "semester_id": sem["id"], "department_id": dept["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    # Try to skip straight to published
    response = client.post(f"/timetables/{tt['id']}/publish",
                           headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 400  # must be approved first


def test_get_generation_job_status(client):
    token = get_admin_token(client)
    sem, dept = setup_semester_and_department(client, token)
    tt = client.post("/timetables/", json={
        "semester_id": sem["id"], "department_id": dept["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    response = client.get(f"/timetables/{tt['id']}/job-status",
                          headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.json()["status"] == "no_job"
```

- [ ] **Step 2: Run to confirm failures**

```bash
pytest tests/test_timetable_api.py -v
```

Expected: failures.

- [ ] **Step 3: Create `app/schemas/timetable.py`**

```python
from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class TimetableCreate(BaseModel):
    semester_id: int
    department_id: int


class TimetableResponse(BaseModel):
    id: int
    status: str
    semester_id: int
    department_id: int
    generated_at: Optional[datetime]
    created_at: datetime

    model_config = {"from_attributes": True}


class TimetableEntryResponse(BaseModel):
    id: int
    timetable_id: int
    course_id: int
    lecturer_id: int
    room_id: int
    time_slot_id: int
    group_id: Optional[int]
    week_pattern: str
    rotation_sequence: Optional[str]
    is_overcapacity: bool
    is_merged: bool
    class_ids: list[int] = []

    model_config = {"from_attributes": True}


class TimetableConflictResponse(BaseModel):
    id: int
    timetable_id: int
    conflict_type: str
    course_id: Optional[int]
    class_id: Optional[int]
    details: str
    resolved: bool
    resolution: Optional[str]

    model_config = {"from_attributes": True}


class ConflictResolutionRequest(BaseModel):
    resolution: str  # add_session | rotate_groups


class GenerationJobResponse(BaseModel):
    status: str
    error_message: Optional[str] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class ManualSlotMoveRequest(BaseModel):
    entry_id: int
    new_time_slot_id: int
    new_room_id: int


class NotificationResponse(BaseModel):
    id: int
    message: str
    notification_type: str
    is_read: bool
    created_at: datetime

    model_config = {"from_attributes": True}
```

- [ ] **Step 4: Create `app/routers/timetable.py`**

```python
import json
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.timetable import (
    Timetable, TimetableEntry, TimetableEntryClass,
    TimetableConflict, GenerationJob, Notification,
)
from app.models.user import User
from app.schemas.timetable import (
    TimetableCreate, TimetableResponse, TimetableEntryResponse,
    TimetableConflictResponse, ConflictResolutionRequest,
    GenerationJobResponse, ManualSlotMoveRequest, NotificationResponse,
)
from app.core.auth import get_current_user
from app.core.permissions import require_min_role

router = APIRouter(prefix="/timetables", tags=["Timetables"])

STATUS_FLOW = ["draft", "under_review", "approved", "published"]


@router.post("/", response_model=TimetableResponse, status_code=201)
def create_timetable(
    data: TimetableCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    timetable = Timetable(**data.model_dump())
    db.add(timetable)
    db.commit()
    db.refresh(timetable)
    return timetable


@router.get("/", response_model=list[TimetableResponse])
def list_timetables(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    return db.query(Timetable).all()


@router.get("/{timetable_id}", response_model=TimetableResponse)
def get_timetable(timetable_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    tt = db.query(Timetable).filter(Timetable.id == timetable_id).first()
    if not tt:
        raise HTTPException(status_code=404, detail="Timetable not found")
    return tt


@router.get("/{timetable_id}/entries", response_model=list[TimetableEntryResponse])
def get_entries(timetable_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    entries = db.query(TimetableEntry).filter(TimetableEntry.timetable_id == timetable_id).all()
    result = []
    for entry in entries:
        class_ids = [ec.class_id for ec in entry.entry_classes]
        entry_dict = {
            "id": entry.id, "timetable_id": entry.timetable_id,
            "course_id": entry.course_id, "lecturer_id": entry.lecturer_id,
            "room_id": entry.room_id, "time_slot_id": entry.time_slot_id,
            "group_id": entry.group_id, "week_pattern": entry.week_pattern,
            "rotation_sequence": entry.rotation_sequence,
            "is_overcapacity": entry.is_overcapacity,
            "is_merged": entry.is_merged, "class_ids": class_ids,
        }
        result.append(TimetableEntryResponse(**entry_dict))
    return result


@router.get("/{timetable_id}/conflicts", response_model=list[TimetableConflictResponse])
def get_conflicts(timetable_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    return db.query(TimetableConflict).filter(
        TimetableConflict.timetable_id == timetable_id,
        TimetableConflict.resolved == False,  # noqa: E712
    ).all()


@router.post("/{timetable_id}/advance-status", response_model=TimetableResponse)
def advance_status(
    timetable_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    tt = db.query(Timetable).filter(Timetable.id == timetable_id).first()
    if not tt:
        raise HTTPException(status_code=404, detail="Timetable not found")
    current_idx = STATUS_FLOW.index(tt.status) if tt.status in STATUS_FLOW else -1
    if current_idx >= len(STATUS_FLOW) - 1:
        raise HTTPException(status_code=400, detail="Timetable is already published")
    tt.status = STATUS_FLOW[current_idx + 1]
    db.commit()
    db.refresh(tt)
    return tt


@router.post("/{timetable_id}/publish", response_model=TimetableResponse)
def publish_timetable(
    timetable_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_min_role("department_head")),
):
    tt = db.query(Timetable).filter(Timetable.id == timetable_id).first()
    if not tt:
        raise HTTPException(status_code=404, detail="Timetable not found")
    if tt.status != "approved":
        raise HTTPException(status_code=400, detail="Timetable must be approved before publishing")
    tt.status = "published"
    db.commit()
    db.refresh(tt)
    # Notify all users in the department
    _notify_department(tt, db)
    return tt


@router.get("/{timetable_id}/job-status", response_model=GenerationJobResponse)
def get_job_status(timetable_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    job = (
        db.query(GenerationJob)
        .filter(GenerationJob.timetable_id == timetable_id)
        .order_by(GenerationJob.id.desc())
        .first()
    )
    if not job:
        return GenerationJobResponse(status="no_job")
    return job


@router.post("/{timetable_id}/generate")
def trigger_generation(
    timetable_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    tt = db.query(Timetable).filter(Timetable.id == timetable_id).first()
    if not tt:
        raise HTTPException(status_code=404, detail="Timetable not found")
    if tt.status not in ("draft",):
        raise HTTPException(status_code=400, detail="Can only generate for a draft timetable")

    # Create a job record
    job = GenerationJob(timetable_id=timetable_id, status="pending")
    db.add(job)
    db.commit()
    db.refresh(job)

    background_tasks.add_task(_run_generation, timetable_id, job.id)
    return {"message": "Generation started", "job_id": job.id}


@router.post("/{timetable_id}/conflicts/{conflict_id}/resolve", response_model=TimetableConflictResponse)
def resolve_conflict(
    timetable_id: int,
    conflict_id: int,
    data: ConflictResolutionRequest,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("department_head")),
):
    conflict = db.query(TimetableConflict).filter(
        TimetableConflict.id == conflict_id,
        TimetableConflict.timetable_id == timetable_id,
    ).first()
    if not conflict:
        raise HTTPException(status_code=404, detail="Conflict not found")
    if data.resolution not in ("add_session", "rotate_groups"):
        raise HTTPException(status_code=400, detail="resolution must be 'add_session' or 'rotate_groups'")

    from app.solver.conflict_resolver import apply_resolution
    apply_resolution(conflict, data.resolution, db)

    conflict.resolved = True
    conflict.resolution = data.resolution
    db.commit()
    db.refresh(conflict)
    return conflict


@router.put("/{timetable_id}/entries/move", response_model=TimetableEntryResponse)
def move_entry(
    timetable_id: int,
    data: ManualSlotMoveRequest,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("department_head")),
):
    entry = db.query(TimetableEntry).filter(
        TimetableEntry.id == data.entry_id,
        TimetableEntry.timetable_id == timetable_id,
    ).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Entry not found")

    # Clash check: is the new slot already taken by this lecturer or these classes?
    class_ids = [ec.class_id for ec in entry.entry_classes]
    lecturer_clash = db.query(TimetableEntry).filter(
        TimetableEntry.timetable_id == timetable_id,
        TimetableEntry.time_slot_id == data.new_time_slot_id,
        TimetableEntry.lecturer_id == entry.lecturer_id,
        TimetableEntry.id != entry.id,
    ).first()
    if lecturer_clash:
        raise HTTPException(status_code=409, detail="Lecturer already has a session in that slot")

    for class_id in class_ids:
        class_clash = (
            db.query(TimetableEntryClass)
            .join(TimetableEntry, TimetableEntry.id == TimetableEntryClass.entry_id)
            .filter(
                TimetableEntry.timetable_id == timetable_id,
                TimetableEntry.time_slot_id == data.new_time_slot_id,
                TimetableEntryClass.class_id == class_id,
                TimetableEntryClass.entry_id != entry.id,
            ).first()
        )
        if class_clash:
            raise HTTPException(status_code=409, detail=f"Class {class_id} already has a session in that slot")

    entry.time_slot_id = data.new_time_slot_id
    entry.room_id = data.new_room_id
    db.commit()
    db.refresh(entry)

    entry_class_ids = [ec.class_id for ec in entry.entry_classes]
    return TimetableEntryResponse(
        id=entry.id, timetable_id=entry.timetable_id, course_id=entry.course_id,
        lecturer_id=entry.lecturer_id, room_id=entry.room_id, time_slot_id=entry.time_slot_id,
        group_id=entry.group_id, week_pattern=entry.week_pattern,
        rotation_sequence=entry.rotation_sequence, is_overcapacity=entry.is_overcapacity,
        is_merged=entry.is_merged, class_ids=entry_class_ids,
    )


@router.get("/{timetable_id}/analytics")
def get_analytics(
    timetable_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("department_head")),
):
    from collections import Counter
    entries = db.query(TimetableEntry).filter(TimetableEntry.timetable_id == timetable_id).all()

    room_usage = Counter(e.room_id for e in entries)
    lecturer_sessions = Counter(e.lecturer_id for e in entries)
    overcapacity_entries = [e.id for e in entries if e.is_overcapacity]

    return {
        "total_entries": len(entries),
        "overcapacity_count": len(overcapacity_entries),
        "overcapacity_entry_ids": overcapacity_entries,
        "room_utilization": dict(room_usage),
        "lecturer_session_counts": dict(lecturer_sessions),
    }


@router.get("/notifications/mine", response_model=list[NotificationResponse])
def get_my_notifications(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return (
        db.query(Notification)
        .filter(Notification.user_id == current_user.id)
        .order_by(Notification.created_at.desc())
        .limit(50)
        .all()
    )


@router.post("/notifications/{notification_id}/read")
def mark_notification_read(
    notification_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    notif = db.query(Notification).filter(
        Notification.id == notification_id,
        Notification.user_id == current_user.id,
    ).first()
    if not notif:
        raise HTTPException(status_code=404, detail="Notification not found")
    notif.is_read = True
    db.commit()
    return {"ok": True}


# --- Internal helpers ---

def _run_generation(timetable_id: int, job_id: int) -> None:
    """Background task: runs the full solver pipeline."""
    from app.database import SessionLocal
    from app.solver.db_preprocessor import build_solver_input
    from app.solver.solver import solve_timetable
    from app.solver.postprocessor import save_solver_result

    db = SessionLocal()
    try:
        job = db.query(GenerationJob).filter(GenerationJob.id == job_id).first()
        timetable = db.query(Timetable).filter(Timetable.id == timetable_id).first()

        job.status = "running"
        job.started_at = datetime.utcnow()
        db.commit()

        solver_input, conflicts = build_solver_input(
            timetable_id=timetable_id,
            semester_id=timetable.semester_id,
            department_id=timetable.department_id,
            db=db,
        )

        # Save conflict flags to DB
        for c in conflicts:
            db.add(TimetableConflict(
                timetable_id=timetable_id,
                conflict_type=c.conflict_type,
                course_id=c.course_id,
                class_id=c.class_id,
                details=json.dumps({
                    "groups_needed": c.groups_needed,
                    "sessions_available": c.sessions_available,
                    "message": c.details,
                }),
            ))
        db.commit()

        if solver_input.sessions:
            result = solve_timetable(solver_input)
            if result.status in ("optimal", "feasible"):
                save_solver_result(timetable, result, db)
                timetable.generated_at = datetime.utcnow()
                job.status = "completed"
            else:
                job.status = "failed"
                job.error_message = f"Solver returned status: {result.status}"
        else:
            # All sessions flagged as conflicts — still mark completed
            job.status = "completed"
            timetable.generated_at = datetime.utcnow()

        job.completed_at = datetime.utcnow()
        db.commit()

    except Exception as exc:
        job = db.query(GenerationJob).filter(GenerationJob.id == job_id).first()
        if job:
            job.status = "failed"
            job.error_message = str(exc)
            job.completed_at = datetime.utcnow()
            db.commit()
    finally:
        db.close()


def _notify_department(timetable: Timetable, db: Session) -> None:
    """Create notifications for all users in the timetable's department."""
    from app.models.user import User
    users = db.query(User).filter(User.department_id == timetable.department_id).all()
    for user in users:
        db.add(Notification(
            user_id=user.id,
            message=f"Timetable for {timetable.department_id} has been published.",
            notification_type="timetable_published",
        ))
    db.commit()
```

- [ ] **Step 5: Create `app/solver/conflict_resolver.py`**

```python
import json
from math import ceil
from sqlalchemy.orm import Session
from app.models.timetable import TimetableConflict, TimetableEntry, TimetableEntryClass


def apply_resolution(conflict: TimetableConflict, resolution: str, db: Session) -> None:
    """
    Apply a head's chosen resolution to a flagged conflict.
    - add_session: add extra TimetableEntry rows for the extra groups in the same week
    - rotate_groups: mark existing entries with rotation_group week_pattern
    """
    details = json.loads(conflict.details) if conflict.details else {}

    if resolution == "rotate_groups":
        # Find entries for this course in this timetable and mark them as rotation_group
        entries = db.query(TimetableEntry).filter(
            TimetableEntry.timetable_id == conflict.timetable_id,
            TimetableEntry.course_id == conflict.course_id,
        ).all()
        group_names = [chr(65 + i) for i in range(len(entries))]  # ["A", "B", ...]
        rotation_seq = json.dumps(group_names)
        for entry in entries:
            entry.week_pattern = "rotation_group"
            entry.rotation_sequence = rotation_seq
        db.commit()

    elif resolution == "add_session":
        # Find available timeslots not used by this lecturer or the affected class
        from app.models.timetable import TimetableEntry, TimetableEntryClass
        from app.models.academic import TimeSlot, Semester
        from app.models.course import Course

        course = db.query(Course).filter(Course.id == conflict.course_id).first()
        if not course or not course.lecturer_id:
            return

        # All timeslots for this timetable's semester
        timetable = db.query(Timetable).filter(Timetable.id == conflict.timetable_id).first()
        all_slots = db.query(TimeSlot).filter(TimeSlot.semester_id == timetable.semester_id).all()
        used_slot_ids_for_lecturer = {
            e.time_slot_id for e in db.query(TimetableEntry).filter(
                TimetableEntry.timetable_id == conflict.timetable_id,
                TimetableEntry.lecturer_id == course.lecturer_id,
            ).all()
        }
        used_slot_ids_for_class = set()
        if conflict.class_id:
            used_slot_ids_for_class = {
                e.time_slot_id for e in
                db.query(TimetableEntry)
                .join(TimetableEntryClass, TimetableEntryClass.entry_id == TimetableEntry.id)
                .filter(
                    TimetableEntry.timetable_id == conflict.timetable_id,
                    TimetableEntryClass.class_id == conflict.class_id,
                ).all()
            }

        blocked = used_slot_ids_for_lecturer | used_slot_ids_for_class
        free_slot = next((s for s in all_slots if s.id not in blocked), None)
        if not free_slot:
            return  # No free slot found — head must resolve manually via move endpoint

        # Find the largest lab room
        from app.models.room import Room
        from app.models.university import Faculty, Department
        uni_id = (
            db.query(Faculty)
            .join(Department, Department.faculty_id == Faculty.id)
            .filter(Department.id == timetable.department_id)
            .first().university_id
        )
        lab = db.query(Room).filter(
            Room.university_id == uni_id, Room.room_type == "lab"
        ).order_by(Room.capacity.desc()).first()
        if not lab:
            return

        groups_needed = details.get("groups_needed", 2)
        sessions_available = details.get("sessions_available", 2)
        extra_groups = groups_needed - sessions_available
        from math import ceil
        total_population = (
            db.query(Class).filter(Class.id == conflict.class_id).first().population
            if conflict.class_id else 0
        )
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
```

- [ ] **Step 6: Register timetable router in `app/main.py`**

```python
from fastapi import FastAPI
from app.routers import auth, universities, faculties, departments, rooms, semesters, academic, courses, users, timetable

app = FastAPI(title="University Timetabling API", version="1.0.0")

app.include_router(auth.router)
app.include_router(universities.router)
app.include_router(faculties.router)
app.include_router(departments.router)
app.include_router(rooms.router)
app.include_router(semesters.router)
app.include_router(academic.router)
app.include_router(courses.router)
app.include_router(users.router)
app.include_router(timetable.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
```

- [ ] **Step 7: Run tests**

```bash
pytest tests/test_timetable_api.py -v
```

Expected: all 6 tests pass.

- [ ] **Step 8: Commit checkpoint**

> **Suggested commit message:** "feat: add Timetable CRUD, generation trigger, status workflow, conflict resolution, and notifications"

```bash
git add backend/app/schemas/timetable.py backend/app/routers/timetable.py backend/app/solver/conflict_resolver.py backend/app/main.py backend/tests/test_timetable_api.py
```

---

## Task 9: Timetable Export (PDF & CSV)

**Files:**
- Create: `backend/app/routers/export.py`
- Modify: `backend/app/main.py`

- [ ] **Step 1: Create `app/routers/export.py`**

```python
import csv
import io
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph
from reportlab.lib.styles import getSampleStyleSheet
from app.database import get_db
from app.models.timetable import Timetable, TimetableEntry
from app.models.academic import TimeSlot, Class
from app.models.course import Course
from app.models.room import Room
from app.models.user import Lecturer, User as UserModel
from app.core.auth import get_current_user

router = APIRouter(prefix="/export", tags=["Export"])


def _get_entries_with_details(timetable_id: int, db: Session) -> list[dict]:
    entries = db.query(TimetableEntry).filter(TimetableEntry.timetable_id == timetable_id).all()
    rows = []
    for entry in entries:
        timeslot = db.query(TimeSlot).filter(TimeSlot.id == entry.time_slot_id).first()
        course = db.query(Course).filter(Course.id == entry.course_id).first()
        room = db.query(Room).filter(Room.id == entry.room_id).first()
        lecturer = db.query(Lecturer).filter(Lecturer.id == entry.lecturer_id).first()
        lecturer_name = lecturer.user.full_name if lecturer and lecturer.user else "N/A"
        class_ids = [ec.class_id for ec in entry.entry_classes]
        class_names = []
        for cid in class_ids:
            cls = db.query(Class).filter(Class.id == cid).first()
            if cls:
                class_names.append(cls.name)
        rows.append({
            "Day": timeslot.day_of_week if timeslot else "",
            "Time": f"{timeslot.start_time}-{timeslot.end_time}" if timeslot else "",
            "Course": f"{course.code} — {course.name}" if course else "",
            "Classes": ", ".join(class_names),
            "Lecturer": lecturer_name,
            "Room": room.name if room else "",
            "Capacity": str(room.capacity) if room else "",
            "Overcapacity": "YES" if entry.is_overcapacity else "No",
            "Week Pattern": entry.week_pattern,
        })
    return sorted(rows, key=lambda r: (r["Day"], r["Time"]))


@router.get("/timetables/{timetable_id}/csv")
def export_csv(
    timetable_id: int,
    db: Session = Depends(get_db),
    _: UserModel = Depends(get_current_user),
):
    tt = db.query(Timetable).filter(Timetable.id == timetable_id).first()
    if not tt:
        raise HTTPException(status_code=404, detail="Timetable not found")

    rows = _get_entries_with_details(timetable_id, db)
    if not rows:
        raise HTTPException(status_code=404, detail="No entries to export")

    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)
    output.seek(0)

    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename=timetable_{timetable_id}.csv"},
    )


@router.get("/timetables/{timetable_id}/pdf")
def export_pdf(
    timetable_id: int,
    db: Session = Depends(get_db),
    _: UserModel = Depends(get_current_user),
):
    tt = db.query(Timetable).filter(Timetable.id == timetable_id).first()
    if not tt:
        raise HTTPException(status_code=404, detail="Timetable not found")

    rows = _get_entries_with_details(timetable_id, db)
    if not rows:
        raise HTTPException(status_code=404, detail="No entries to export")

    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=landscape(A4))
    styles = getSampleStyleSheet()

    headers = list(rows[0].keys())
    table_data = [headers] + [[r[h] for h in headers] for r in rows]

    table = Table(table_data, repeatRows=1)
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1a237e")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f5f5f5")]),
        ("BACKGROUND", (7, 1), (7, -1), colors.HexColor("#fff3e0")),  # highlight overcapacity col
    ]))

    doc.build([
        Paragraph(f"Timetable #{timetable_id}", styles["Title"]),
        table,
    ])
    buffer.seek(0)

    return StreamingResponse(
        buffer,
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=timetable_{timetable_id}.pdf"},
    )
```

- [ ] **Step 2: Register export router in `app/main.py`**

```python
from fastapi import FastAPI
from app.routers import (
    auth, universities, faculties, departments, rooms,
    semesters, academic, courses, users, timetable, export,
)

app = FastAPI(title="University Timetabling API", version="1.0.0")

app.include_router(auth.router)
app.include_router(universities.router)
app.include_router(faculties.router)
app.include_router(departments.router)
app.include_router(rooms.router)
app.include_router(semesters.router)
app.include_router(academic.router)
app.include_router(courses.router)
app.include_router(users.router)
app.include_router(timetable.router)
app.include_router(export.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
```

- [ ] **Step 3: Verify export endpoints appear in docs**

```bash
uvicorn app.main:app --reload
```

Open `http://127.0.0.1:8000/docs` and confirm `/export/timetables/{id}/csv` and `/export/timetables/{id}/pdf` appear. Press CTRL+C to stop.

- [ ] **Step 4: Run full test suite**

```bash
pytest -v --tb=short
```

Expected: all tests pass.

- [ ] **Step 5: Commit checkpoint**

> **Suggested commit message:** "feat: add PDF and CSV timetable export endpoints"

```bash
git add backend/app/routers/export.py backend/app/main.py
```

---

## Task 10: Final Verification

- [ ] **Step 1: Run full test suite**

```bash
cd backend
source venv/Scripts/activate
pytest -v --tb=short
```

Expected: all tests pass with no failures.

- [ ] **Step 2: Start the server and verify all endpoints**

```bash
uvicorn app.main:app --reload
```

Open `http://127.0.0.1:8000/docs` and verify these groups appear:
- Timetables (generate, status workflow, conflict resolution, manual move)
- Export (CSV, PDF)
- Notifications

- [ ] **Step 3: Final commit checkpoint**

> **Suggested commit message:** "chore: complete timetable generation engine — solver, export, notifications"

```bash
git add .
```

---

## What's Next

**Plan 3 — Flutter Frontend** will add:
- Role-based navigation and screen routing
- UI design for each screen (using frontend-design skill)
- Timetable grid view (weekly schedule)
- Generation trigger UI with job status polling
- Conflict resolution UI for department heads
- PDF/CSV export buttons
- Push notifications (FCM integration)
- Shareable read-only timetable links
