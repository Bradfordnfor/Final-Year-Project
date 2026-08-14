# Client Data Intake Forms — Engineering & Technology Pilot — Design

Date: 2026-08-14
Status: Approved (pending spec review)

## Problem

To prove the timetabling system on a real client, we need to collect everything
the solver requires for one faculty, one semester, from people who are not
technical. The data splits into two shapes: a small amount of single-value
configuration (faculty, working days, time grid) and several long repeating
lists (departments, classes, rooms, courses, lecturers). A single Google Form
handles the first shape well and the second shape badly, so the intake is
organised as a small set of purpose-built channels rather than one form.

The first pilot is the **Faculty of Engineering and Technology only**, one
semester.

## Decisions locked in brainstorming

- **Scope: Engineering & Technology faculty, one semester.** Other faculties,
  class sub-groups (A/B/C lab splits), and multi-semester intake are out of scope.
- **Two Google Forms plus two Excel attachments**, not one mega-form.
- **Rooms and Courses are Excel uploads** on Form A (they are long lists).
- **Departments, levels and class populations stay as guided form questions**
  in Form A (not an upload) — the client explicitly wanted this guided.
- **Lecturers are NOT bulk imported.** Each lecturer submits Form B individually;
  their account is created one at a time (activation email).
- **Lecturer availability is collected in Form B**, not left to in-app self-service,
  so we can generate a realistic timetable immediately.

## Channels overview

| Channel | Who fills it | How often | Produces |
|---|---|---|---|
| Form A — Faculty Setup | Faculty officer / head | Once | University/Faculty/Semester config, time grid, departments, levels, classes; Rooms + Courses via Excel |
| Form B — Lecturer Registration | Each lecturer | Once per lecturer | One `User(role=lecturer)` + their `LecturerAvailability` |
| Rooms Excel (attached to Form A) | Faculty officer | Once | `Building` + `Room` rows |
| Courses Excel (attached to Form A) | Faculty officer | Once | `Course` (+ `SharedCourse`) rows |

## Form A — Faculty Setup

Single submission by the faculty officer. File-upload questions require the
respondent to be signed into a Google account (acceptable for one officer).

### Section 1 · Contact & faculty basics → University / Faculty / Semester
- Officer full name; officer email (short answer)
- Academic year (e.g. 2025/2026)
- Which semester this intake is for: **Term 1 / Term 2** (multiple choice)
- Sessions per week per course (number, default 2) → `Faculty.sessions_per_week`
- Session length in hours (number, default 2) → `Faculty.session_duration_hours`

### Section 2 · Time grid → `TimeSlot` rows
The slots the solver fills. Without this there is nothing to schedule into.
- First teaching day / last teaching day (dropdowns Mon–Sat)
- Day start time, day end time (e.g. 07:30, 18:00)
- Session length (confirms Section 1; used to slice the day into slots)
- Lunch/break window that must stay free (start–end)

The build turns "days × sliced day minus break" into individual `TimeSlot`
rows (`day_of_week`, `start_time`, `end_time`) under the active `Semester`.

### Section 3 · Departments, levels & classes → `Department` → `Level` → `Class`
Guided questions (no Excel). Google Forms cannot make one dropdown depend on a
previous answer, so we use a **fixed ordered block per known Eng & Tech
department** instead of dynamic nesting:

- Computer Engineering, Electrical & Electronic Engineering, Civil Engineering,
  Mechanical Engineering, and an "Other department" free-text catch-all.
- Each block:
  - "Is this department in the faculty?" (Yes / No)
  - If yes: **levels offered** — checkboxes 100 / 200 / 300 / 400 / 500
  - For each offered level: **class size (population)** — a number question
- One class per level per department is assumed for the pilot (name derived as
  `<dept code><level>`, e.g. `CEF400`); sub-groups are out of scope.

### Section 4 · Rooms → `Building` + `Room` (Excel upload)
Template columns (one row per room):

```
building, room_name, capacity, room_type, active
```

- `room_type` ∈ `lecture_hall | lab | outdoor`
- `capacity` is an integer; `active` is yes/no (default yes)
- Capacity vs class population is the core scheduling constraint, so it is required.

### Section 5 · Courses → `Course` (+ `SharedCourse`) (Excel upload)
Template columns match the existing faculty-head bulk-import format exactly:

```
code, name, level, department, semester, weekly_hours, room_type, lecturer
```

- `department` may list several departments separated by `|` to share one course
  across them (owner first) — the existing shared-course import behaviour.
- `semester` is 1 or 2; `weekly_hours` default 2; `room_type` ∈
  `lecture_hall | lab | studio`; `lecturer` optional (auto-matched on import).

## Form B — Lecturer Registration

One submission **per lecturer**, filled by the lecturer themselves.

- Full name (short answer) → `User.full_name`
- Email (short answer) → `User.email` (the activation invite goes here)
- Department (dropdown, the Eng & Tech departments) → `Lecturer.department_id`
- Courses they teach (short answer / list of codes — reference for matching)
- **Availability grid** → `LecturerAvailability`
  - "Mark the half-days you are **NOT** available."
  - Checkbox grid: rows = teaching days (from Section 2's range), columns =
    Morning / Afternoon.
  - Unmarked cells are treated as available; marked cells are excluded when the
    officer records the lecturer's availability.

## Ingestion — how responses become app data

The forms collect data; existing app screens/imports load it. No new backend
endpoints are required for the pilot.

- **Form A Sections 1–3** → typed into the existing faculty-setup screen
  (departments, levels, classes) and the semester/time-grid setup. Time-grid
  answers become `TimeSlot` rows on the active `Semester`.
- **Section 5 courses Excel** → `POST /courses/bulk-import/` (faculty-head mode),
  unchanged.
- **Section 4 rooms Excel** → entered via the buildings/rooms screen. **There is
  no rooms bulk-import endpoint today** (`POST /rooms/` creates one room at a
  time), so the officer/we key the rooms in from the Excel. A rooms bulk import
  is a possible future enhancement but is out of scope here.
- **Form B** → for each response, create the lecturer via the create-user flow
  (activation email), then record their availability from the grid.

## Deliverables

1. **Form A build spec** — every section, question type, options, and required
   flags, ready to build in Google Forms (or generate via Apps Script).
2. **Form B build spec** — same, including the availability checkbox grid.
3. **`rooms_template.xlsx`** — headers `building, room_name, capacity, room_type,
   active` with one example row and a notes row.
4. **`courses_template.xlsx`** — headers matching the faculty-head course import,
   with an example single-department row and an example `|`-shared row.
5. **Intake runbook** — step order for turning the three channels into a loaded
   database using the existing screens/imports, so the pilot is reproducible.

## Google Forms caveats we design around

- **File upload requires a signed-in Google account** — fine for a single officer.
- **No cross-question dynamic dropdowns** — handled with linear per-department
  sections in Section 3.
- **Numbers-per-item** (class populations) — kept small and bounded by asking per
  offered level inside each department block, rather than a free-form list.

## Acceptance — how we confirm it works for the client

1. A completed Form A + rooms/courses Excel + a handful of Form B submissions
   load cleanly through the existing screens/imports (no manual DB edits).
2. A timetable run for the Engineering & Technology faculty, that semester,
   generates with: no class double-booked, no lecturer scheduled in a marked-off
   slot, every session in a room of the required type whose capacity covers the
   class population (within the university overflow threshold).
3. The officer can read the generated timetable back per department and per level.

## Out of scope (pilot v1)

- Faculties other than Engineering & Technology.
- Class sub-groups (A/B/C) and lab splitting.
- Multi-semester / full-year intake in one pass.
- Auto-parsing the uploaded Excel straight from Google Form responses (the
  imports are run by the officer/us, not triggered automatically).
- A rooms bulk-import endpoint (rooms are keyed in manually for now).
