# Bulk Import Redesign — Design

**Date:** 2026-06-20
**Status:** Approved (design)

## Goal

Replace the numeric-ID bulk import of lecturers with a human-readable, CSV that
a university admin can fill in by hand. The import is scoped automatically to
the importing admin's own university, so no university identifier appears in the
file.

## Motivation

The current `POST /users/bulk-import/` requires `department_id`, `faculty_id`,
and `university_id` as integers. Admins do not know these IDs, and the handler
crashes (HTTP 500) on a blank/non-numeric ID or an ID that violates a foreign
key on PostgreSQL. Manually adding one lecturer is currently easier than using
the import, which defeats its purpose.

## Who can run it

The importer's account must have a `university_id` (a university admin). The
import always targets that admin's university. A super admin (no university)
receives HTTP 400 telling them to use a university-admin account.

## CSV format

Header row required. Columns:

| Column | Required | Notes |
|---|---|---|
| `name` | yes | Lecturer's full name |
| `email` | yes | Login email; must be unique |
| `faculty` | yes | Faculty **name**, resolved within the admin's university |
| `department` | yes | Department **name**, resolved within that faculty |
| `password` | no | If blank, a temp password is generated and returned once |

Name matching for `faculty` and `department` is case-insensitive and trimmed.

Example:

```csv
name,email,faculty,department,password
John Doe,jdoe@ub.cm,Faculty of Engineering and Technology,Computer Engineering,
Jane Smith,jsmith@ub.cm,Faculty of Engineering and Technology,Electrical Engineering,Start123
```

Faculty is required (not derived) because department names can repeat across
faculties; faculty disambiguates and also sets the lecturer's `faculty_id`.

## Per-row processing

Each row is independent — a bad row is skipped, never aborts the batch.

1. `name`, `email`, `faculty`, `department` non-empty → else skip, reason
   "missing required field".
2. Faculty name found in the admin's university → else skip, reason
   "faculty '<X>' not found".
3. Department name found within that faculty → else skip, reason
   "department '<Y>' not found in faculty '<X>'".
4. Email not already registered → else skip, reason "already exists".
5. Create `User` (role=lecturer, `university_id`=importer's, `faculty_id`,
   `department_id`) and a linked `Lecturer` profile (same `department_id`).
   Password: use the CSV value if present, otherwise generate
   `secrets.token_urlsafe(10)` and include it in the result.

## Response

Shape is unchanged so the existing results UI keeps working:

```json
{
  "created": [{"name": "...", "email": "...", "temp_password": "..."}],
  "skipped": [{"email": "...", "reason": "..."}]
}
```

`temp_password` is present on a created row only when the system generated it
(blank password column).

## Error handling

No row-level condition raises. Malformed input becomes a skip reason. The only
hard error is the importer lacking a `university_id` (HTTP 400 before any rows
are read).

## Files

- `backend/app/routers/users.py` — rewrite `bulk_import_lecturers`.
- `frontend/lib/features/bulk_import/bulk_import_screen.dart` — update the CSV
  format help rows and the example block (new columns, names not IDs).
- `backend/tests/test_bulk_import.py` (new) — cover: successful create with and
  without password, case-insensitive name resolution, duplicate email skipped,
  unknown faculty/department skipped, super-admin (no university) rejected,
  scoping (cannot import into another university's faculty by name).

## Testing strategy

Backend tests via the FastAPI test client against the SQLite test DB, building a
university/faculty/department with the existing fixtures. Assert the JSON
`created`/`skipped` breakdown and that the created `User`+`Lecturer` rows carry
the right university/faculty/department. Frontend verified with
`flutter analyze`.

## Out of scope

- Importing roles other than lecturer.
- Updating existing lecturers (duplicates are skipped, not updated).
- Sending invitation emails (tracked separately in the further-works backlog).
