# Course Bulk Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a faculty head or a university admin upload a CSV/Excel file of courses and have them created in bulk, with lecturers auto-matched from the file where possible and left unassigned otherwise.

**Architecture:** One role-aware endpoint `POST /courses/bulk-import/`. Pure parsing/matching helpers live in a new module `app/services/course_import.py` (unit-tested in isolation); the endpoint in `app/routers/courses.py` orchestrates role → mode, scoping queries, per-row validation, and the `dry_run` preview/commit. The Flutter UI reuses the existing bulk-import screen pattern.

**Tech Stack:** Python 3.13, FastAPI, SQLAlchemy 2.0 (typed `Mapped`), pytest + FastAPI `TestClient`, `openpyxl` (new), Flutter/GetX/Dio.

## Global Constraints

- Per-row independence: a bad row is appended to `skipped` with a `reason` and the batch continues. Never abort the whole import for one bad row. (Copied from the lecturer importer contract.)
- `dry_run=true` must persist nothing: build the same `created`/`skipped` breakdown, then `db.rollback()`. `dry_run=false` commits.
- Response shape is always `{"created": [...], "skipped": [...], "dry_run": <bool>}`.
- Permission for the endpoint is exactly `{faculty_head, university_admin}`. Super admin and timetable officers get `403`.
- Duplicates are skipped, never overwritten (v1). No PDF. No upsert. No new lecturer-assignment endpoint (existing `PUT /courses/{id}` covers it).
- Lecturer notes use a plain hyphen: `"not found - assign manually"` and `"ambiguous - assign manually"`.
- Course model fields (do not invent new ones): `code, name, room_type_required, level_id, department_id, university_id, lecturer_id, weekly_hours, semester`.
- Room types: `{"lecture_hall", "lab", "studio"}`; invalid/blank → `lecture_hall`.
- Run backend tests from `backend/` with `pytest`.

---

## File Structure

- **Create** `backend/app/services/__init__.py` — empty package marker.
- **Create** `backend/app/services/course_import.py` — pure helpers: `read_rows`, `normalize_name`, `match_lecturer`, `parse_int`.
- **Modify** `backend/app/routers/courses.py` — add the `bulk_import_courses` endpoint plus two private mode helpers.
- **Modify** `backend/requirements.txt` — add `openpyxl`.
- **Create** `backend/tests/test_course_import_helpers.py` — unit tests for the pure helpers.
- **Create** `backend/tests/test_course_bulk_import.py` — endpoint integration tests.
- **Create** `frontend/lib/features/bulk_import/course_bulk_import_screen.dart` — the UI screen.
- **Modify** `frontend/lib/core/routes.dart` — register the route.
- **Modify** `frontend/lib/core/widgets/app_shell.dart` — add the role-gated nav item.

---

### Task 1: File-reading helper (CSV + Excel)

**Files:**
- Create: `backend/app/services/__init__.py`
- Create: `backend/app/services/course_import.py`
- Modify: `backend/requirements.txt`
- Test: `backend/tests/test_course_import_helpers.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `read_rows(filename: str, content: bytes) -> tuple[list[str], list[dict]]` — returns `(header, rows)`. `header` is the lower-cased, trimmed column names. Each row is a dict of lower-cased column name → stripped string value. Raises `ValueError` if the file can't be read as CSV or `.xlsx`.
  - `parse_int(raw, default: int) -> int` — parse `raw` (str/None/number) to int; blank or unparseable → `default`. Accepts `"2.0"`.

- [ ] **Step 1: Add the dependency**

Add this line to `backend/requirements.txt` (alphabetical-ish, near the other libs):

```
openpyxl
```

Then install it:

Run: `pip install openpyxl`
Expected: "Successfully installed openpyxl-..." (and `et-xmlfile`).

- [ ] **Step 2: Write the failing tests**

Create `backend/tests/test_course_import_helpers.py`:

```python
import io
from openpyxl import Workbook
from app.services.course_import import read_rows, parse_int


def _xlsx_bytes(rows):
    """rows: list of lists; first list is the header. Returns .xlsx bytes."""
    wb = Workbook()
    ws = wb.active
    for r in rows:
        ws.append(r)
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def test_read_rows_csv_lowercases_header_and_strips():
    content = b"Code,Name,Level\nCEF440, Internet Programming ,400\n"
    header, rows = read_rows("courses.csv", content)
    assert header == ["code", "name", "level"]
    assert rows == [{"code": "CEF440", "name": "Internet Programming", "level": "400"}]


def test_read_rows_csv_utf8_bom():
    content = "﻿code,name\nCEF440,Internet\n".encode("utf-8")
    header, rows = read_rows("c.csv", content)
    assert header == ["code", "name"]
    assert rows[0]["code"] == "CEF440"


def test_read_rows_xlsx():
    content = _xlsx_bytes([["code", "name", "level"], ["CEF440", "Internet Programming", 400]])
    header, rows = read_rows("courses.xlsx", content)
    assert header == ["code", "name", "level"]
    # numbers from Excel are stringified
    assert rows[0] == {"code": "CEF440", "name": "Internet Programming", "level": "400"}


def test_read_rows_xlsx_skips_blank_rows():
    content = _xlsx_bytes([["code", "name"], [None, None], ["CEF440", "Internet"]])
    _, rows = read_rows("c.xlsx", content)
    assert len(rows) == 1
    assert rows[0]["code"] == "CEF440"


def test_read_rows_header_only_returns_no_rows():
    header, rows = read_rows("c.csv", b"code,name\n")
    assert header == ["code", "name"]
    assert rows == []


def test_read_rows_unreadable_raises():
    import pytest
    with pytest.raises(ValueError):
        read_rows("c.xlsx", b"this is not a real xlsx file")


def test_parse_int():
    assert parse_int("3", 2) == 3
    assert parse_int("3.0", 2) == 3
    assert parse_int("", 2) == 2
    assert parse_int(None, 2) == 2
    assert parse_int("abc", 2) == 2
    assert parse_int(4, 2) == 4
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd backend && pytest tests/test_course_import_helpers.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.services'`.

- [ ] **Step 4: Create the package and the helper**

Create `backend/app/services/__init__.py` (empty file).

Create `backend/app/services/course_import.py`:

```python
import csv
import io
from typing import Optional


def parse_int(raw, default: int) -> int:
    """Best-effort int parse. Blank/None/unparseable returns ``default``.

    Accepts spreadsheet-style floats like "2.0" (Excel stores numbers as floats).
    """
    if raw is None:
        return default
    text = str(raw).strip()
    if not text:
        return default
    try:
        return int(float(text))
    except (ValueError, TypeError):
        return default


def _normalize_cell(value) -> str:
    return "" if value is None else str(value).strip()


def read_rows(filename: str, content: bytes) -> tuple[list[str], list[dict]]:
    """Read a CSV or .xlsx upload into (header, rows).

    ``header`` is the lower-cased, trimmed column names. Each row is a dict of
    lower-cased column name -> stripped string value. Raises ``ValueError`` when
    the bytes cannot be read in the format implied by the filename.
    """
    name = (filename or "").lower()
    if name.endswith(".xlsx"):
        return _read_xlsx(content)
    return _read_csv(content)


def _read_csv(content: bytes) -> tuple[list[str], list[dict]]:
    try:
        text = content.decode("utf-8-sig")
    except (UnicodeDecodeError, ValueError):
        raise ValueError("file is not decodable text")
    reader = csv.DictReader(io.StringIO(text))
    header = [(_normalize_cell(h)).lower() for h in (reader.fieldnames or [])]
    rows = []
    for raw in reader:
        rows.append({
            (_normalize_cell(k)).lower(): _normalize_cell(v)
            for k, v in raw.items() if k is not None
        })
    return header, rows


def _read_xlsx(content: bytes) -> tuple[list[str], list[dict]]:
    from openpyxl import load_workbook
    try:
        wb = load_workbook(io.BytesIO(content), read_only=True, data_only=True)
    except Exception:
        raise ValueError("file is not a readable .xlsx")
    ws = wb.active
    if ws is None:
        return [], []
    row_iter = ws.iter_rows(values_only=True)
    try:
        header_cells = next(row_iter)
    except StopIteration:
        return [], []
    header = [(_normalize_cell(c)).lower() for c in header_cells]
    rows = []
    for cells in row_iter:
        if cells is None:
            continue
        if all(_normalize_cell(c) == "" for c in cells):
            continue
        row = {}
        for i, key in enumerate(header):
            if not key:
                continue
            row[key] = _normalize_cell(cells[i]) if i < len(cells) else ""
        rows.append(row)
    return header, rows
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd backend && pytest tests/test_course_import_helpers.py -v`
Expected: PASS (7 passed).

- [ ] **Step 6: Commit**

```bash
git add backend/app/services/__init__.py backend/app/services/course_import.py backend/requirements.txt backend/tests/test_course_import_helpers.py
git commit -m "course import: CSV/Excel row-reading helper"
```

---

### Task 2: Lecturer name matching

**Files:**
- Modify: `backend/app/services/course_import.py`
- Test: `backend/tests/test_course_import_helpers.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `normalize_name(raw: Optional[str]) -> str` — lower-cases, drops leading titles (`dr`, `prof`, `professor`, `mr`, `mrs`, `ms`, `miss`, `engr`, `rev`), collapses whitespace. Blank/None → `""`.
  - `match_lecturer(raw_name, candidates: list[tuple[int, str]]) -> tuple[Optional[int], Optional[str]]` — `candidates` is `(lecturer_id, full_name)`. Returns `(lecturer_id, None)` on exactly one name match; `(None, None)` when `raw_name` is blank (no lecturer requested); `(None, "not found - assign manually")` on zero matches; `(None, "ambiguous - assign manually")` on multiple.

- [ ] **Step 1: Write the failing tests**

Append to `backend/tests/test_course_import_helpers.py`:

```python
from app.services.course_import import normalize_name, match_lecturer


def test_normalize_name_strips_titles_and_case():
    assert normalize_name("Dr. Ateba") == "ateba"
    assert normalize_name("  Prof   John  Doe ") == "john doe"
    assert normalize_name("Mrs Jane Smith") == "jane smith"
    assert normalize_name("") == ""
    assert normalize_name(None) == ""


def test_match_lecturer_exact():
    candidates = [(1, "Dr. Ateba"), (2, "John Doe")]
    assert match_lecturer("ateba", candidates) == (1, None)
    assert match_lecturer("Dr Ateba", candidates) == (1, None)


def test_match_lecturer_blank_is_no_request():
    assert match_lecturer("", [(1, "Ateba")]) == (None, None)
    assert match_lecturer(None, [(1, "Ateba")]) == (None, None)


def test_match_lecturer_not_found():
    assert match_lecturer("Nobody", [(1, "Ateba")]) == (None, "not found - assign manually")


def test_match_lecturer_ambiguous():
    candidates = [(1, "Dr. Ateba"), (2, "Prof Ateba")]
    assert match_lecturer("Ateba", candidates) == (None, "ambiguous - assign manually")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && pytest tests/test_course_import_helpers.py -k "normalize or match" -v`
Expected: FAIL — `ImportError: cannot import name 'normalize_name'`.

- [ ] **Step 3: Implement the helpers**

Add to the top of `backend/app/services/course_import.py` (after the existing `import io`):

```python
import re
```

Append to `backend/app/services/course_import.py`:

```python
_TITLES = {"dr", "prof", "professor", "mr", "mrs", "ms", "miss", "engr", "rev"}


def normalize_name(raw: Optional[str]) -> str:
    """Lower-case a person name, drop leading honorifics, collapse whitespace."""
    if not raw:
        return ""
    text = str(raw).strip().lower().replace(".", " ")
    tokens = [t for t in re.split(r"\s+", text) if t]
    while tokens and tokens[0] in _TITLES:
        tokens.pop(0)
    return " ".join(tokens)


def match_lecturer(raw_name, candidates: list[tuple[int, str]]):
    """Resolve a free-text lecturer name to a lecturer id.

    Returns (lecturer_id, None) on a single clean match; (None, None) when no
    name was supplied; (None, note) when the name is unmatched or ambiguous.
    A messy or missing name never raises - it just leaves the course unassigned.
    """
    target = normalize_name(raw_name)
    if not target:
        return None, None
    matches = [cid for cid, full in candidates if normalize_name(full) == target]
    if len(matches) == 1:
        return matches[0], None
    if not matches:
        return None, "not found - assign manually"
    return None, "ambiguous - assign manually"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && pytest tests/test_course_import_helpers.py -v`
Expected: PASS (12 passed).

- [ ] **Step 5: Commit**

```bash
git add backend/app/services/course_import.py backend/tests/test_course_import_helpers.py
git commit -m "course import: lecturer name normalization and matching"
```

---

### Task 3: Endpoint — faculty-head mode

**Files:**
- Modify: `backend/app/routers/courses.py`
- Test: `backend/tests/test_course_bulk_import.py`

**Interfaces:**
- Consumes: `read_rows`, `match_lecturer`, `parse_int` (Task 1/2).
- Produces: `POST /courses/bulk-import/?dry_run=<bool>` (multipart `file`). Faculty-head branch. Returns `{"created", "skipped", "dry_run"}`.

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_course_bulk_import.py`:

```python
import io
from openpyxl import Workbook
from tests.conftest import make_university


def _login(client, email, password="password123"):
    r = client.post("/auth/login", json={"email": email, "password": password})
    return r.json()["access_token"]


def _headers(token):
    return {"Authorization": f"Bearer {token}"}


def setup_faculty_head(client, auth_headers, level_number=400):
    """Create uni + faculty + department + level + an active faculty head.

    Returns dict with uni, faculty, dept and the head's auth headers.
    """
    uni = make_university(client, auth_headers)
    fac = client.post("/faculties/", json={
        "name": "FET", "code": "FET", "university_id": uni["id"],
    }, headers=auth_headers).json()
    dept = client.post("/departments/", json={
        "name": "Computer Engineering", "code": "CEF", "faculty_id": fac["id"],
    }, headers=auth_headers).json()
    client.post("/levels/", json={"number": level_number, "department_id": dept["id"]},
                headers=auth_headers)
    client.post("/users/", json={
        "email": "head@test.com", "password": "password123",
        "full_name": "Head One", "role": "faculty_head",
        "university_id": uni["id"], "faculty_id": fac["id"],
    }, headers=auth_headers)
    token = _login(client, "head@test.com")
    return {"uni": uni, "fac": fac, "dept": dept, "headers": _headers(token)}


def _upload(client, headers, text, filename="courses.csv", dry_run=False):
    return client.post(
        "/courses/bulk-import/",
        params={"dry_run": dry_run},
        files={"file": (filename, io.BytesIO(text.encode()), "text/csv")},
        headers=headers,
    )


def test_faculty_head_imports_courses(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = (
        "code,name,level,department,semester\n"
        "CEF440,Internet Programming,400,Computer Engineering,1\n"
        "CEF445,Distributed Systems,400,Computer Engineering,2\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    assert r.status_code == 200
    body = r.json()
    assert len(body["created"]) == 2
    assert body["skipped"] == []
    # persisted
    listed = client.get(f"/courses/?department_id={ctx['dept']['id']}",
                        headers=ctx["headers"]).json()
    assert {c["code"] for c in listed} == {"CEF440", "CEF445"}


def test_faculty_head_dry_run_persists_nothing(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = "code,name,level,department\nCEF440,Internet Programming,400,Computer Engineering\n"
    r = _upload(client, ctx["headers"], csv_text, dry_run=True)
    assert r.status_code == 200
    assert r.json()["dry_run"] is True
    assert len(r.json()["created"]) == 1
    listed = client.get(f"/courses/?department_id={ctx['dept']['id']}",
                        headers=ctx["headers"]).json()
    assert listed == []


def test_faculty_head_skips_semester_zero(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = "code,name,level,department,semester\nCEF440,Internet Programming,400,Computer Engineering,0\n"
    r = _upload(client, ctx["headers"], csv_text)
    assert r.json()["created"] == []
    assert r.json()["skipped"][0]["code"] == "CEF440"
    assert "university admin" in r.json()["skipped"][0]["reason"]


def test_faculty_head_skips_unknown_department_and_level(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = (
        "code,name,level,department\n"
        "CEF440,Internet Programming,400,Nonexistent Dept\n"   # bad dept
        "CEF441,Networks,999,Computer Engineering\n"           # bad level
        "CEF442,Databases,400,Computer Engineering\n"          # good
    )
    r = _upload(client, ctx["headers"], csv_text)
    body = r.json()
    assert [c["code"] for c in body["created"]] == ["CEF442"]
    reasons = {s["code"]: s["reason"] for s in body["skipped"]}
    assert "not found" in reasons["CEF440"]
    assert "not found" in reasons["CEF441"]


def test_faculty_head_skips_duplicates(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = "code,name,level,department\nCEF440,Internet Programming,400,Computer Engineering\n"
    _upload(client, ctx["headers"], csv_text)                  # first import creates it
    r = _upload(client, ctx["headers"], csv_text)              # second should skip
    assert r.json()["created"] == []
    assert r.json()["skipped"][0]["reason"] == "already exists"


def test_faculty_head_skips_in_file_duplicate(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = (
        "code,name,level,department\n"
        "CEF440,Internet Programming,400,Computer Engineering\n"
        "CEF440,Internet Programming Again,400,Computer Engineering\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    assert len(r.json()["created"]) == 1
    assert r.json()["skipped"][0]["reason"] == "duplicate row in file"


def test_bulk_import_forbidden_for_super_admin(client, auth_headers):
    # auth_headers is the super_admin from conftest
    r = _upload(client, auth_headers,
                "code,name,level,department\nCEF440,X,400,Computer Engineering\n")
    assert r.status_code == 403


def test_bulk_import_rejects_unreadable_file(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    r = client.post(
        "/courses/bulk-import/",
        files={"file": ("courses.xlsx", io.BytesIO(b"not a real xlsx"), "application/octet-stream")},
        headers=ctx["headers"],
    )
    assert r.status_code == 400
    assert "CSV or Excel" in r.json()["detail"]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && pytest tests/test_course_bulk_import.py -v`
Expected: FAIL — `404 Not Found` on `/courses/bulk-import/` (endpoint not defined yet).

- [ ] **Step 3: Implement the endpoint (faculty-head mode)**

In `backend/app/routers/courses.py`, replace the import block at the top:

```python
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.course import Course, SharedCourse
from app.models.user import User
from app.schemas.course import (
    CourseCreate, CourseUpdate, CourseOut,
    SharedCourseCreate, SharedCourseOut,
)
from app.core.permissions import get_current_user, require_timetable_officer
```

with:

```python
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status
from sqlalchemy import func
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.course import Course, SharedCourse
from app.models.user import User, Lecturer
from app.models.university import Faculty, Department
from app.models.academic import Level
from app.schemas.course import (
    CourseCreate, CourseUpdate, CourseOut,
    SharedCourseCreate, SharedCourseOut,
)
from app.core.permissions import get_current_user, require_timetable_officer
from app.services.course_import import read_rows, match_lecturer, parse_int

ALLOWED_ROOM_TYPES = {"lecture_hall", "lab", "studio"}
```

Then append to the end of `backend/app/routers/courses.py`:

```python
@router.post("/courses/bulk-import/")
def bulk_import_courses(
    file: UploadFile = File(...),
    dry_run: bool = False,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Bulk-create courses from a CSV or Excel (.xlsx) file.

    The caller's role selects the mode. A faculty head imports departmental
    courses (semester 1 or 2) into their own faculty; a university admin imports
    year-long university-wide requirements (semester 0). Every row is
    independent: a bad row is skipped with a reason rather than aborting the
    batch. With ``dry_run=true`` the same breakdown is returned but nothing is
    written (this drives the preview the user confirms).
    """
    if current_user.role not in ("faculty_head", "university_admin"):
        raise HTTPException(
            status_code=403,
            detail="Only faculty heads and university admins can bulk-import courses.",
        )

    content = file.file.read()
    try:
        header, rows = read_rows(file.filename or "", content)
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail="That file could not be read. Please upload a CSV or Excel "
                   "(.xlsx) file.",
        )

    if current_user.role == "faculty_head":
        return _import_faculty_courses(db, current_user, header, rows, dry_run)
    return _import_university_courses(db, current_user, header, rows, dry_run)


def _normalize_room_type(raw) -> str:
    room_type = (raw or "").strip().lower()
    return room_type if room_type in ALLOWED_ROOM_TYPES else "lecture_hall"


def _import_faculty_courses(db, user, header, rows, dry_run):
    required = {"code", "name", "level", "department"}
    if not required.issubset(set(header)):
        raise HTTPException(
            status_code=400,
            detail="File must contain columns: code, name, level, department "
                   "(semester, weekly_hours, room_type, lecturer are optional).",
        )

    depts = db.query(Department).filter(Department.faculty_id == user.faculty_id).all()
    dept_by_name = {d.name.strip().lower(): d for d in depts}
    dept_ids = [d.id for d in depts]

    levels = (
        db.query(Level).filter(Level.department_id.in_(dept_ids)).all()
        if dept_ids else []
    )
    level_by_key = {(l.department_id, l.number): l for l in levels}

    # Lecturers of these departments, grouped by department for scoped matching.
    candidates_by_dept: dict[int, list[tuple[int, str]]] = {}
    if dept_ids:
        lect_rows = (
            db.query(Lecturer, User)
            .join(User, Lecturer.user_id == User.id)
            .filter(Lecturer.department_id.in_(dept_ids))
            .all()
        )
        for lect, u in lect_rows:
            candidates_by_dept.setdefault(lect.department_id, []).append(
                (lect.id, u.full_name)
            )

    created, skipped, seen = [], [], set()

    for row in rows:
        code = (row.get("code") or "").strip()
        name = (row.get("name") or "").strip()
        level_raw = (row.get("level") or "").strip()
        dept_name = (row.get("department") or "").strip()

        if not (code and name and level_raw and dept_name):
            skipped.append({"code": code or "(missing)", "reason": "missing required field"})
            continue

        dept = dept_by_name.get(dept_name.lower())
        if not dept:
            skipped.append({"code": code,
                            "reason": f"department '{dept_name}' not found in your faculty"})
            continue

        try:
            level_num = int(float(level_raw))
        except (ValueError, TypeError):
            skipped.append({"code": code, "reason": f"level '{level_raw}' is not a number"})
            continue

        level = level_by_key.get((dept.id, level_num))
        if not level:
            skipped.append({"code": code,
                            "reason": f"level {level_num} not found in department '{dept.name}'"})
            continue

        sem_raw = (row.get("semester") or "").strip()
        if not sem_raw:
            semester = 1
        else:
            try:
                semester = int(float(sem_raw))
            except (ValueError, TypeError):
                skipped.append({"code": code, "reason": f"semester '{sem_raw}' is not a number"})
                continue
        if semester == 0:
            skipped.append({"code": code,
                            "reason": "year-long courses are added by the university admin, not here"})
            continue
        if semester not in (1, 2):
            skipped.append({"code": code, "reason": f"semester {semester} must be 1 or 2"})
            continue

        weekly_hours = parse_int(row.get("weekly_hours"), 2)
        room_type = _normalize_room_type(row.get("room_type"))

        key = (dept.id, level.id, code.lower())
        if key in seen:
            skipped.append({"code": code, "reason": "duplicate row in file"})
            continue
        exists = (
            db.query(Course)
            .filter(Course.department_id == dept.id,
                    Course.level_id == level.id,
                    func.lower(Course.code) == code.lower())
            .first()
        )
        if exists:
            skipped.append({"code": code, "reason": "already exists"})
            continue
        seen.add(key)

        lecturer_raw = (row.get("lecturer") or "").strip()
        lect_id, lect_note = match_lecturer(lecturer_raw, candidates_by_dept.get(dept.id, []))

        entry = {
            "code": code, "name": name, "level": level_num,
            "department": dept.name, "semester": semester,
            "lecturer": lecturer_raw or None, "lecturer_note": lect_note,
        }

        if not dry_run:
            db.add(Course(
                code=code, name=name, room_type_required=room_type,
                level_id=level.id, department_id=dept.id, university_id=None,
                lecturer_id=lect_id, weekly_hours=weekly_hours, semester=semester,
            ))
        created.append(entry)

    if dry_run:
        db.rollback()
    else:
        db.commit()
    return {"created": created, "skipped": skipped, "dry_run": dry_run}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && pytest tests/test_course_bulk_import.py -v`
Expected: PASS for all faculty-head tests. (`_import_university_courses` is referenced but not called by these tests; it is defined in Task 4. To keep this task self-contained and importable, add a stub now — see Step 5.)

- [ ] **Step 5: Add a temporary stub so the module imports**

Add this stub near `_import_faculty_courses` (it will be replaced in Task 4):

```python
def _import_university_courses(db, user, header, rows, dry_run):
    raise HTTPException(status_code=501, detail="Not implemented yet")
```

Re-run: `cd backend && pytest tests/test_course_bulk_import.py -v`
Expected: PASS (8 passed).

- [ ] **Step 6: Commit**

```bash
git add backend/app/routers/courses.py backend/tests/test_course_bulk_import.py
git commit -m "course bulk import endpoint: faculty-head mode"
```

---

### Task 4: Endpoint — university-admin mode

**Files:**
- Modify: `backend/app/routers/courses.py`
- Test: `backend/tests/test_course_bulk_import.py`

**Interfaces:**
- Consumes: `read_rows`, `match_lecturer`, `parse_int`, `_normalize_room_type` (Task 3).
- Produces: university-admin branch of `POST /courses/bulk-import/` (semester forced 0, university-wide courses).

- [ ] **Step 1: Write the failing tests**

Append to `backend/tests/test_course_bulk_import.py`:

```python
def _login_admin(client, auth_headers):
    """make_university creates a university admin admin_<slug>@test.com. Log in."""
    uni = make_university(client, auth_headers)
    token = _login(client, "admin_ub@test.com")
    return uni, _headers(token)


def test_university_admin_imports_year_long_courses(client, auth_headers):
    uni, admin_headers = _login_admin(client, auth_headers)
    csv_text = "code,name\nUB101,Use of English\nUB102,Civics\n"
    r = _upload(client, admin_headers, csv_text)
    assert r.status_code == 200
    body = r.json()
    assert len(body["created"]) == 2
    assert all(c["semester"] == 0 for c in body["created"])
    listed = client.get(f"/courses/?university_id={uni['id']}", headers=admin_headers).json()
    assert {c["code"] for c in listed} == {"UB101", "UB102"}
    assert all(c["department_id"] is None and c["semester"] == 0 for c in listed)


def test_university_admin_skips_duplicate(client, auth_headers):
    uni, admin_headers = _login_admin(client, auth_headers)
    csv_text = "code,name\nUB101,Use of English\n"
    _upload(client, admin_headers, csv_text)
    r = _upload(client, admin_headers, csv_text)
    assert r.json()["created"] == []
    assert r.json()["skipped"][0]["reason"] == "already exists"


def test_university_admin_missing_columns(client, auth_headers):
    _, admin_headers = _login_admin(client, auth_headers)
    r = _upload(client, admin_headers, "code\nUB101\n")   # no name column
    assert r.status_code == 400
    assert "code, name" in r.json()["detail"]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && pytest tests/test_course_bulk_import.py -k university -v`
Expected: FAIL — `501` / "Not implemented yet".

- [ ] **Step 3: Replace the stub with the real implementation**

In `backend/app/routers/courses.py`, replace the `_import_university_courses` stub from Task 3 with:

```python
def _import_university_courses(db, user, header, rows, dry_run):
    required = {"code", "name"}
    if not required.issubset(set(header)):
        raise HTTPException(
            status_code=400,
            detail="File must contain columns: code, name "
                   "(weekly_hours, room_type, lecturer are optional).",
        )

    lect_rows = (
        db.query(Lecturer, User)
        .join(User, Lecturer.user_id == User.id)
        .filter(User.university_id == user.university_id)
        .all()
    )
    candidates = [(lect.id, u.full_name) for lect, u in lect_rows]

    created, skipped, seen = [], [], set()

    for row in rows:
        code = (row.get("code") or "").strip()
        name = (row.get("name") or "").strip()
        if not (code and name):
            skipped.append({"code": code or "(missing)", "reason": "missing required field"})
            continue

        weekly_hours = parse_int(row.get("weekly_hours"), 2)
        room_type = _normalize_room_type(row.get("room_type"))

        if code.lower() in seen:
            skipped.append({"code": code, "reason": "duplicate row in file"})
            continue
        exists = (
            db.query(Course)
            .filter(Course.university_id == user.university_id,
                    Course.department_id.is_(None),
                    func.lower(Course.code) == code.lower())
            .first()
        )
        if exists:
            skipped.append({"code": code, "reason": "already exists"})
            continue
        seen.add(code.lower())

        lecturer_raw = (row.get("lecturer") or "").strip()
        lect_id, lect_note = match_lecturer(lecturer_raw, candidates)

        entry = {
            "code": code, "name": name, "semester": 0,
            "lecturer": lecturer_raw or None, "lecturer_note": lect_note,
        }
        if not dry_run:
            db.add(Course(
                code=code, name=name, room_type_required=room_type,
                level_id=None, department_id=None,
                university_id=user.university_id,
                lecturer_id=lect_id, weekly_hours=weekly_hours, semester=0,
            ))
        created.append(entry)

    if dry_run:
        db.rollback()
    else:
        db.commit()
    return {"created": created, "skipped": skipped, "dry_run": dry_run}
```

- [ ] **Step 4: Run the whole import test file to verify it passes**

Run: `cd backend && pytest tests/test_course_bulk_import.py -v`
Expected: PASS (11 passed).

- [ ] **Step 5: Run the full backend suite to confirm no regressions**

Run: `cd backend && pytest -q`
Expected: all tests pass (previous green count + the new ~23 assertions across the two new files).

- [ ] **Step 6: Commit**

```bash
git add backend/app/routers/courses.py backend/tests/test_course_bulk_import.py
git commit -m "course bulk import endpoint: university-admin mode"
```

---

### Task 5: Flutter course bulk-import screen

**Files:**
- Create: `frontend/lib/features/bulk_import/course_bulk_import_screen.dart`
- Modify: `frontend/lib/core/routes.dart`
- Modify: `frontend/lib/core/widgets/app_shell.dart`

**Interfaces:**
- Consumes: `POST /courses/bulk-import/` (Tasks 3-4); `AuthController.to.user`/`token`; `AppConstants.baseUrl`.
- Produces: route `AppRoutes.courseBulkImport = '/course-bulk-import'`; a nav item visible only to `faculty_head` and `university_admin`.

- [ ] **Step 1: Create the screen**

Create `frontend/lib/features/bulk_import/course_bulk_import_screen.dart`:

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';

import '../../core/constants.dart';
import '../../core/controllers/auth_controller.dart';

class CourseBulkImportScreen extends StatefulWidget {
  const CourseBulkImportScreen({super.key});

  @override
  State<CourseBulkImportScreen> createState() => _CourseBulkImportScreenState();
}

class _CourseBulkImportScreenState extends State<CourseBulkImportScreen> {
  String? _fileName;
  Uint8List? _fileBytes;
  bool _uploading = false;
  Map<String, dynamic>? _preview;
  Map<String, dynamic>? _result;
  String? _error;

  bool get _isFacultyHead =>
      AuthController.to.user.value?.isFacultyHead ?? false;

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    setState(() {
      _fileName = file.name;
      _fileBytes = file.bytes;
      _preview = null;
      _result = null;
      _error = null;
    });
  }

  Future<void> _runImport({required bool dryRun}) async {
    if (_fileBytes == null || _fileName == null) return;
    setState(() {
      _uploading = true;
      _error = null;
      if (dryRun) { _preview = null; _result = null; }
    });
    try {
      final token = AuthController.to.token;
      final dio = Dio(BaseOptions(
        baseUrl: AppConstants.baseUrl,
        headers: {'Authorization': 'Bearer $token'},
      ));
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(_fileBytes!, filename: _fileName),
      });
      final response = await dio.post(
        '/courses/bulk-import/',
        data: formData,
        queryParameters: {'dry_run': dryRun},
      );
      setState(() {
        if (dryRun) {
          _preview = response.data as Map<String, dynamic>;
        } else {
          _result = response.data as Map<String, dynamic>;
          _preview = null;
        }
      });
    } on DioException catch (e) {
      final data = e.response?.data;
      final detail = (data is Map) ? data['detail'] as String? : null;
      setState(() => _error = detail ?? e.message ?? 'Import failed. Please try again.');
    } catch (e) {
      setState(() => _error = 'Import failed: $e');
    } finally {
      setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final createdCount = (_preview?['created'] as List?)?.length ?? 0;

    return CustomScrollView(
      slivers: [
        const SliverAppBar(pinned: true, title: Text('Bulk Import Courses')),
        SliverPadding(
          padding: const EdgeInsets.all(24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Format help (role-aware)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.info_outline, color: cs.primary),
                        const SizedBox(width: 10),
                        Text('File Format (CSV or Excel)',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 12),
                      if (_isFacultyHead) ...const [
                        _FormatRow('code', 'Course code, e.g. CEF440', required: true),
                        _FormatRow('name', 'Course name', required: true),
                        _FormatRow('level', 'Year of study: 200, 300, 400', required: true),
                        _FormatRow('department', 'Department in your faculty', required: true),
                        _FormatRow('semester', '1 or 2 (year-long is university-wide)', required: false),
                        _FormatRow('weekly_hours', 'Hours per week (default 2)', required: false),
                        _FormatRow('room_type', 'lecture_hall / lab / studio', required: false),
                        _FormatRow('lecturer', 'Lecturer name (auto-matched)', required: false),
                      ] else ...const [
                        _FormatRow('code', 'Course code, e.g. UB101', required: true),
                        _FormatRow('name', 'Course name', required: true),
                        _FormatRow('weekly_hours', 'Hours per week (default 2)', required: false),
                        _FormatRow('room_type', 'lecture_hall / lab / studio', required: false),
                        _FormatRow('lecturer', 'Lecturer name (auto-matched)', required: false),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Text(
                          _isFacultyHead
                              ? 'code,name,level,department,semester,lecturer\n'
                                'CEF440,Internet Programming,400,Computer Engineering,1,Dr. Ateba\n'
                                'CEF445,Distributed Systems,400,Computer Engineering,2,\n'
                              : 'code,name,lecturer\n'
                                'UB101,Use of English,\n'
                                'UB102,Civics and Ethics,\n',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12,
                              color: cs.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isFacultyHead
                            ? 'Courses are created in your faculty. Department and '
                              'level are matched by name/number. A lecturer name is '
                              'optional: a clean match is assigned, anything else is '
                              'left for you to assign manually.'
                            : 'These are year-long university-wide requirements '
                              '(semester is set automatically). A lecturer name is '
                              'optional and auto-matched.',
                        style: TextStyle(fontSize: 12, color: cs.outline),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // File picker
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Upload File',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: _uploading ? null : _pickFile,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _fileName != null ? cs.primary : cs.outlineVariant,
                              width: _fileName != null ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: _fileName != null
                                ? cs.primaryContainer.withAlpha(40) : null,
                          ),
                          child: Column(children: [
                            Icon(
                              _fileName != null
                                  ? Icons.check_circle_outline
                                  : Icons.upload_file_outlined,
                              size: 40,
                              color: _fileName != null ? cs.primary : cs.outline,
                            ),
                            const SizedBox(height: 12),
                            Text(_fileName ?? 'Click to select a CSV or Excel file',
                                style: TextStyle(
                                  color: _fileName != null ? cs.primary : cs.outline,
                                  fontWeight: _fileName != null
                                      ? FontWeight.w600 : FontWeight.normal,
                                )),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _uploading ? null : _pickFile,
                            child: const Text('Change File'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: (_fileBytes == null || _uploading)
                                ? null : () => _runImport(dryRun: true),
                            icon: _uploading
                                ? const SizedBox(width: 16, height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.fact_check_outlined, size: 18),
                            label: Text(_uploading ? 'Checking...' : 'Preview'),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: cs.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Icon(Icons.error_outline, color: cs.error),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_error!,
                          style: TextStyle(color: cs.onErrorContainer))),
                    ]),
                  ),
                ),
              ],

              // Preview
              if (_preview != null) ...[
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.preview_outlined, color: cs.primary),
                          const SizedBox(width: 10),
                          Text('Preview - nothing saved yet',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          'Will create $createdCount  ·  '
                          'Will skip ${(_preview!['skipped'] as List?)?.length ?? 0}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cs.outline),
                        ),
                        const SizedBox(height: 12),
                        ...(_preview!['created'] as List? ?? []).map((item) {
                          final m = item as Map<String, dynamic>;
                          final note = m['lecturer_note'] as String?;
                          final lecturer = m['lecturer'] as String?;
                          return _PreviewCourseRow(
                            code: m['code'] as String? ?? '',
                            name: m['name'] as String? ?? '',
                            subtitle: [
                              if (m['level'] != null) 'L${m['level']}',
                              'S${m['semester']}',
                              if (m['department'] != null) m['department'] as String,
                            ].join('  ·  '),
                            lecturer: lecturer,
                            note: note,
                          );
                        }),
                        if ((_preview!['skipped'] as List?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 12),
                          Text('Will be skipped:',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: cs.outline)),
                          const SizedBox(height: 4),
                          ...(_preview!['skipped'] as List).map((item) {
                            final m = item as Map<String, dynamic>;
                            return Text('• ${m['code']} — ${m['reason']}',
                                style: TextStyle(fontSize: 12, color: cs.outline));
                          }),
                        ],
                        const SizedBox(height: 16),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _uploading
                                  ? null : () => setState(() => _preview = null),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: (createdCount == 0 || _uploading)
                                  ? null : () => _runImport(dryRun: false),
                              icon: _uploading
                                  ? const SizedBox(width: 16, height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check, size: 18),
                              label: Text('Create $createdCount course'
                                  '${createdCount == 1 ? '' : 's'}'),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],

              // Result
              if (_result != null) ...[
                const SizedBox(height: 24),
                Text(
                  'Created ${(_result!['created'] as List?)?.length ?? 0} courses  ·  '
                  'Skipped ${(_result!['skipped'] as List?)?.length ?? 0}',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                ...(_result!['created'] as List? ?? []).map((item) {
                  final m = item as Map<String, dynamic>;
                  return _PreviewCourseRow(
                    code: m['code'] as String? ?? '',
                    name: m['name'] as String? ?? '',
                    subtitle: [
                      if (m['level'] != null) 'L${m['level']}',
                      'S${m['semester']}',
                    ].join('  ·  '),
                    lecturer: m['lecturer'] as String?,
                    note: m['lecturer_note'] as String?,
                  );
                }),
                if ((_result!['skipped'] as List?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  Text('Skipped:',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: cs.outline)),
                  const SizedBox(height: 8),
                  ...(_result!['skipped'] as List).map((item) {
                    final m = item as Map<String, dynamic>;
                    return Text('• ${m['code']} — ${m['reason']}',
                        style: TextStyle(color: cs.outline, fontSize: 12));
                  }),
                ],
              ],
            ]),
          ),
        ),
      ],
    );
  }
}

class _PreviewCourseRow extends StatelessWidget {
  final String code;
  final String name;
  final String subtitle;
  final String? lecturer;
  final String? note;
  const _PreviewCourseRow({
    required this.code, required this.name, required this.subtitle,
    this.lecturer, this.note,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Badge: matched (assigned lecturer, no note), ambiguous/unassigned (note).
    final Widget badge;
    if (note == null && (lecturer?.isNotEmpty ?? false)) {
      badge = _Badge(text: 'matched: $lecturer', color: cs.primary);
    } else if (note != null) {
      badge = _Badge(text: note!, color: cs.error);
    } else {
      badge = _Badge(text: 'no lecturer', color: cs.outline);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(Icons.menu_book_outlined, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$code — $name',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(subtitle, style: TextStyle(fontSize: 11, color: cs.outline)),
          ]),
        ),
        badge,
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, color: color)),
      );
}

class _FormatRow extends StatelessWidget {
  final String column;
  final String description;
  final bool required;
  const _FormatRow(this.column, this.description, {this.required = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 130,
          child: Text(column,
              style: const TextStyle(fontFamily: 'monospace',
                  fontWeight: FontWeight.w600, fontSize: 12)),
        ),
        Expanded(child: Text(description, style: const TextStyle(fontSize: 12))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: required ? Colors.red.shade50 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(required ? 'required' : 'optional',
              style: TextStyle(fontSize: 10,
                  color: required ? Colors.red.shade700 : Colors.grey.shade600)),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 2: Register the route**

In `frontend/lib/core/routes.dart`:

Add the import near the existing bulk-import import (line ~12):

```dart
import '../features/bulk_import/course_bulk_import_screen.dart';
```

Add the route constant near `bulkImport` (line ~28):

```dart
  static const courseBulkImport = '/course-bulk-import';
```

Add the `GetPage` near the `bulkImport` page (line ~42):

```dart
    GetPage(name: courseBulkImport, page: () => const AppShell(child: CourseBulkImportScreen())),
```

- [ ] **Step 3: Add the role-gated nav item**

In `frontend/lib/core/widgets/app_shell.dart`, inside the `_secondary` list (after the existing "Bulk Import" `_Dest`, around line 68), add:

```dart
    _Dest(
      icon: Icons.library_books_outlined, activeIcon: Icons.library_books,
      label: 'Import Courses', route: AppRoutes.courseBulkImport,
      // Only the two roles the endpoint accepts. canManageUniversity is
      // university_admin (not super_admin); plus faculty heads.
      visible: (u) => u.canManageUniversity || u.isFacultyHead,
    ),
```

- [ ] **Step 4: Verify the app builds**

Run: `cd frontend && flutter analyze`
Expected: "No issues found!" (or only pre-existing warnings unrelated to these files).

- [ ] **Step 5: Manual verification**

Start the backend and `cd frontend && flutter run -d chrome`. Log in as a faculty head, open **Import Courses**, upload a CSV like the example, click **Preview** (nothing saved), confirm the created/skipped/lecturer badges look right, then **Create**. Verify the courses appear in the courses list. Log in as a university admin and confirm the same screen shows the year-long template. Confirm a super admin and a timetable officer do **not** see the nav item.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/features/bulk_import/course_bulk_import_screen.dart frontend/lib/core/routes.dart frontend/lib/core/widgets/app_shell.dart
git commit -m "course bulk import UI: role-aware upload screen and nav entry"
```

---

## Self-Review Notes

- **Spec coverage:** role-aware single endpoint (T3/T4), CSV+Excel (T1), column templates + validation (T3/T4), semester rules per role (T3 rejects 0, T4 forces 0; T4 tests reject non-empty semester implicitly by ignoring it — university mode has no semester column), lecturer auto-match never fatal (T2, wired T3/T4), skip-only duplicates (T3/T4), preview/response shape (T3/T4), role-gated UI with no 403 surface (T5), tests (all tasks). PDF/upsert/super-admin explicitly excluded.
- **Type consistency:** `read_rows -> (header, rows)`, `match_lecturer -> (id|None, note|None)`, `parse_int(raw, default)` used consistently across T1-T4. Notes use plain hyphen everywhere.
- **One gap intentionally deferred:** university-admin mode ignores any `semester` column rather than rejecting semester 1/2 rows — university-wide courses are year-long by definition, so there is no semester column in that template. If you want an explicit skip for a stray `semester=1` in an admin file, add it in T4; left out to honor YAGNI.
```