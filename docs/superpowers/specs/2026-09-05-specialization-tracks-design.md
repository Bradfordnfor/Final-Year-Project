# Specialization Tracks — Design

Date: 2026-09-05
Status: Approved (pending spec review)

## Problem

Some programs split into specializations partway through the degree, and the
split level varies by program — level 300 for some, 400 for others, 500 for
others. When a cohort specializes, one class becomes two (or more) tracks that
each take a partly different set of courses. For example, Computer Engineering
400 (200 students) divides into **Software (120)** and **Networking (80)**, and
a Software-only course and a Networking-only course are meant to run **at the
same time** because they are physically different students.

The system cannot express this today. A whole cohort is modelled as a single
`Class` (e.g. "CE400", population 200), and courses attach to a **level**: the
preprocessor gives every course at a level to *all* classes at that level
(`db_preprocessor.py`, the "Classes at this course's level" query). The solver
then enforces a hard constraint (`solver.py`, "Class attends at most one session
per timeslot") that no class occupies two slots at once. So the Software and
Networking courses — both sessions of the one "CE400" class — are forbidden from
sharing a slot, even though they should overlap.

The scheduling unit is the whole cohort, but specialization means the cohort is
really two independent scheduling units that share only *some* courses.

## Decisions locked in brainstorming

- **A track is a `Class`.** A student belongs to exactly one track for the whole
  specialization level (a stable sub-cohort), so a track is modelled as its own
  `Class` under the level. At a specialization level the operator creates one
  class per track (e.g. "CE400 Software" pop 120, "CE400 Networking" pop 80).
  Ordinary levels keep their single class unchanged.
- **The solver is not changed.** The clash constraint is already per-class, so
  two different track-classes schedule in parallel with no modification. This is
  a data-model and course-targeting change only.
- **Courses gain an optional per-class target.** A course can attach to one
  specific track-class, or (target left empty) to the whole level as today.
- **Common courses reuse the existing merge logic.** A course targeting the
  whole level at a two-track level attaches to both track-classes; the existing
  `compute_merge_decision` seats them in one combined session (all 200), or
  splits per class when no room fits. No new "common course" concept is needed.
- **Mixed curricula are supported per course, not per level.** Whether a level
  has common courses, track-specific courses, or both is expressed course by
  course (the target field), because it varies by program and level.
- **Tracks are stable, not per-course.** Students do not mix and match tracks
  between courses, so no per-course grouping mechanism is introduced.

## Data model

Two nullable additions; both default to today's behavior so existing data is
untouched.

- **`courses.class_id`** — nullable FK to `classes`. The course's target.
  - `NULL` → the course belongs to the **whole level**: every class at
    `courses.level_id` (current behavior; every existing course has this).
  - set → the course belongs to **only that one track-class**.
- **`classes.track`** — nullable string (short label, e.g. `"Software"`,
  `"Networking"`). `NULL` for ordinary single-class levels. Used to match the
  import's track column and to display the track in the UI.

`class_id` and the existing `SharedCourse` mechanism are orthogonal and compose:
`SharedCourse` *adds* classes (e.g. a course shared to another department),
while `class_id` *narrows* the owning level to a single class.

## How tracks are created

No new endpoint. For a specialization level the operator creates several classes
under the same level via the existing `POST /classes/`, each with a `track`
label and its own population. Non-specialization levels keep their single class.

## Preprocessor change

In `db_preprocessor.py`, replace the "all classes at this course's level" step
so it honors the target:

```
own_class_ids = [course.class_id] if course.class_id else [c.id for c in classes at course.level_id]
attending_class_ids = set(own_class_ids + shared_class_ids)
```

Everything downstream (merge decision, lab split, university-wide packing) is
unchanged. A track-specific course yields sessions for one class only; a
whole-level course at a two-track level yields the merged/ split sessions across
both track-classes exactly as a normal multi-class level would.

## Course bulk import

Add an optional **`track`** column to the faculty-head course file
(`_import_faculty_courses`). Semantics per row:

- **blank** → `class_id = NULL` (common course, whole level).
- **a track label** → resolve the `Class` at (owning department, `level`) whose
  `track` matches (case-insensitive, trimmed); set `class_id` to it.
- **track given but no matching class at that level** → the row is **skipped
  with a clear reason**, consistent with the importer's existing non-fatal
  per-row skip behavior (nothing else in the batch is affected).

The university-admin (university-wide, semester 0) import is unchanged — those
courses have no level and no track.

Shared-department rows (the existing multi-department `A | B` syntax) continue to
share to *all* classes at the matching level in each other department. Combining
a track target with cross-department sharing is out of scope for this change; a
row may use one or the other.

## UI

- **Class create/edit form** — add the optional `track` field.
- **Course create/edit form** — an optional track/class target, shown only when
  the selected level has more than one class; otherwise omitted.
- **Course-import help** — document the new `track` column.
- **`CourseOut` / `CourseCreate` / `CourseUpdate` schemas** — add `class_id`;
  **`ClassOut` / `ClassCreate` / `ClassUpdate`** — add `track`.

## Migration & backward compatibility

One Alembic migration adds `courses.class_id` (nullable FK) and `classes.track`
(nullable string). Existing courses have `class_id = NULL`, i.e. "whole level",
so no already-scheduled or already-loaded data changes meaning.

## Testing

- **Preprocessor**
  - A track-specific course (`class_id` set) produces sessions for only that
    class.
  - Two track-specific courses at the same level (one per track) are assigned to
    the same time slot by the solver — no clash, because they are different
    classes.
  - A whole-level course (`class_id = NULL`) at a two-track level produces one
    merged session across both tracks when a room fits, and a clean per-track
    split when no room fits.
- **Import**
  - `track` blank → `class_id = NULL`.
  - valid `track` → the correct track-class.
  - unknown `track` → row skipped with a reason; the rest of the batch imports.
- **Backward compatibility**
  - Existing courses with `class_id = NULL` schedule exactly as before at
    single-class levels.

## Out of scope

- Per-course track grouping (students changing track between courses).
- Combining a single course's track target with cross-department sharing in one
  import row.
- Any change to the CP-SAT solver model.
