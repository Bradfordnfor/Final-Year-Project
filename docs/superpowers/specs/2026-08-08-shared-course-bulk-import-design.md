# Shared Courses in Course Bulk Import — Design

Date: 2026-08-08
Status: Approved (pending spec review)

## Problem

A single course is often taught to several departments at once — e.g. `CEF201`
sat by both Computer Engineering and Electrical Engineering. The manual
course flow already supports this: you create the course once and share it with
the other departments' classes (`SharedCourse`), so the solver schedules it as
one combined session (`db_preprocessor.py` unions the course's own classes with
its shared classes and sums their populations). But the **course bulk import**
(`POST /courses/bulk-import/`) has no way to express this: each row creates a
course in exactly one department, so a shared course must either be entered by
hand afterwards or duplicated per department (which schedules it multiple times —
wrong).

We want the faculty head to list several departments for one course in the
spreadsheet and have the importer create the course once and wire up the shares
automatically — the bulk equivalent of the manual "share with these classes"
action.

## Decisions locked in brainstorming

- **Faculty-head mode only.** Sharing applies to departmental courses. The
  university-admin (university-wide, semester 0, no department) mode is
  unchanged — those courses already belong to no department.
- **Same faculty only.** Every department listed in a row must be in the
  faculty head's own faculty. A listed department outside the faculty is not an
  error that aborts the row — it is reported as un-shareable (see non-fatal
  rules). Cross-faculty shared courses are out of scope.
- **Same level across departments.** A shared course runs at one level number
  across every sharing department (`level` stays a single column applied to
  each). Per-department levels are out of scope.
- **First department owns the course.** The first name in the `department` cell
  becomes the course's `department_id`/`level_id`; the rest become shares.
- **Shares link all classes at the matching level.** For each additional
  department, the course is linked (via `SharedCourse`) to every `Class` at that
  department's Level with the given number.
- **Existing owner course → skip the whole row** (`"already exists"`), exactly
  as today. Adding shares to a course that already exists is done through the
  manual course dialog, not by re-import. (Update/upsert stays out of scope, per
  the original course-import design.)
- **Delimiter is `|`** (pipe) between department names.

## CSV / Excel format (faculty-head mode)

The only change is that the `department` column may contain more than one
department name, separated by `|`. All other columns are unchanged, and a row
with a single department behaves exactly as it does today (no `|` → current
path).

```
code,name,level,department,semester,weekly_hours,room_type,lecturer
CEF201,Circuits & Systems,200,Computer Engineering | Electrical Engineering,1,3,lecture_hall,Dr. Ateba
CEF210,Data Structures,200,Computer Engineering,1,2,lecture_hall,
```

- Department names are matched case-insensitively within the head's faculty
  (as today). Surrounding whitespace around each `|`-separated name is trimmed.
- `level` is a single number applied to the owner and every shared department.

## Semantics — what a multi-department row produces

For a row listing `D1 | D2 | D3` at level `N`:

1. **Owner (`D1`).** Resolve `D1` in the head's faculty and its Level `N`; create
   the `Course` with `department_id = D1`, `level_id = D1.levelN`, plus the usual
   `code`, `name`, `semester`, `weekly_hours`, `room_type`, and lecturer
   auto-match (auto-match candidate pool = lecturers in `D1`, unchanged, never
   fatal). This is byte-for-byte the current single-department behaviour.
2. **Shares (`D2`, `D3`).** For each, resolve the department in the faculty and
   its Level `N`, collect every `Class` at that level, and create a
   `SharedCourse(course_id, class_id)` for each — skipping any link that already
   exists (same dedup rule as `POST /courses/shared/`).

Because the solver already unions own-level classes with shared classes into one
combined session, the course is scheduled once and all listed departments'
level-`N` classes attend together — the intended "added to all departments and
their classes at once" behaviour, with no duplicate scheduling.

## Validation and non-fatal rules (per-row independence preserved)

Each row is independent; a failing row is skipped with a reason and the batch
continues (unchanged philosophy).

Row is **skipped** (nothing created) when:
- `code` or `name` missing → `"missing required field"`.
- The **owner** department (first name) is not found in the head's faculty →
  `"department '<D1>' not found in your faculty"`.
- The owner department has no Level `N` → `"level '<N>' not found"`.
- `semester` is `0` → `"year-long courses are added by the university admin, not here"` (unchanged).
- Duplicate owner course (same `code` in owner `department_id`+`level_id`) →
  `"already exists"`; in-file duplicate `code` → `"duplicate row in file"`.

Sharing is **best-effort and never fatal.** After the owner course is created,
for each shared department that cannot be fully wired the course is still created
and a per-row `shared_note` records what was skipped, e.g.:
- shared department not found / outside the faculty →
  `"Electrical Engineering: department not found in your faculty — not shared"`;
- shared department has no Level `N` → `"Electrical Engineering: no level 200 — not shared"`;
- Level `N` has no classes → `"Electrical Engineering: level 200 has no classes — not shared"`.

`shared_note` is `null` when every listed shared department was wired
successfully (or when the row lists only one department).

## Duplicate handling

- Owner course duplicate (same `code`, `department_id`, `level_id`) → skip the
  whole row `"already exists"` (no shares added — consistent with v1
  "skip only, never update").
- `SharedCourse` links are always deduped: a link that already exists is left
  as-is, never duplicated.
- Second occurrence of a `code` within the same file → `"duplicate row in file"`.

## Response shape

Each `created` entry gains `shared_with` (list of successfully-wired shared
department names) and `shared_note` (string or null). `department` remains the
owner department, so existing consumers keep working.

```json
{
  "created": [
    {
      "code": "CEF201", "name": "Circuits & Systems", "level": 200,
      "department": "Computer Engineering",
      "shared_with": ["Electrical Engineering"],
      "semester": 1, "lecturer": "Dr. Ateba",
      "lecturer_note": null, "shared_note": null
    }
  ],
  "skipped": [
    { "code": "CEF210", "reason": "already exists" }
  ],
  "dry_run": true
}
```

`dry_run=true` validates and previews (including how many/which shares would be
wired) and rolls back — nothing, including `SharedCourse` rows, is persisted.

## Frontend (CourseBulkImportScreen)

- The faculty-head format-help card and sample CSV show the `Dept A | Dept B`
  syntax with a one-line explanation ("list several departments to share one
  course across them").
- Preview and result rows show the owner department plus a small "shared: Dept B,
  Dept C" badge, and the `shared_note` in amber when a share could not be wired.
- University-admin mode's help/UI is unchanged.

## Testing

Backend tests in the existing course-import style (`make_university()` fixtures):

- faculty-head multi-department row creates **one** course in the owner
  department and `SharedCourse` links to every class at the other departments'
  matching level — one CSV test, one `.xlsx` test;
- shared department not found / has no level / has no classes → the owner course
  is still created and `shared_note` names the un-wired department; batch
  continues;
- a listed shared department outside the head's faculty → un-wired, recorded in
  `shared_note`, owner course still created;
- single-department rows are byte-for-byte unchanged (backward compatibility);
- duplicate owner course skipped (`"already exists"`), no shares added;
- `SharedCourse` dedup: re-wiring an existing link does not create a duplicate;
- `dry_run=true` persists nothing, including no `SharedCourse` rows.

## Out of scope (v1)

- Cross-faculty shared courses.
- Per-department levels for one shared course.
- Updating/adding shares to a course that already exists via re-import
  (use the manual course dialog).
- Sharing in university-admin (university-wide) mode.
