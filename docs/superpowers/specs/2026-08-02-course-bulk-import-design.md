# Course Bulk Import — Design

Date: 2026-08-02
Status: Approved (pending spec review)

## Problem

Courses are currently added one at a time through the UI. A real department
can have dozens of courses, and at the jury defense the panel flagged manual
course entry as a market-readiness gap. Departments already hold their course
lists in spreadsheets. We want the person responsible to upload that file and
have the courses created in bulk, with lecturers auto-assigned from the file
where possible and left for manual assignment otherwise — never blocking a
course because of a messy or missing lecturer name.

This is a sibling of the existing lecturer bulk import
(`POST /users/bulk-import/` in `backend/app/routers/users.py`) and reuses its
established contract: a `dry_run` preview, a `created`/`skipped` breakdown, and
per-row independence (a bad row is skipped with a reason, never aborting the
batch).

## Roles and modes

The caller's role selects the mode. There is no mode parameter.

| Role | Mode | Target | Semester |
|---|---|---|---|
| `faculty_head` | departmental | courses in departments of the head's own faculty | must be 1 or 2 (0 rejected) |
| `university_admin` | university-wide | year-long university requirements (no department, no level) | forced to 0 |

- **`super_admin` is excluded** — a super admin has nothing to do with courses.
- **Timetable officers and below** cannot bulk-import courses.
- Permission is a custom role check for exactly `{faculty_head, university_admin}`,
  **not** `require_faculty_head` (which would include super_admin).

Scoping uses existing user fields (no schema change): a `faculty_head` carries
`faculty_id` and `university_id`; a `university_admin` carries `university_id`.

## API

```
POST /courses/bulk-import/?dry_run=<bool>
  Content-Type: multipart/form-data, field `file`
  Returns: { "created": [...], "skipped": [...], "dry_run": <bool> }
```

- `dry_run=true`  → validate and return the preview; roll back, persist nothing.
- `dry_run=false` → create the non-skipped rows and commit.

Same `dry_run` semantics as the lecturer importer.

## File formats (CSV + Excel)

A single internal helper `_read_rows(file) -> list[dict]` normalizes both
formats into a list of string-keyed, string-valued row dicts:

- `.csv` → decoded `utf-8-sig`, parsed with `csv.DictReader` (as the lecturer
  importer does today).
- `.xlsx` → parsed with **`openpyxl`** (new dependency, added to
  `backend/requirements.txt`). First sheet; first non-empty row is the header;
  cells are stringified and stripped.
- Any other/corrupt upload → a friendly `400`: "That file could not be read.
  Please upload a CSV or Excel (.xlsx) file."
- Header keys are lower-cased and trimmed, so `Code`, `CODE`, `code` all match.

## Columns

**Faculty-head mode**

| column | required | notes |
|---|---|---|
| `code` | yes | e.g. CEF440 |
| `name` | yes | e.g. Internet Programming |
| `level` | yes | number: 200 = year 1, 300 = year 2, 400 = year 3, … matched to the department's Levels |
| `department` | yes | matched by name within the head's faculty |
| `semester` | no | 1 or 2; defaults to 1; **0 is rejected** |
| `weekly_hours` | no | int; defaults to 2 |
| `room_type` | no | lecture_hall / lab / studio; defaults to lecture_hall |
| `lecturer` | no | auto-matched by name; blank/unmatched → unassigned |

**University-admin mode**

| column | required | notes |
|---|---|---|
| `code` | yes | |
| `name` | yes | |
| `weekly_hours` | no | int; defaults to 2 |
| `room_type` | no | lecture_hall / lab / studio; defaults to lecture_hall |
| `lecturer` | no | auto-matched by name across the university; blank/unmatched → unassigned |

University-wide courses have no `level`/`department` columns: `department_id`
and `level_id` are null, `university_id` is set, `semester` is 0 — exactly what
`create_course` does for university-wide courses today.

## Row validation

Each row is independent. A failing row is appended to `skipped` with a reason
and the batch continues.

Faculty-head mode, per row:
1. `code` and `name` present, else skip ("missing required field").
2. `department` matched (case-insensitive) among departments of the head's
   faculty, else skip ("department '<x>' not found in your faculty").
3. `level` parsed to an int and matched to a Level of that department, else
   skip ("level '<x>' not found").
4. `semester`: blank → 1; must be 1 or 2. A `0` is skipped ("year-long courses
   are added by the university admin, not here").
5. `weekly_hours`: blank/invalid → 2. `room_type`: invalid → lecture_hall.
6. Duplicate check (see below).

University-admin mode, per row:
1. `code` and `name` present, else skip.
2. `semester` forced to 0; `department_id`/`level_id` null; `university_id`
   set from the admin's `university_id`.
3. `weekly_hours` / `room_type` defaults as above.
4. Duplicate check (see below).

## Duplicate handling — skip only (v1)

A row is a duplicate if a course with the same `code` already exists in the
same scope:

- departmental mode: same `code` in the same `department_id` **and** `level_id`;
- university-wide mode: same `code` with the same `university_id` and no
  department.

Duplicates are **skipped** with reason "already exists". Existing courses are
never overwritten. A `code` that appears twice within the same file is also
skipped on its second occurrence ("duplicate row in file"). Update-existing is
explicitly out of scope for v1.

## Lecturer auto-match (never fatal)

The `lecturer` cell is always optional and never blocks a course.

1. Normalize the cell: strip leading titles (`Dr.`, `Dr`, `Prof.`, `Prof`,
   `Mr`, `Mrs`, `Ms`), collapse internal whitespace, lower-case.
2. Build the candidate set of lecturers' normalized `User.full_name`:
   - departmental mode: lecturers in the target department;
   - university-wide mode: lecturers across the admin's university.
3. Resolve:
   - exactly one match → assign that lecturer (`course.lecturer_id`);
   - no match → create the course unassigned, `lecturer_note = "not found — assign manually"`;
   - more than one match → create unassigned, `lecturer_note = "ambiguous — assign manually"`.

After import, the head assigns any unassigned lecturers through the existing
course-edit path (`PUT /courses/{id}` with `lecturer_id`). No new assignment
endpoint is needed.

## Response shape

```json
{
  "created": [
    {
      "code": "CEF440",
      "name": "Internet Programming",
      "level": 400,
      "department": "Computer Engineering",
      "semester": 1,
      "lecturer": "Dr. Ateba",
      "lecturer_note": null
    }
  ],
  "skipped": [
    { "code": "CEF999", "reason": "department 'Xyz' not found in your faculty" }
  ],
  "dry_run": true
}
```

In university-admin mode, `level` and `department` are omitted (or null) and
`semester` is 0. On a real (non-dry-run) commit the shape is identical; the only
difference is that the rows have been persisted.

## Frontend

A new `CourseBulkImportScreen`, closely modeled on the existing
`frontend/lib/features/bulk_import/bulk_import_screen.dart`: the same
pick → preview → confirm/cancel → result flow and the same card styling.

Differences:
- File picker accepts `['csv', 'xlsx']`.
- The format-help card is role-aware: it reads the logged-in role from
  `AuthController` and shows the faculty-head template (with `level`/`department`)
  or the university-admin template (year-long requirements), plus a matching
  example.
- Preview rows show course `code` / `name` / `level` / `semester` and a small
  lecturer badge: **matched** (name), **unassigned** (amber, from
  `lecturer_note`), or **ambiguous**.
- The result view lists created courses and the skipped rows with reasons
  (no passwords involved, unlike the lecturer importer).
- Entry point (route + navigation item) renders only when the logged-in role is
  `faculty_head` or `university_admin`, so the button a user can't use is never
  shown — no 403 surprises.

## Testing

Backend tests in the existing style (`make_university()` fixtures in
`backend/tests/conftest.py`):

- faculty-head happy path creates departmental courses — one test for CSV, one
  for `.xlsx`;
- semester-0 row is skipped in faculty-head mode; semester 1/2 row is skipped in
  university-admin mode;
- department not found / level not found → skipped, batch continues;
- lecturer exact match assigns; no-match and ambiguous land unassigned with the
  correct `lecturer_note`;
- duplicate `code` skipped (existing course untouched); in-file duplicate skipped;
- `dry_run=true` writes nothing (row count unchanged);
- a `timetable_officer` and a `super_admin` both receive `403`.

## Out of scope (v1)

- PDF upload (unreliable table extraction; a mis-parse produces silently wrong
  courses).
- Update-existing / upsert of duplicate courses.
- Changing the permissions of the existing single-course CRUD endpoints — this
  spec only governs the new bulk-import endpoint and its UI entry point.
- A dedicated lecturer-assignment endpoint (the existing `PUT /courses/{id}`
  already covers it).

## New dependency

- `openpyxl` — added to `backend/requirements.txt` for `.xlsx` parsing.
