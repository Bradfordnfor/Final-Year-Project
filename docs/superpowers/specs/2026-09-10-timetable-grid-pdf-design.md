# Timetable Grid PDF Download — Design

Date: 2026-09-10
Status: Approved (pending spec review)

## Problem

The timetable PDF/CSV download is a **flat list**: `_get_entries_with_details`
(in `backend/app/routers/export.py`) emits one row per session and both the CSV
and the PDF render those rows as a plain table (Day, Time, Course, Classes,
Lecturer, Room, …). To read "what is on Wednesday", a reader scans the whole
list. The on-screen grid is nicer to read, but it is not downloadable, and it
only renders **one session per slot** (`entryBySlot[e.timeSlotId] = e`
overwrites), so it relies on the user filtering to a single class first.

We want the **download** to be the familiar wall-timetable grid — days across
the top, time slots down the side — and for a whole-faculty download each cell
must show **every** concurrent session in that slot (course code, lecturer,
hall). The grid must adapt to the same filter the list download already honors:
whole faculty shows all concurrent sessions per cell; filtering to a
class/level/department thins each cell down to just those sessions.

## Decisions locked in brainstorming

- **Faculty-wide grid, stacked cells.** A single days×slots grid. Each cell
  lists every session in that (day, slot) stacked vertically; cells grow as tall
  as needed.
- **Cell line = Course · Lecturer · Hall.** Each session shows the course
  **code** (bold), then `Lecturer · Hall` beneath. No explicit class label in
  the cell (the course code implies the cohort). Sessions in a cell are sorted
  by course code.
- **PDF becomes the grid; CSV is unchanged.** The `/runs/{run_id}/pdf` endpoint
  now renders the grid. The flat-list PDF is retired (its content still lives in
  the CSV export). `/runs/{run_id}/csv` and `_get_entries_with_details` are
  untouched.
- **Course-code legend at the bottom.** Because cells show only codes, the grid
  ends with a "Course codes" key mapping every code that appears in the
  (filtered) grid to its full course name (e.g. `CEF401 — Internet
  Programming`), sorted by code.
- **Reuse the existing filter.** The grid honors the same `class_ids` query
  param the frontend already sends; the download URL and the frontend button do
  not change (beyond the label already reading "PDF" / "PDF (filtered)").
- **Backend, ReportLab.** Built in `export.py` with ReportLab (already a
  dependency), not generated in Flutter.
- **Track selection in the filter.** When a selected level has tracks, the
  filter offers a Track dropdown so a download can be scoped to one track;
  default stays the whole level.
- **System-logo watermark.** A faded, centered watermark of the fixed system
  logo appears on every page — product identity, uniform across all
  universities, no per-tenant configuration.
- **Minimal running footer.** University name · faculties in the run on the
  left, page number on the right; no running header.

## Layout

- **Landscape A4.** A leading **Time** column, then one column per weekday that
  appears in the run's semester, ordered Monday→Sunday (see day ordering).
- **Rows:** the distinct time slots of the run's semester, ordered by
  `start_time`. Row label is `start–end` (e.g. `07:00–09:00`).
- **Cell:** every session whose `time_slot` falls on that (day, slot). Each
  session renders as the course **code** (bold) with `Lecturer · Hall` beneath.
  An outdoor session (no room) shows `Outdoor / off-site` for the hall (matches
  current export wording). An empty slot renders blank.
- **Header:** run name and status, plus a "Filtered: …" note when `class_ids`
  is supplied (else "All sessions").
- **Footer legend:** a "Course codes" block after the grid — each distinct code
  in the grid → its full name, sorted by code.

## Day ordering

There is no weekday-ordering helper in the backend today, and the existing flat
list sorts days as strings (so Friday sorts before Monday — a latent bug). Add a
canonical order constant:

```python
WEEKDAY_ORDER = ["Monday", "Tuesday", "Wednesday", "Thursday",
                 "Friday", "Saturday", "Sunday"]
```

Columns are the weekdays actually present among the run's time slots, ordered by
this constant. Unknown day strings sort last, stably.

## Component structure

Keep the grid logic in `export.py`, factored so it is testable without parsing
PDF bytes:

- **`build_grid(rows) -> GridModel`** — a pure function that turns the detail
  rows (from `_get_entries_with_details`, reused as-is) into an in-memory grid:
  ordered `days`, ordered `slots` (each `"HH:MM–HH:MM"`), a `cells` map keyed by
  `(day, slot_label)` to a list of `{code, lecturer, hall}` dicts sorted by
  code, and a `legend` list of `(code, name)` sorted by code. This is what tests
  assert against. The "Filtered: …" header note is not part of the grid model;
  it is derived in the renderer from whether `class_ids` was supplied.
  - Note: `_get_entries_with_details` currently returns `Course` as
    `"{code} — {name}"`. `build_grid` needs code and name separately. Either
    split on `" — "` inside `build_grid`, or (preferred) extend the detail row
    with explicit `"Code"` and `"CourseName"` fields and keep the combined
    `"Course"` for the unchanged CSV. Chosen: add `"Code"` and `"CourseName"`
    to the row dict (CSV keeps using `"Course"`, so its output is unchanged).
- **`_grid_pdf_response(grid, run) -> StreamingResponse`** — renders `GridModel`
  to a landscape ReportLab table plus the legend, and returns the PDF stream.
- **`export_pdf`** endpoint: unchanged signature; now calls
  `build_grid` + `_grid_pdf_response` instead of `_pdf_response`.

## Filter adaptation

`export_pdf` already resolves `class_ids` via `_resolve_class_filter` and passes
them to `_get_entries_with_details`. That filtering is unchanged; the grid is
built from whatever rows survive the filter. Whole faculty → many sessions per
cell; a class/level/department filter → cells contain only those sessions and
the legend shrinks accordingly.

## Track selection in the filter

The download adapts to the class filter the frontend builds in
`ClassFilterBar` (`frontend/lib/core/widgets/class_filter_bar.dart`). Today the
filter goes Faculty → Department → Level, and a level resolves to *all* its
class ids. For a specialization level the user should also be able to narrow to
one **track**.

- **Backend:** extend `GET /faculty-setup/public-levels` to include, per level,
  a `classes` list of `{id, name, track}` (alongside the existing `class_id`
  and `class_ids`, which stay for backward compatibility).
- **Frontend:** in `ClassFilterBar`, after a Level is selected, if that level
  has tracks (more than one class, or any class with a non-null `track`), show a
  **Track** dropdown. Its default option is "All tracks (whole level)"; the
  other options are the level's tracks. Default → scope is every class id of the
  level (unchanged); a specific track → scope is that single class id.
- This flows through the existing `class_ids` download param with no change to
  the download URL shape, so both the grid PDF and the CSV adapt to the chosen
  track.

## Watermark and footer

Both are drawn by a single ReportLab **page callback** (`onPage`) so they repeat
identically on every page, behind/around the grid content.

- **Watermark — the system logo.** The app logo at
  `frontend/assets/images/logo.png` is copied into the backend as a static
  asset (`backend/app/assets/watermark_logo.png`) and embedded **faded**
  (reduced opacity via a low-alpha fill / `setFillAlpha`) and **centered** on
  each page. It is uniform across all timetables — it identifies the product,
  not the university — so it needs no per-tenant configuration. If the asset is
  missing the PDF still renders (the watermark is skipped, not an error).
- **Footer — one minimal line.** Left: `University name · Faculty(ies)`, where
  the university and faculties are derived from the run (run → faculties via
  `TimetableRunFaculty`, university via `faculty.university`); multiple
  faculties are joined by `·`. Right: `Page X of Y`. Departments are omitted
  (kept minimal, per "not too much info"). There is no separate running header —
  the grid's own title block already names the run.

## Testing

Unit tests target the pure `build_grid` (no PDF parsing):

- **Concurrent sessions share a cell:** two sessions on the same day+slot
  produce one cell containing both codes, each with its lecturer and hall.
- **Day ordering:** a run whose slots include Friday and Monday yields
  `days == [..., "Monday", ..., "Friday", ...]` in canonical order, never
  alphabetical.
- **Slot ordering:** slots are ordered by start time.
- **Legend:** the legend lists each distinct code once with its full name,
  sorted by code, and only for codes present in the (filtered) grid.
- **Outdoor session:** a session with no room shows `Outdoor / off-site` as the
  hall.

Endpoint tests (thin):

- `GET /runs/{id}/pdf` returns `200` and `application/pdf` for a run with
  multiple concurrent sessions (exercises the grid render, watermark callback,
  and footer without asserting pixel content).
- `GET /runs/{id}/pdf?class_ids=<one class>` returns `200`; combined with a
  `build_grid` assertion on the same filtered rows, only that class's sessions
  and codes appear.
- `GET /runs/{id}/pdf` still returns `200` when the watermark asset is absent
  (watermark skipped, not fatal).
- CSV export is unchanged: `GET /runs/{id}/csv` still returns the flat list with
  the existing columns (regression guard on the `"Course"` column).

Track filter:

- `GET /faculty-setup/public-levels?department_id=<d>` returns each level's
  `classes` list with `{id, name, track}`; a two-track level lists both tracks.
  (The frontend dropdown behaviour is verified by `flutter analyze` +
  interactive click-through, not an automated widget test.)

## Out of scope

- Any change to the CSV export or the on-screen grid layout (the filter bar
  gains a track dropdown, but the grid widget itself is unchanged).
- Per-class "booklet" (one grid per class) output.
- Showing the class/track label inside a cell (course code implies the cohort).
- Configurable page size/orientation.
- Per-university logos or a logo-upload feature — the watermark is the fixed
  system logo, the same on every timetable.
