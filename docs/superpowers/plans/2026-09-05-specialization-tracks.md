# Specialization Tracks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a specialization level split into stable sub-cohorts ("tracks") that take some courses in parallel, by modelling each track as its own `Class` and giving each course an optional per-class target.

**Architecture:** A track is a `Class` under a level. A new nullable `courses.class_id` targets one class; when NULL the course belongs to the whole level (every class), which is today's behavior. The preprocessor honors the target when gathering attending classes. The CP-SAT solver is untouched — its clash constraint is already per-class, so two different track-classes schedule in the same slot. A new nullable `classes.track` labels the sub-cohort.

**Tech Stack:** FastAPI, SQLAlchemy 2.0, Alembic, OR-Tools CP-SAT, pytest (SQLite), Flutter/GetX frontend.

## Global Constraints

- Both new columns are **nullable** and default to today's behavior; existing rows must not change meaning (`courses.class_id = NULL` = whole level).
- **No change to the CP-SAT solver** (`app/solver/solver.py`).
- Tests run on SQLite via `Base.metadata.create_all` (see `tests/conftest.py`) — they pick up model columns automatically and do **not** run Alembic. The Alembic migration is for the real PostgreSQL database only.
- Commit style: plain messages, no `feat:`/`fix:` prefixes, no `Co-Authored-By` line.
- The current Alembic head is `a1b2c3d4e5f6`; the new migration chains from it.
- Backend commands run from `backend/` using the venv: `./venv/Scripts/python.exe -m pytest ...`.

---

### Task 1: Data model, schemas, and migration

**Files:**
- Modify: `backend/app/models/course.py` (add `class_id`)
- Modify: `backend/app/models/academic.py` (add `Class.track`)
- Modify: `backend/app/schemas/course.py` (add `class_id` to Create/Update/Out)
- Modify: `backend/app/schemas/academic.py` (add `track` to ClassCreate/Update/Out)
- Modify: `backend/app/routers/courses.py` (null `class_id` for university-admin courses)
- Create: `backend/alembic/versions/c1d2e3f4a5b6_add_specialization_tracks.py`
- Test: `backend/tests/test_specialization_model.py`

**Interfaces:**
- Produces: `Course.class_id: Optional[int]` (FK `classes.id`); `Class.track: Optional[str]`; `CourseCreate.class_id`, `CourseOut.class_id`, `CourseUpdate.class_id`; `ClassCreate.track`, `ClassOut.track`, `ClassUpdate.track`. Later tasks rely on these exact names.

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_specialization_model.py`:

```python
from tests.conftest import make_university


def _make_level(client, headers):
    uni = make_university(client, headers)
    fac = client.post("/faculties/", json={
        "name": "FET", "code": "FET", "university_id": uni["id"],
    }, headers=headers).json()
    dept = client.post("/departments/", json={
        "name": "Computer Engineering", "code": "CEF", "faculty_id": fac["id"],
    }, headers=headers).json()
    level = client.post("/levels/", json={
        "number": 400, "department_id": dept["id"],
    }, headers=headers).json()
    return dept, level


def test_class_accepts_track(client, auth_headers):
    _dept, level = _make_level(client, auth_headers)
    r = client.post("/classes/", json={
        "name": "CE400 Software", "population": 120,
        "level_id": level["id"], "track": "Software",
    }, headers=auth_headers)
    assert r.status_code == 201
    assert r.json()["track"] == "Software"


def test_class_track_defaults_to_null(client, auth_headers):
    _dept, level = _make_level(client, auth_headers)
    r = client.post("/classes/", json={
        "name": "CE400", "population": 200, "level_id": level["id"],
    }, headers=auth_headers)
    assert r.status_code == 201
    assert r.json()["track"] is None


def test_course_accepts_class_id(client, auth_headers):
    dept, level = _make_level(client, auth_headers)
    cls = client.post("/classes/", json={
        "name": "CE400 Software", "population": 120,
        "level_id": level["id"], "track": "Software",
    }, headers=auth_headers).json()
    r = client.post("/courses/", json={
        "code": "CEF440", "name": "Internet Programming",
        "level_id": level["id"], "department_id": dept["id"],
        "class_id": cls["id"], "weekly_hours": 2, "semester": 1,
    }, headers=auth_headers)
    assert r.status_code == 201
    assert r.json()["class_id"] == cls["id"]


def test_course_class_id_defaults_to_null(client, auth_headers):
    dept, level = _make_level(client, auth_headers)
    r = client.post("/courses/", json={
        "code": "CEF441", "name": "Common Course",
        "level_id": level["id"], "department_id": dept["id"],
        "weekly_hours": 2, "semester": 1,
    }, headers=auth_headers)
    assert r.status_code == 201
    assert r.json()["class_id"] is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./venv/Scripts/python.exe -m pytest tests/test_specialization_model.py -v`
Expected: FAIL — `track` / `class_id` not accepted or not returned (KeyError / assertion on `None` vs missing).

- [ ] **Step 3: Add the model columns**

In `backend/app/models/course.py`, inside `class Course`, after the `lecturer_id` column add:

```python
    class_id: Mapped[Optional[int]] = mapped_column(ForeignKey("classes.id"), nullable=True)
    # When set, the course belongs to just this one class (a specialization
    # track). When NULL, it belongs to every class at level_id (the default).
```

In `backend/app/models/academic.py`, inside `class Class`, after the `population` column add:

```python
    track: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    # Specialization label, e.g. "Software" / "Networking"; NULL for a level's
    # single (non-specialized) class.
```

Ensure `Optional` is imported in `academic.py` (add `from typing import Optional` at the top if missing).

- [ ] **Step 4: Add the schema fields**

In `backend/app/schemas/course.py`:
- `CourseCreate`: add `class_id: Optional[int] = None`
- `CourseUpdate`: add `class_id: Optional[int] = None`
- `CourseOut`: add `class_id: Optional[int]`

In `backend/app/schemas/academic.py`:
- `ClassCreate`: add `track: Optional[str] = None`
- `ClassUpdate`: add `track: Optional[str] = None`
- `ClassOut`: add `track: Optional[str]`

(Confirm `Optional` is imported in both schema files.)

- [ ] **Step 5: Null class_id for university-wide courses**

In `backend/app/routers/courses.py`, in `create_course`, the `university_admin` branch already nulls `department_id`/`level_id`. Add `class_id` to it:

```python
    if current_user.role == "university_admin":
        # University admin adds university-wide requirements only
        data["university_id"] = current_user.university_id
        data["department_id"] = None
        data["level_id"] = None
        data["class_id"] = None
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./venv/Scripts/python.exe -m pytest tests/test_specialization_model.py -v`
Expected: PASS (4 passed).

- [ ] **Step 7: Write the Alembic migration**

Create `backend/alembic/versions/c1d2e3f4a5b6_add_specialization_tracks.py`:

```python
"""add_specialization_tracks

Revision ID: c1d2e3f4a5b6
Revises: a1b2c3d4e5f6
Create Date: 2026-09-05 00:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'c1d2e3f4a5b6'
down_revision: Union[str, None] = 'a1b2c3d4e5f6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('classes', sa.Column('track', sa.String(length=50), nullable=True))
    op.add_column('courses', sa.Column(
        'class_id', sa.Integer(),
        sa.ForeignKey('classes.id'), nullable=True,
    ))


def downgrade() -> None:
    op.drop_column('courses', 'class_id')
    op.drop_column('classes', 'track')
```

- [ ] **Step 8: Verify the migration chain is valid**

Run: `./venv/Scripts/python.exe -m alembic heads`
Expected: a single head `c1d2e3f4a5b6`.

(Do not run `alembic upgrade` here — that would touch the live PostgreSQL DB. Applying it to production is a deliberate, separate step in the rollout, done when you choose.)

- [ ] **Step 9: Run the full backend suite (no regressions)**

Run: `./venv/Scripts/python.exe -m pytest -q`
Expected: all pass (previous green baseline + the 4 new tests).

- [ ] **Step 10: Commit**

```bash
git add backend/app/models/course.py backend/app/models/academic.py \
        backend/app/schemas/course.py backend/app/schemas/academic.py \
        backend/app/routers/courses.py \
        backend/alembic/versions/c1d2e3f4a5b6_add_specialization_tracks.py \
        backend/tests/test_specialization_model.py
git commit -m "specialization tracks: add courses.class_id and classes.track (model, schemas, migration)"
```

---

### Task 2: Preprocessor honors the per-class target

**Files:**
- Modify: `backend/app/solver/db_preprocessor.py` (the departmental-course loop, "Classes at this course's level")
- Test: `backend/tests/test_track_scheduling.py`

**Interfaces:**
- Consumes: `Course.class_id` (Task 1), `build_solver_input(run_id, semester_id, faculty_ids, building_ids, db)` returning `(SolverInput, conflicts)` where `SolverInput.sessions` is a list of `ScheduleSession` with `.course_id` and `.class_ids`.
- Produces: no new symbols; changes only which classes a course's sessions cover.

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_track_scheduling.py` (mirrors `tests/test_semester_filtering.py`'s DB setup):

```python
"""A track-specific course (class_id set) schedules for only its own class;
a whole-level course (class_id NULL) covers every class at the level, so the
two tracks can be taught in parallel."""
from app.models.university import University, Faculty, Department
from app.models.academic import Level, Class, Semester, TimeSlot
from app.models.building import Building
from app.models.room import Room
from app.models.course import Course
from app.models.user import User, Lecturer
from app.models.timetable import TimetableRun, TimetableRunFaculty, TimetableRunBuilding
from app.solver.db_preprocessor import build_solver_input


def _setup(db):
    uni = University(name="UB", slug="ub-track", overflow_threshold=0.2)
    db.add(uni); db.flush()
    fac = Faculty(name="FET", code="FET", sessions_per_week=2,
                  session_duration_hours=2, university_id=uni.id)
    db.add(fac); db.flush()
    dept = Department(name="CE", code="CE", faculty_id=fac.id)
    db.add(dept); db.flush()
    level = Level(number=400, department_id=dept.id)
    db.add(level); db.flush()
    sw = Class(name="CE400 Software", population=120, level_id=level.id, track="Software")
    net = Class(name="CE400 Networking", population=80, level_id=level.id, track="Networking")
    db.add(sw); db.add(net); db.flush()
    sem = Semester(name="S", start_date="2025-09-01", end_date="2026-01-31",
                   university_id=uni.id, term=1)
    db.add(sem); db.flush()
    db.add(TimeSlot(day_of_week="Monday", start_time="07:00",
                    end_time="09:00", semester_id=sem.id)); db.flush()
    bld = Building(name="Block", university_id=uni.id)
    db.add(bld); db.flush()
    db.add(Room(name="Hall", capacity=250, room_type="lecture_hall",
                is_active=True, building_id=bld.id)); db.flush()
    luser = User(email="lt@ub.cm", hashed_password="x", full_name="Dr X",
                 role="lecturer", is_active=True)
    db.add(luser); db.flush()
    lect = Lecturer(user_id=luser.id, department_id=dept.id)
    db.add(lect); db.flush()

    def course(code, class_id):
        c = Course(code=code, name=code, room_type_required="lecture_hall",
                   level_id=level.id, department_id=dept.id, class_id=class_id,
                   lecturer_id=lect.id, weekly_hours=1, semester=1)
        db.add(c); db.flush()
        return c

    sw_course = course("CE401SW", sw.id)      # Software only
    net_course = course("CE402NET", net.id)   # Networking only
    common = course("CE400C", None)           # whole level

    run = TimetableRun(name="Run", semester_id=sem.id, created_by=luser.id, status="draft")
    db.add(run); db.flush()
    db.add(TimetableRunFaculty(run_id=run.id, faculty_id=fac.id))
    db.add(TimetableRunBuilding(run_id=run.id, building_id=bld.id))
    db.commit(); db.refresh(run)
    return run, sem, fac, bld, sw, net, sw_course, net_course, common


def test_track_specific_course_targets_one_class(db):
    run, sem, fac, bld, sw, net, sw_course, net_course, common = _setup(db)
    solver_input, _ = build_solver_input(
        run_id=run.id, semester_id=sem.id,
        faculty_ids=[fac.id], building_ids=[bld.id], db=db,
    )
    sw_sessions = [s for s in solver_input.sessions if s.course_id == sw_course.id]
    assert sw_sessions, "Software course produced no session"
    for s in sw_sessions:
        assert set(s.class_ids) == {sw.id}     # only Software class


def test_whole_level_course_covers_all_classes(db):
    run, sem, fac, bld, sw, net, sw_course, net_course, common = _setup(db)
    solver_input, _ = build_solver_input(
        run_id=run.id, semester_id=sem.id,
        faculty_ids=[fac.id], building_ids=[bld.id], db=db,
    )
    common_sessions = [s for s in solver_input.sessions if s.course_id == common.id]
    assert common_sessions, "Common course produced no session"
    covered = set()
    for s in common_sessions:
        covered.update(s.class_ids)
    assert covered == {sw.id, net.id}          # both tracks
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./venv/Scripts/python.exe -m pytest tests/test_track_scheduling.py -v`
Expected: FAIL — `test_track_specific_course_targets_one_class` fails because the Software course currently attaches to *both* classes (`class_ids` == {sw, net}).

- [ ] **Step 3: Implement the targeting**

In `backend/app/solver/db_preprocessor.py`, find the block (in the `for course in courses:` loop):

```python
        # Classes at this course's level
        level_classes = (
            db.query(Class)
            .filter(Class.level_id == course.level_id)
            .all()
        )
        own_class_ids = [c.id for c in level_classes]
```

Replace it with:

```python
        # Classes this course is for. A course targeting one class (class_id
        # set) is a specialization-track course: only that class attends. With
        # no target (class_id NULL) every class at the level attends, as before.
        if course.class_id is not None:
            own_class_ids = [course.class_id]
        else:
            level_classes = (
                db.query(Class)
                .filter(Class.level_id == course.level_id)
                .all()
            )
            own_class_ids = [c.id for c in level_classes]
```

(The following lines — `attending_class_ids = list(set(own_class_ids + shared_class_ids))` etc. — stay unchanged.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `./venv/Scripts/python.exe -m pytest tests/test_track_scheduling.py -v`
Expected: PASS (2 passed).

- [ ] **Step 5: Run the full backend suite**

Run: `./venv/Scripts/python.exe -m pytest -q`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add backend/app/solver/db_preprocessor.py backend/tests/test_track_scheduling.py
git commit -m "specialization tracks: preprocessor targets a single class when a course sets class_id"
```

---

### Task 3: Course bulk import — optional `track` column

**Files:**
- Modify: `backend/app/routers/courses.py` (`_import_faculty_courses`)
- Test: `backend/tests/test_track_import.py`

**Interfaces:**
- Consumes: `Class.track` (Task 1), the faculty import's existing `classes_by_level: dict[int, list[Class]]` and `level_by_key: dict[(dept_id, number), Level]`.
- Produces: rows may carry a `track` column; created courses get the matching `class_id`.

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_track_import.py` (reuses helpers from `tests/test_course_bulk_import.py`):

```python
from tests.test_course_bulk_import import setup_faculty_head, _upload


def _level_id(client, ctx):
    # setup_faculty_head already created level 400; fetch its id.
    levels = client.get(f"/departments/{ctx['dept']['id']}/levels",
                        headers=ctx["headers"]).json()
    return next(l["id"] for l in levels if l["number"] == 400)


def _make_track_classes(client, ctx):
    """Create two track-classes under the existing Computer Engineering level 400."""
    lid = _level_id(client, ctx)
    sw = client.post("/classes/", json={
        "name": "CE400 Software", "population": 120,
        "level_id": lid, "track": "Software",
    }, headers=ctx["headers"]).json()
    net = client.post("/classes/", json={
        "name": "CE400 Networking", "population": 80,
        "level_id": lid, "track": "Networking",
    }, headers=ctx["headers"]).json()
    return sw, net


def test_import_track_column_targets_class(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)  # creates dept + level 400
    sw, net = _make_track_classes(client, ctx)
    csv_text = (
        "code,name,level,department,semester,track\n"
        "CE401SW,Software Design,400,Computer Engineering,1,Software\n"
        "CE402NET,Routing,400,Computer Engineering,1,Networking\n"
        "CE400C,Ethics,400,Computer Engineering,1,\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    assert r.status_code == 200
    # Verify class_id via the courses list.
    courses = client.get("/courses/", headers=ctx["headers"]).json()
    by_code = {c["code"]: c for c in courses}
    assert by_code["CE401SW"]["class_id"] == sw["id"]
    assert by_code["CE402NET"]["class_id"] == net["id"]
    assert by_code["CE400C"]["class_id"] is None   # blank track = whole level


def test_import_unknown_track_is_skipped(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    _make_track_classes(client, ctx)
    csv_text = (
        "code,name,level,department,semester,track\n"
        "CE499X,Mystery,400,Computer Engineering,1,Robotics\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    assert r.status_code == 200
    body = r.json()
    assert body["created"] == []
    assert any("Robotics" in s["reason"] or "track" in s["reason"].lower()
               for s in body["skipped"])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./venv/Scripts/python.exe -m pytest tests/test_track_import.py -v`
Expected: FAIL — the importer ignores `track`, so `CE401SW`'s `class_id` is `None` (assertion fails).

- [ ] **Step 3: Implement track resolution in the importer**

In `backend/app/routers/courses.py`, inside `_import_faculty_courses`, after the `level` is resolved and before building the `entry`/`Course`, add track handling. Locate where `lecturer_raw`/`lect_id` are computed and add just before constructing the course:

```python
        # Optional specialization track: match the row's track label against a
        # class at this (department, level). Blank track = whole level.
        track_raw = (row.get("track") or "").strip()
        target_class_id = None
        if track_raw:
            level_classes = classes_by_level.get(level.id, [])
            match = next(
                (c for c in level_classes
                 if (c.track or "").strip().lower() == track_raw.lower()),
                None,
            )
            if not match:
                skipped.append({
                    "code": code,
                    "reason": f"track '{track_raw}' not found at level {level_num} "
                              f"in '{dept.name}'",
                })
                continue
            target_class_id = match.id
```

Then, in the `if not dry_run:` block, pass `class_id=target_class_id` to the `Course(...)` constructor:

```python
            course = Course(
                code=code, name=name, room_type_required=room_type,
                level_id=level.id, department_id=dept.id, university_id=None,
                lecturer_id=lect_id, weekly_hours=weekly_hours, semester=semester,
                class_id=target_class_id,
            )
```

Also add `"track": track_raw or None` to the `entry` dict so the dry-run preview shows it.

- [ ] **Step 4: Run tests to verify they pass**

Run: `./venv/Scripts/python.exe -m pytest tests/test_track_import.py -v`
Expected: PASS (2 passed).

- [ ] **Step 5: Run the full backend suite**

Run: `./venv/Scripts/python.exe -m pytest -q`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add backend/app/routers/courses.py backend/tests/test_track_import.py
git commit -m "course import: optional track column targets a specialization-track class"
```

---

### Task 4: Frontend — track fields and faculty-setup support

**Files:**
- Modify: `frontend/lib/core/models/academic.dart` (`StudyClass.track`)
- Modify: `frontend/lib/core/models/course.dart` (`Course.classId`)
- Modify: `frontend/lib/features/faculty_setup/faculty_setup_screen.dart` (add/list track-classes under a level)
- Modify: `frontend/lib/features/bulk_import/course_bulk_import_screen.dart` (document the `track` column)

**Interfaces:**
- Consumes: backend `class_id` on courses and `track` on classes (Tasks 1–3); `POST /classes/` accepting `{name, population, level_id, track}`; `GET /faculty-setup/tree` (currently reads `level.classes[0]`).
- Produces: no code consumed by later tasks (final task).

- [ ] **Step 1: Add `track` to the StudyClass model**

In `frontend/lib/core/models/academic.dart`, `class StudyClass`:
- add field `final String? track;`
- add `this.track,` to the constructor
- in `fromJson`, add `track: json['track'] as String?,`

- [ ] **Step 2: Add `classId` to the Course model**

In `frontend/lib/core/models/course.dart`, `class Course`:
- add field `final int? classId;`
- add `this.classId,` to the constructor
- in `fromJson`, add `classId: json['class_id'] as int?,`

- [ ] **Step 3: Verify the app still analyzes and builds**

Run (from `frontend/`): `flutter analyze`
Expected: no new errors beyond the known baseline (37 info-level issues).

- [ ] **Step 4: Add track-class management to faculty setup**

In `frontend/lib/features/faculty_setup/faculty_setup_screen.dart`:
- Follow the existing `_addLevel` dialog pattern (around the level dialog) to add an **"Add class / track"** action on each level node that POSTs to `/classes/` with `{name, population, level_id, track}`. The `track` field is an optional text input ("e.g. Software — leave blank for a single class").
- The faculty tree currently shows only `level.classes[0]` (see backend `GET /faculty-setup/tree`). Update the backend `get_faculty_tree` in `backend/app/routers/faculty_setup.py` to return **all** classes per level (a `classes: [{id, name, population, track}]` list on each level node) and render each track under its level in the tree. Keep the existing single-population display working when a level has exactly one untracked class.

Note: this step spans backend (`faculty_setup.py` tree endpoint) and Flutter. Add a backend test in `backend/tests/test_academic.py` (or a new `test_faculty_tree_tracks.py`) asserting the tree returns two classes for a level with two track-classes, before wiring the Flutter side.

- [ ] **Step 5: Document the import `track` column**

In `frontend/lib/features/bulk_import/course_bulk_import_screen.dart`, add the `track` column to the on-screen column documentation/help: "`track` (optional) — the specialization track this course is for (must match a class's track at that level); leave blank for a course the whole level takes."

- [ ] **Step 6: Verify analyze + build**

Run (from `frontend/`):
- `flutter analyze` — no new errors beyond baseline
- `flutter build web` — compiles

Run (from `backend/`): `./venv/Scripts/python.exe -m pytest -q` — all pass (including the new tree test).

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/core/models/academic.dart frontend/lib/core/models/course.dart \
        frontend/lib/features/faculty_setup/faculty_setup_screen.dart \
        frontend/lib/features/bulk_import/course_bulk_import_screen.dart \
        backend/app/routers/faculty_setup.py backend/tests/
git commit -m "specialization tracks: frontend track fields and faculty-setup track-class management"
```

---

## Notes for the implementer

- **Pilot unblock:** Tasks 1–3 make specialization fully functional. Track-classes can be created immediately via `POST /classes/` (now track-aware) even before Task 4's UI lands, and courses imported with a `track` column. Task 4 is usability polish.
- **Solver is deliberately untouched.** If a test wants to prove two tracks run in the same slot end-to-end, it can call the solver, but the preprocessor tests in Task 2 already establish the class-targeting that makes it possible; the per-class clash constraint does the rest unchanged.
