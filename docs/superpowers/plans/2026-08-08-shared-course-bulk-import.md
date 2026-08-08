# Shared Courses in Course Bulk Import — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a faculty head list several departments (separated by `|`) for one course row in the course bulk import, so the course is created once in the owner department and shared — via `SharedCourse` links — to the matching-level classes of the other departments, mirroring the manual share flow.

**Architecture:** Extend `_import_faculty_courses` in `backend/app/routers/courses.py`. The first department in the cell owns the `Course` (unchanged single-department path); each additional department is resolved to its Level with the same number, and the course is linked to every `Class` at that level via `SharedCourse`. Sharing is best-effort: an unresolvable shared department is recorded in a per-row `shared_note` and never aborts the row. The frontend course-import screen shows the shared departments and any `shared_note`.

**Tech Stack:** FastAPI + SQLAlchemy + pytest (backend); Flutter + GetX (frontend). Flutter package: `university_timetabling`.

## Global Constraints

- **Faculty-head mode only.** `_import_university_courses` (university-wide, semester 0) is unchanged.
- **Delimiter is `|`** between department names in the `department` cell. First name = owner; the rest = shared. Each name is trimmed; empty segments ignored.
- **Same level number** applies to the owner and every shared department (the existing single `level` column).
- **Shares link ALL classes at each shared department's Level with the given number**, deduplicated by class id.
- **Best-effort, never fatal:** after the owner course is created, a shared department that is missing / outside the faculty / has no matching level / has no classes is recorded in the row's `shared_note`; the owner course is still created. `shared_note` is `null` when every shared department wired successfully (and for single-department rows).
- **Existing owner course → skip the whole row** with `"already exists"` (unchanged); no shares added.
- Response `created` entries gain `shared_with` (list of wired shared department names) and `shared_note` (string|null). `department` stays the owner name. Single-department rows yield `shared_with: []`, `shared_note: null` (backward compatible).
- `dry_run=true` persists nothing, including no `SharedCourse` rows.
- Backend: the full pytest suite must stay green (currently 186 passing; this plan adds tests).
- Frontend: `flutter analyze` introduces no new issues beyond the repo's 37-info baseline.
- Commit messages: plain sentences, no `feat:`/`fix:` prefixes, no `Co-Authored-By` line.

---

## File Map

- Modify: `backend/app/routers/courses.py` — import `Class`; preload classes-by-level; multi-department parsing, shared linking, response fields, and flush+`SharedCourse` inserts in `_import_faculty_courses`.
- Test: `backend/tests/test_course_bulk_import.py` — a helper to add a shared department (dept + level + class) and shared-course tests.
- Modify: `frontend/lib/features/bulk_import/course_bulk_import_screen.dart` — faculty-head format help/sample for the `|` syntax; show `shared_with` and `shared_note` in preview/result rows.

---

## Task 1: Backend — multi-department shared courses in faculty-head import

**Files:**
- Modify: `backend/app/routers/courses.py:8` (import), `:207-211` (preload), `_import_faculty_courses` body (`:229-308`)
- Test: `backend/tests/test_course_bulk_import.py`

**Interfaces:**
- Consumes: `Course`, `SharedCourse` (`app.models.course`, already imported at `courses.py:5`); `Level`, `Class` (`app.models.academic`); `match_lecturer`, `parse_int` (`app.services.course_import`).
- Produces: `POST /courses/bulk-import/` faculty-head response `created[]` entries now carry `shared_with: list[str]` and `shared_note: str | None`; `SharedCourse(course_id, class_id)` rows are created for shared departments' level classes.

- [ ] **Step 1: Add a shared-department helper and the failing tests**

Append to `backend/tests/test_course_bulk_import.py`. First, a helper that adds a second department in the same faculty with a level and a class (place it after `setup_faculty_head`):

```python
def _add_dept_with_class(client, auth_headers, fac, name, code,
                         level_number=400, class_name=None, population=100,
                         with_class=True):
    """Add a department to `fac` with a Level `level_number` and (optionally) one Class.

    Returns {"dept", "level", "class"} (class is None when with_class=False).
    """
    dept = client.post("/departments/", json={
        "name": name, "code": code, "faculty_id": fac["id"],
    }, headers=auth_headers).json()
    level = client.post("/levels/", json={
        "number": level_number, "department_id": dept["id"],
    }, headers=auth_headers).json()
    cls = None
    if with_class:
        cls = client.post("/classes/", json={
            "name": class_name or f"{code}{level_number}",
            "population": population, "level_id": level["id"],
        }, headers=auth_headers).json()
    return {"dept": dept, "level": level, "class": cls}
```

Then the tests:

```python
def test_shared_course_links_other_department(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)  # owner: Computer Engineering, level 400
    ee = _add_dept_with_class(client, auth_headers, ctx["fac"],
                              "Electrical Engineering", "EEF", 400, "EEF400")
    csv_text = (
        "code,name,level,department,semester\n"
        "CEF201,Circuits,400,Computer Engineering | Electrical Engineering,1\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    assert r.status_code == 200
    body = r.json()
    assert len(body["created"]) == 1
    entry = body["created"][0]
    assert entry["department"] == "Computer Engineering"
    assert entry["shared_with"] == ["Electrical Engineering"]
    assert entry["shared_note"] is None
    # The course was created once, in the owner department...
    listed = client.get(f"/courses/?department_id={ctx['dept']['id']}",
                        headers=ctx["headers"]).json()
    course = next(c for c in listed if c["code"] == "CEF201")
    # ...and linked to the Electrical Engineering level-400 class.
    shared = client.get(f"/courses/{course['id']}/shared",
                        headers=ctx["headers"]).json()
    assert [s["class_id"] for s in shared] == [ee["class"]["id"]]


def test_shared_course_note_when_shared_dept_has_no_class(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    _add_dept_with_class(client, auth_headers, ctx["fac"],
                         "Electrical Engineering", "EEF", 400, with_class=False)
    csv_text = (
        "code,name,level,department\n"
        "CEF201,Circuits,400,Computer Engineering | Electrical Engineering\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    body = r.json()
    assert len(body["created"]) == 1
    entry = body["created"][0]
    assert entry["shared_with"] == []
    assert "has no classes" in entry["shared_note"]
    # Owner course still created.
    listed = client.get(f"/courses/?department_id={ctx['dept']['id']}",
                        headers=ctx["headers"]).json()
    assert any(c["code"] == "CEF201" for c in listed)


def test_shared_course_unknown_shared_dept_is_noted(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = (
        "code,name,level,department\n"
        "CEF201,Circuits,400,Computer Engineering | Ghost Department\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    entry = r.json()["created"][0]
    assert entry["shared_with"] == []
    assert "not found" in entry["shared_note"]


def test_single_department_row_has_empty_shared(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = "code,name,level,department\nCEF440,Internet Programming,400,Computer Engineering\n"
    entry = _upload(client, ctx["headers"], csv_text).json()["created"][0]
    assert entry["shared_with"] == []
    assert entry["shared_note"] is None


def test_shared_course_dry_run_persists_no_links(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    ee = _add_dept_with_class(client, auth_headers, ctx["fac"],
                              "Electrical Engineering", "EEF", 400, "EEF400")
    csv_text = (
        "code,name,level,department\n"
        "CEF201,Circuits,400,Computer Engineering | Electrical Engineering\n"
    )
    r = _upload(client, ctx["headers"], csv_text, dry_run=True)
    body = r.json()
    assert body["dry_run"] is True
    assert body["created"][0]["shared_with"] == ["Electrical Engineering"]
    # Nothing persisted: no course, hence no shared links.
    listed = client.get(f"/courses/?department_id={ctx['dept']['id']}",
                        headers=ctx["headers"]).json()
    assert listed == []


def test_shared_course_xlsx(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    ee = _add_dept_with_class(client, auth_headers, ctx["fac"],
                              "Electrical Engineering", "EEF", 400, "EEF400")
    content = _xlsx_bytes([
        ["code", "name", "level", "department"],
        ["CEF201", "Circuits", 400, "Computer Engineering | Electrical Engineering"],
    ])
    r = _upload_xlsx(client, ctx["headers"], content)
    assert r.status_code == 200
    entry = r.json()["created"][0]
    assert entry["shared_with"] == ["Electrical Engineering"]
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `cd backend && python -m pytest tests/test_course_bulk_import.py -k "shared or single_department_row" -q`
Expected: FAIL — `_import_faculty_courses` doesn't split on `|` yet (the whole `"Computer Engineering | Electrical Engineering"` string won't match a department, so those rows are skipped), and entries have no `shared_with`/`shared_note` keys → `KeyError`/assertion failures.

- [ ] **Step 3: Import the `Class` model**

In `backend/app/routers/courses.py`, line 8 currently reads:

```python
from app.models.academic import Level
```

Change it to:

```python
from app.models.academic import Level, Class
```

- [ ] **Step 4: Preload classes grouped by level**

In `_import_faculty_courses`, the block that builds `level_by_key` (lines 207-211) currently reads:

```python
    levels = (
        db.query(Level).filter(Level.department_id.in_(dept_ids)).all()
        if dept_ids else []
    )
    level_by_key = {(l.department_id, l.number): l for l in levels}
```

Add a classes-by-level map immediately after it:

```python
    levels = (
        db.query(Level).filter(Level.department_id.in_(dept_ids)).all()
        if dept_ids else []
    )
    level_by_key = {(l.department_id, l.number): l for l in levels}

    # Classes at each level, for wiring shared courses to other departments.
    level_ids = [l.id for l in levels]
    classes = (
        db.query(Class).filter(Class.level_id.in_(level_ids)).all()
        if level_ids else []
    )
    classes_by_level: dict[int, list[Class]] = {}
    for c in classes:
        classes_by_level.setdefault(c.level_id, []).append(c)
```

- [ ] **Step 5: Parse the department cell into owner + shared**

In the row loop, the department read + resolution (lines 233, 235-243) currently reads:

```python
        dept_name = (row.get("department") or "").strip()

        if not (code and name and level_raw and dept_name):
            skipped.append({"code": code or "(missing)", "reason": "missing required field"})
            continue

        dept = dept_by_name.get(dept_name.lower())
        if not dept:
            skipped.append({"code": code,
                            "reason": f"department '{dept_name}' not found in your faculty"})
            continue
```

Replace it with owner/shared parsing:

```python
        dept_raw = (row.get("department") or "").strip()

        if not (code and name and level_raw and dept_raw):
            skipped.append({"code": code or "(missing)", "reason": "missing required field"})
            continue

        # First department owns the course; the rest are shared with it.
        dept_names = [d.strip() for d in dept_raw.split("|") if d.strip()]
        owner_name = dept_names[0]
        shared_names = dept_names[1:]

        dept = dept_by_name.get(owner_name.lower())
        if not dept:
            skipped.append({"code": code,
                            "reason": f"department '{owner_name}' not found in your faculty"})
            continue
```

(The `level`, `semester`, `weekly_hours`, `room_type`, in-file duplicate, and `already exists` checks that follow are unchanged — they are all keyed on the owner `dept` and `level`.)

- [ ] **Step 6: Resolve shared departments and build the entry**

The lecturer-match + entry block (lines 293-300) currently reads:

```python
        lecturer_raw = (row.get("lecturer") or "").strip()
        lect_id, lect_note = match_lecturer(lecturer_raw, candidates_by_dept.get(dept.id, []))

        entry = {
            "code": code, "name": name, "level": level_num,
            "department": dept.name, "semester": semester,
            "lecturer": lecturer_raw or None, "lecturer_note": lect_note,
        }
```

Replace it with shared resolution + the extended entry:

```python
        lecturer_raw = (row.get("lecturer") or "").strip()
        lect_id, lect_note = match_lecturer(lecturer_raw, candidates_by_dept.get(dept.id, []))

        # Resolve shared departments (best-effort; a problem is noted, never fatal).
        shared_with, shared_problems, shared_class_ids = [], [], []
        seen_share_ids = set()
        for sname in shared_names:
            sdept = dept_by_name.get(sname.lower())
            if not sdept:
                shared_problems.append(f"{sname}: department not found in your faculty - not shared")
                continue
            if sdept.id == dept.id:
                continue  # owner listed again; its own classes are already covered
            slevel = level_by_key.get((sdept.id, level_num))
            if not slevel:
                shared_problems.append(f"{sdept.name}: no level {level_num} - not shared")
                continue
            sclasses = classes_by_level.get(slevel.id, [])
            if not sclasses:
                shared_problems.append(f"{sdept.name}: level {level_num} has no classes - not shared")
                continue
            shared_with.append(sdept.name)
            for c in sclasses:
                if c.id not in seen_share_ids:
                    seen_share_ids.add(c.id)
                    shared_class_ids.append(c.id)
        shared_note = "; ".join(shared_problems) or None

        entry = {
            "code": code, "name": name, "level": level_num,
            "department": dept.name, "shared_with": shared_with,
            "semester": semester,
            "lecturer": lecturer_raw or None, "lecturer_note": lect_note,
            "shared_note": shared_note,
        }
```

- [ ] **Step 7: Create the course and its shared links (non-dry-run)**

The persist block (lines 302-308) currently reads:

```python
        if not dry_run:
            db.add(Course(
                code=code, name=name, room_type_required=room_type,
                level_id=level.id, department_id=dept.id, university_id=None,
                lecturer_id=lect_id, weekly_hours=weekly_hours, semester=semester,
            ))
        created.append(entry)
```

Replace it so the course id is available for the `SharedCourse` links:

```python
        if not dry_run:
            course = Course(
                code=code, name=name, room_type_required=room_type,
                level_id=level.id, department_id=dept.id, university_id=None,
                lecturer_id=lect_id, weekly_hours=weekly_hours, semester=semester,
            )
            db.add(course)
            db.flush()  # assign course.id before adding shared links
            for cid in shared_class_ids:
                db.add(SharedCourse(course_id=course.id, class_id=cid))
        created.append(entry)
```

- [ ] **Step 8: Run the new tests to verify they pass**

Run: `cd backend && python -m pytest tests/test_course_bulk_import.py -q`
Expected: PASS (all course-bulk-import tests, old and new, green).

- [ ] **Step 9: Run the full backend suite**

Run: `cd backend && python -m pytest -q`
Expected: PASS (whole suite green; count is the previous 186 plus the six new tests).

- [ ] **Step 10: Commit**

```bash
git add backend/app/routers/courses.py backend/tests/test_course_bulk_import.py
git commit -m "course bulk import: a row may list several departments so a shared course is created once and linked to the other departments' classes"
```

---

## Task 2: Frontend — show shared departments and notes in the course-import screen

**Files:**
- Modify: `frontend/lib/features/bulk_import/course_bulk_import_screen.dart`

**Interfaces:**
- Consumes: faculty-head `created[]` entries with `shared_with: list` and `shared_note: string|null` (Task 1).

- [ ] **Step 1: Update the faculty-head `department` format row**

In `course_bulk_import_screen.dart`, the faculty-head format rows (lines 111-119) include:

```dart
                        _FormatRow('department', 'Department in your faculty', required: true),
```

Change that one line to explain multi-department sharing:

```dart
                        _FormatRow('department', 'Department in your faculty; list several with | to share one course', required: true),
```

- [ ] **Step 2: Update the faculty-head sample CSV and helper text**

The sample/help block (lines 135-158) currently has, for the faculty-head branch, this sample string and explanation:

```dart
                          _isFacultyHead
                              ? 'code,name,level,department,semester,lecturer\n'
                                'CEF440,Internet Programming,400,Computer Engineering,1,Dr. Ateba\n'
                                'CEF445,Distributed Systems,400,Computer Engineering,2,\n'
                              : 'code,name,lecturer\n'
                                'UB101,Use of English,\n'
                                'UB102,Civics and Ethics,\n',
```

Change the faculty-head sample to include a shared row:

```dart
                          _isFacultyHead
                              ? 'code,name,level,department,semester,lecturer\n'
                                'CEF440,Internet Programming,400,Computer Engineering,1,Dr. Ateba\n'
                                'CEF201,Circuits,400,Computer Engineering | Electrical Engineering,1,\n'
                              : 'code,name,lecturer\n'
                                'UB101,Use of English,\n'
                                'UB102,Civics and Ethics,\n',
```

And the faculty-head explanatory text (lines 149-153):

```dart
                            ? 'Courses are created in your faculty. Department and '
                              'level are matched by name/number. A lecturer name is '
                              'optional: a clean match is assigned, anything else is '
                              'left for you to assign manually.'
```

becomes:

```dart
                            ? 'Courses are created in your faculty. Department and '
                              'level are matched by name/number. To share one course '
                              'across departments, list them separated by | (the first '
                              'owns it); it is created once and its other departments\' '
                              'classes are linked. A lecturer name is optional: a clean '
                              'match is assigned, anything else is left to assign manually.'
```

- [ ] **Step 3: Pass `shared_with`/`shared_note` into the preview rows**

In the preview `created` mapper (lines 276-291), the `_PreviewCourseRow(...)` call currently ends with `lecturer:`/`note:`. Add the two shared fields. Replace the call:

```dart
                          return _PreviewCourseRow(
                            code: m['code'] as String? ?? '',
                            name: m['name'] as String? ?? '',
                            subtitle: [
                              if (m['level'] != null) 'L${m['level']}',
                              (m['semester'] == 0 ? 'Year-long' : 'S${m['semester']}'),
                              if (m['department'] != null) m['department'] as String,
                            ].join('  ·  '),
                            lecturer: lecturer,
                            note: note,
                          );
```

with:

```dart
                          return _PreviewCourseRow(
                            code: m['code'] as String? ?? '',
                            name: m['name'] as String? ?? '',
                            subtitle: [
                              if (m['level'] != null) 'L${m['level']}',
                              (m['semester'] == 0 ? 'Year-long' : 'S${m['semester']}'),
                              if (m['department'] != null) m['department'] as String,
                            ].join('  ·  '),
                            lecturer: lecturer,
                            note: note,
                            sharedWith: (m['shared_with'] as List?)?.cast<String>() ?? const [],
                            sharedNote: m['shared_note'] as String?,
                          );
```

- [ ] **Step 4: Pass `shared_with`/`shared_note` into the result rows**

In the result `created` mapper (lines 344-356), replace the `_PreviewCourseRow(...)` call:

```dart
                  return _PreviewCourseRow(
                    code: m['code'] as String? ?? '',
                    name: m['name'] as String? ?? '',
                    subtitle: [
                      if (m['level'] != null) 'L${m['level']}',
                      (m['semester'] == 0 ? 'Year-long' : 'S${m['semester']}'),
                      if (m['department'] != null) m['department'] as String,
                    ].join('  ·  '),
                    lecturer: m['lecturer'] as String?,
                    note: m['lecturer_note'] as String?,
                  );
```

with:

```dart
                  return _PreviewCourseRow(
                    code: m['code'] as String? ?? '',
                    name: m['name'] as String? ?? '',
                    subtitle: [
                      if (m['level'] != null) 'L${m['level']}',
                      (m['semester'] == 0 ? 'Year-long' : 'S${m['semester']}'),
                      if (m['department'] != null) m['department'] as String,
                    ].join('  ·  '),
                    lecturer: m['lecturer'] as String?,
                    note: m['lecturer_note'] as String?,
                    sharedWith: (m['shared_with'] as List?)?.cast<String>() ?? const [],
                    sharedNote: m['shared_note'] as String?,
                  );
```

- [ ] **Step 5: Render shared departments and the note in `_PreviewCourseRow`**

Replace the whole `_PreviewCourseRow` widget (lines 379-418) with a version that accepts and displays the shared fields:

```dart
class _PreviewCourseRow extends StatelessWidget {
  final String code;
  final String name;
  final String subtitle;
  final String? lecturer;
  final String? note;
  final List<String> sharedWith;
  final String? sharedNote;
  const _PreviewCourseRow({
    required this.code, required this.name, required this.subtitle,
    this.lecturer, this.note,
    this.sharedWith = const [], this.sharedNote,
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
            if (sharedWith.isNotEmpty)
              Text('shared with: ${sharedWith.join(', ')}',
                  style: TextStyle(fontSize: 11, color: cs.primary)),
            if (sharedNote != null)
              Text(sharedNote!, style: TextStyle(fontSize: 11, color: cs.error)),
          ]),
        ),
        badge,
      ]),
    );
  }
}
```

- [ ] **Step 6: Verify analyze is clean**

Run: `cd frontend && flutter analyze`
Expected: introduces no new issues beyond the repo's 37-info baseline. Confirm the total count and that none of the reported issues point at `course_bulk_import_screen.dart` lines you changed.

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/features/bulk_import/course_bulk_import_screen.dart
git commit -m "course import UI: document the multi-department share syntax and show shared departments and notes on each row"
```

---

## Self-Review

**Spec coverage** (against `docs/superpowers/specs/2026-08-08-shared-course-bulk-import-design.md`):
- Faculty-head mode only; university mode untouched → Task 1 edits only `_import_faculty_courses`. ✓
- `|` delimiter, first = owner, rest = shared → Step 5. ✓
- Same level number across departments; shares link all classes at that level, deduped → Step 6 (`level_by_key.get((sdept.id, level_num))`, `classes_by_level`, `seen_share_ids`). ✓
- Best-effort/non-fatal with `shared_note` (dept not found / no level / no classes) → Step 6; tested in Steps 1 (`no_class`, `unknown_shared_dept`). ✓
- Owner listed twice is ignored (no self-linking) → Step 6 `if sdept.id == dept.id: continue`. ✓
- Existing owner course skipped `"already exists"` → unchanged existing code path (covered by existing `test_faculty_head_skips_duplicates`). ✓
- Response gains `shared_with` + `shared_note`; single-dept → `[]`/`null` → Step 6; `test_single_department_row_has_empty_shared`. ✓
- `dry_run` persists nothing incl. `SharedCourse` → Step 7 guards inserts behind `if not dry_run`; `test_shared_course_dry_run_persists_no_links`. ✓
- CSV + `.xlsx` both work → `test_shared_course_links_other_department` (CSV) + `test_shared_course_xlsx`. ✓
- Frontend shows syntax + shared departments + note → Task 2. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases". Every code step shows exact before/after. ✓

**Type consistency:** `shared_with` is a `list[str]` in the backend entry and read as `(m['shared_with'] as List?)?.cast<String>()` in the frontend; `shared_note` is `str|None` ↔ `String?`. `_PreviewCourseRow` gains `sharedWith`/`sharedNote` params used at both call sites (preview + result). `Class` imported before use. `db.flush()` precedes `SharedCourse(course_id=course.id, ...)`. ✓
