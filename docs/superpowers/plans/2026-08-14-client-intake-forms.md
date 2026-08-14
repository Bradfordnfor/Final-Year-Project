# Client Data Intake Forms Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce the intake package for the Engineering & Technology faculty pilot — two Excel templates (rooms, courses), a build spec for each of the two Google Forms, an optional Apps Script generator, and a loading runbook — so the faculty can supply data by form and the operator can load it into the app with the existing screens/imports.

**Architecture:** Everything is a static deliverable under a new `docs/client_intake/` folder. The two `.xlsx` templates are produced by a small, committed Python generator using `openpyxl` (the same library the app's course importer uses), so the templates cannot drift from the import format. The Google Forms are documented as exact build specs the operator follows by hand (primary path); an optional Apps Script builds the parts of the forms the API supports. Nothing here changes backend or frontend code.

**Tech Stack:** Python 3.13 + `openpyxl` 3.1.5 (already installed in `backend/.venv`); Markdown; Google Apps Script (optional, run in the browser by the operator).

## Global Constraints

- **Scope: Engineering & Technology faculty, one semester only.** No other faculties, no class sub-groups (A/B/C), no multi-semester intake.
- **Courses template columns, verbatim:** `code, name, level, department, semester, weekly_hours, room_type, lecturer` — must match `POST /courses/bulk-import/` faculty-head format exactly (`department` may list several names separated by `|` to share a course; owner first).
- **Rooms template columns, verbatim:** `building, room_name, capacity, room_type, active`.
- **Course `room_type` ∈ `lecture_hall | lab | studio`; Room `room_type` ∈ `lecture_hall | lab | outdoor`.** These two enums differ — do not "unify" them; document each where it is used.
- **Lecturers are not bulk imported.** Form B is one submission per lecturer; the operator creates each account individually. The availability grid collects the half-days a lecturer is **NOT** available; the app stores availability (the complement).
- **All deliverables live under `docs/client_intake/`.** Do not touch `backend/` or `frontend/` source.
- **Commit style:** plain sentences, no `feat:`/`fix:` prefixes, no `Co-Authored-By` line.
- Use the repo Python via `backend/.venv` (run generator from the `backend` dir so `openpyxl` resolves).

---

## File Map

- Create: `docs/client_intake/generate_templates.py` — openpyxl script that writes both `.xlsx` templates (single source of truth for their headers/examples).
- Create (generated): `docs/client_intake/rooms_template.xlsx`
- Create (generated): `docs/client_intake/courses_template.xlsx`
- Create: `docs/client_intake/test_templates.py` — verifies the generated workbooks have the exact headers and example rows.
- Create: `docs/client_intake/form_a_faculty_setup.md` — question-by-question build spec for Form A.
- Create: `docs/client_intake/form_b_lecturer_registration.md` — question-by-question build spec for Form B.
- Create: `docs/client_intake/loading_runbook.md` — operator steps to load responses into the app.
- Create (optional): `docs/client_intake/generate_forms.gs` — Apps Script that builds the API-supported parts of both forms.

---

## Task 1: Excel templates + generator + test

**Files:**
- Create: `docs/client_intake/generate_templates.py`
- Create: `docs/client_intake/test_templates.py`
- Create (generated): `docs/client_intake/rooms_template.xlsx`, `docs/client_intake/courses_template.xlsx`

**Interfaces:**
- Consumes: `openpyxl` (`from openpyxl import Workbook, load_workbook`).
- Produces: two workbooks. `rooms_template.xlsx` sheet `Rooms` row 1 = `["building","room_name","capacity","room_type","active"]`. `courses_template.xlsx` sheet `Courses` row 1 = `["code","name","level","department","semester","weekly_hours","room_type","lecturer"]`. Each workbook also has an `Instructions` sheet.

- [ ] **Step 1: Write the generator**

Create `docs/client_intake/generate_templates.py`:

```python
"""Generate the rooms and courses Excel templates for the client intake.

Run from the backend dir so the venv's openpyxl resolves:
    cd backend && python ../docs/client_intake/generate_templates.py
The .xlsx files are written next to this script.
"""
import os
from openpyxl import Workbook

HERE = os.path.dirname(os.path.abspath(__file__))

ROOMS_HEADER = ["building", "room_name", "capacity", "room_type", "active"]
ROOMS_EXAMPLES = [
    ["Main Block", "LT1", 250, "lecture_hall", "yes"],
    ["Main Block", "Electronics Lab", 60, "lab", "yes"],
    ["Sports Complex", "Engineering Field", 400, "outdoor", "yes"],
]
ROOMS_NOTES = [
    ["Column", "Meaning / allowed values"],
    ["building", "Building name; repeat it on every room in that building."],
    ["room_name", "Unique room name or number, e.g. LT1, Room 204."],
    ["capacity", "Whole number of seats. Required — used against class size."],
    ["room_type", "One of: lecture_hall, lab, outdoor."],
    ["active", "yes or no. Use no for a room that must not be scheduled."],
]

COURSES_HEADER = ["code", "name", "level", "department", "semester",
                  "weekly_hours", "room_type", "lecturer"]
COURSES_EXAMPLES = [
    ["CEF440", "Internet Programming", 400, "Computer Engineering", 1, 3,
     "lecture_hall", "Dr. Ateba"],
    ["CEF201", "Circuits", 400, "Computer Engineering | Electrical Engineering",
     1, 3, "lecture_hall", ""],
]
COURSES_NOTES = [
    ["Column", "Meaning / allowed values"],
    ["code", "Course code, e.g. CEF440. Required."],
    ["name", "Course title. Required."],
    ["level", "Year of study number: 100, 200, 300, 400, 500."],
    ["department", "Department name in this faculty. To share ONE course across "
                   "departments, list them separated by | (first owns it), e.g. "
                   "Computer Engineering | Electrical Engineering."],
    ["semester", "1 (first) or 2 (second)."],
    ["weekly_hours", "Contact hours per week. Leave blank for the default (2)."],
    ["room_type", "One of: lecture_hall, lab, studio. Match a room type you have."],
    ["lecturer", "Lecturer full name (optional; auto-matched on import)."],
]


def _sheet(wb, title, header, examples):
    ws = wb.active if wb.active.max_row == 1 and wb.active.max_column == 1 else wb.create_sheet()
    ws.title = title
    ws.append(header)
    for row in examples:
        ws.append(row)
    return ws


def _instructions(wb, notes):
    ws = wb.create_sheet("Instructions")
    for row in notes:
        ws.append(row)
    return ws


def build_rooms(path):
    wb = Workbook()
    _sheet(wb, "Rooms", ROOMS_HEADER, ROOMS_EXAMPLES)
    _instructions(wb, ROOMS_NOTES)
    wb.save(path)


def build_courses(path):
    wb = Workbook()
    _sheet(wb, "Courses", COURSES_HEADER, COURSES_EXAMPLES)
    _instructions(wb, COURSES_NOTES)
    wb.save(path)


if __name__ == "__main__":
    build_rooms(os.path.join(HERE, "rooms_template.xlsx"))
    build_courses(os.path.join(HERE, "courses_template.xlsx"))
    print("Wrote rooms_template.xlsx and courses_template.xlsx to", HERE)
```

- [ ] **Step 2: Write the failing test**

Create `docs/client_intake/test_templates.py`:

```python
"""Verify the generated intake templates have the exact expected shape."""
import os
import pytest
from openpyxl import load_workbook

import generate_templates as gt

HERE = os.path.dirname(os.path.abspath(__file__))
ROOMS = os.path.join(HERE, "rooms_template.xlsx")
COURSES = os.path.join(HERE, "courses_template.xlsx")


@pytest.fixture(scope="module", autouse=True)
def _build():
    gt.build_rooms(ROOMS)
    gt.build_courses(COURSES)


def _header(path, sheet):
    wb = load_workbook(path, read_only=True)
    ws = wb[sheet]
    return [c.value for c in next(ws.iter_rows(min_row=1, max_row=1))]


def test_rooms_header_exact():
    assert _header(ROOMS, "Rooms") == [
        "building", "room_name", "capacity", "room_type", "active"]


def test_courses_header_matches_import_format():
    assert _header(COURSES, "Courses") == [
        "code", "name", "level", "department", "semester",
        "weekly_hours", "room_type", "lecturer"]


def test_courses_has_a_shared_department_example():
    wb = load_workbook(COURSES, read_only=True)
    depts = [row[3].value for row in wb["Courses"].iter_rows(min_row=2)]
    assert any(d and "|" in d for d in depts), "need a | shared-course example row"


def test_both_have_instructions_sheet():
    assert "Instructions" in load_workbook(ROOMS, read_only=True).sheetnames
    assert "Instructions" in load_workbook(COURSES, read_only=True).sheetnames
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd backend && python -m pytest ../docs/client_intake/test_templates.py -q`
Expected: the fixture imports `generate_templates` and builds the files, so if the generator is wrong the header assertions FAIL. (If `generate_templates.py` has a syntax error, collection fails — fix and re-run.)

- [ ] **Step 4: Generate the templates for real**

Run: `cd backend && python ../docs/client_intake/generate_templates.py`
Expected: `Wrote rooms_template.xlsx and courses_template.xlsx to ...docs/client_intake`

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd backend && python -m pytest ../docs/client_intake/test_templates.py -q`
Expected: PASS (4 passed).

- [ ] **Step 6: Commit**

```bash
git add docs/client_intake/generate_templates.py docs/client_intake/test_templates.py docs/client_intake/rooms_template.xlsx docs/client_intake/courses_template.xlsx
git commit -m "client intake: rooms and courses Excel templates with a generator and shape test"
```

---

## Task 2: Form A build spec (Faculty Setup)

**Files:**
- Create: `docs/client_intake/form_a_faculty_setup.md`

**Interfaces:**
- Consumes: nothing (standalone doc). References the two `.xlsx` templates from Task 1 by filename.
- Produces: the exact Google Forms build instructions for Form A.

- [ ] **Step 1: Write the Form A spec document**

Create `docs/client_intake/form_a_faculty_setup.md` with this exact content:

```markdown
# Form A — Faculty Setup (Engineering & Technology)

Who fills it: the faculty officer / head, once.
Form settings: "Collect email addresses" ON; because it has file-upload
questions, respondents must sign in to a Google account. Title: "Engineering &
Technology — Faculty Setup". Every question below marked (required) must be
set required in Google Forms.

## Section 1 — Contact & faculty basics
1. Your full name — Short answer (required)
2. Your email — Short answer (required)
3. Academic year, e.g. 2025/2026 — Short answer (required)
4. Which semester is this data for? — Multiple choice (required): Term 1 · Term 2
5. Sessions per week for a typical course — Short answer / number (required, default 2)
6. Session length in hours — Multiple choice (required): 1 · 2 · 3

## Section 2 — Teaching week & time grid
7. First teaching day — Dropdown (required): Monday … Saturday
8. Last teaching day — Dropdown (required): Monday … Saturday
9. Day start time, e.g. 07:30 — Short answer (required)
10. Day end time, e.g. 18:00 — Short answer (required)
11. Lunch/break window to keep free, e.g. 13:00–14:00 — Short answer (required)

## Section 3 — Departments, levels & classes
One fixed block per department (Google Forms cannot nest dropdowns, so the
blocks are listed linearly). Departments covered: Computer Engineering,
Electrical & Electronic Engineering, Civil Engineering, Mechanical Engineering,
plus an "Other" block.

For EACH department block, ask:
- "Is <Department> part of this faculty?" — Multiple choice (required): Yes · No
- "Which levels does <Department> run?" — Checkboxes: 100 · 200 · 300 · 400 · 500
- One number question per level: "<Department> — Level <N> class size (number of
  students)" — Short answer / number. Leave blank if that level is not run.

"Other" block:
- "Any other department not listed above?" — Short answer (department name)
- "Its levels and class sizes (e.g. 200:75, 300:60)" — Short answer

## Section 4 — Rooms (attachment)
12. Upload your completed rooms file — File upload (required).
    Instruction text: "Download rooms_template.xlsx, fill one row per room
    (building, room_name, capacity, room_type = lecture_hall/lab/outdoor,
    active = yes/no), and upload it here."

## Section 5 — Courses (attachment)
13. Upload your completed courses file — File upload (required).
    Instruction text: "Download courses_template.xlsx and fill one row per
    course. To share one course across departments, list them separated by |
    in the department column (the first department owns it)."

## Notes for the operator
- Section 3 answers are typed into the app's faculty-setup screen (departments →
  levels → classes, using the class sizes as populations).
- Section 4/5 files: courses go through the course bulk-import screen; rooms are
  entered by hand on the rooms screen (no rooms bulk import yet).
```

- [ ] **Step 2: Verify the spec references the real template filenames and course columns**

Run: `grep -n "rooms_template.xlsx\|courses_template.xlsx\|lecture_hall/lab/outdoor" docs/client_intake/form_a_faculty_setup.md`
Expected: matches on the two filenames and the rooms enum — confirms the doc points at Task 1's artifacts and uses the room enum (not the course enum) in Section 4.

- [ ] **Step 3: Commit**

```bash
git add docs/client_intake/form_a_faculty_setup.md
git commit -m "client intake: Form A faculty-setup build spec"
```

---

## Task 3: Form B build spec (Lecturer Registration)

**Files:**
- Create: `docs/client_intake/form_b_lecturer_registration.md`

**Interfaces:**
- Consumes: nothing. Produces the exact build instructions for Form B, including the availability checkbox grid.

- [ ] **Step 1: Write the Form B spec document**

Create `docs/client_intake/form_b_lecturer_registration.md` with this exact content:

```markdown
# Form B — Lecturer Registration (Engineering & Technology)

Who fills it: each lecturer, once for themselves.
Form settings: "Collect email addresses" ON, "Limit to 1 response" OFF (many
lecturers). Title: "Engineering & Technology — Lecturer Registration".

## Questions
1. Full name — Short answer (required) → becomes the lecturer's account name
2. Email — Short answer (required) → the activation invite is sent here
3. Department — Dropdown (required): Computer Engineering · Electrical &
   Electronic Engineering · Civil Engineering · Mechanical Engineering · Other
4. Courses you teach (codes or names, comma-separated) — Short answer (optional)
5. Availability — Checkbox grid (required):
   - Prompt: "Tick the half-days you are NOT available to teach."
   - Rows: Monday, Tuesday, Wednesday, Thursday, Friday (add Saturday only if the
     faculty teaches Saturdays, per Form A Section 2).
   - Columns: Morning · Afternoon
   - A ticked cell = unavailable. Anything left un-ticked is treated as available.

## Notes for the operator
- Create one lecturer account per response (they are NOT bulk imported): use the
  create-user screen with role = lecturer and the department from Q3; this emails
  the activation link.
- Record availability as the COMPLEMENT of the ticked cells: the app stores the
  slots a lecturer IS available for, so translate "Mon Morning ticked" into
  "exclude all Monday-morning time slots" when setting their availability.
- If a lecturer ticks nothing, they are available for the whole teaching week.
```

- [ ] **Step 2: Verify the grid and complement rule are documented**

Run: `grep -n "Checkbox grid\|NOT available\|COMPLEMENT\|Morning\|Afternoon" docs/client_intake/form_b_lecturer_registration.md`
Expected: matches — confirms the availability question type and the invert-on-load rule are both present (this is the spec's stated subtlety).

- [ ] **Step 3: Commit**

```bash
git add docs/client_intake/form_b_lecturer_registration.md
git commit -m "client intake: Form B lecturer-registration build spec with availability grid"
```

---

## Task 4: Loading runbook

**Files:**
- Create: `docs/client_intake/loading_runbook.md`

**Interfaces:**
- Consumes: the two forms and two templates. Produces the operator's ordered loading procedure.

- [ ] **Step 1: Write the runbook document**

Create `docs/client_intake/loading_runbook.md` with this exact content:

```markdown
# Intake Loading Runbook — Engineering & Technology Pilot

Order matters: each step's data depends on the ones above it. Do them top to
bottom, once all forms are in.

1. **University & faculty.** Ensure the university exists and create the
   Faculty "Engineering & Technology" with sessions-per-week and session-length
   from Form A Section 1 (Q5, Q6).
2. **Semester & time grid.** Create/activate the semester for the term in Form A
   Q4. Enter the teaching days (Q7–Q8) and slice each day from day-start to
   day-end (Q9–Q10) into sessions of the Q6 length, skipping the break window
   (Q11). These become the time slots the solver fills.
3. **Departments, levels, classes.** From Form A Section 3, create each "Yes"
   department, its ticked levels, and one class per level using the class-size
   number as the population.
4. **Rooms.** Open the rooms file from Form A Q12. For each row create the
   building (if new) and the room (capacity, room_type, active) on the rooms
   screen. (No bulk import yet — key them in.)
5. **Courses.** Upload the courses file from Form A Q13 through the course
   bulk-import screen (faculty-head mode). Use Preview first; confirm the shared
   (`|`) rows show the right shared departments, then Import.
6. **Lecturers.** For each Form B response, create a lecturer account
   (create-user, role = lecturer, department from Q3). Then set that lecturer's
   availability as the complement of the ticked half-days (see Form B notes).
7. **Generate.** Start a timetable run for the Engineering & Technology faculty
   and the active semester. Review conflicts; confirm no class or lecturer is
   double-booked and every session fits a room of the required type and size.

## Acceptance check
- All six loading steps complete with no manual database edits.
- A generated run has zero hard conflicts (class clash, lecturer clash,
  room-type mismatch, over-capacity beyond the university overflow threshold).
- The timetable reads back correctly per department and per level.
```

- [ ] **Step 2: Verify the runbook covers every channel**

Run: `grep -ni "time grid\|departments\|rooms\|courses\|lecturers\|generate" docs/client_intake/loading_runbook.md`
Expected: matches for each channel/stage — confirms no loading step was dropped.

- [ ] **Step 3: Commit**

```bash
git add docs/client_intake/loading_runbook.md
git commit -m "client intake: operator loading runbook"
```

---

## Task 5 (optional): Apps Script form generator

Skip this task if you will build the forms by hand from Tasks 2–3 (the primary
path). Do it only to speed up rebuilding the forms.

**Files:**
- Create: `docs/client_intake/generate_forms.gs`

**Interfaces:**
- Consumes: run by the operator in script.google.com. Produces two Google Forms.
- **Known limitation:** the Apps Script `FormApp` API cannot create **file-upload**
  questions. The script builds everything else; the operator adds Form A's two
  file-upload questions (Q12, Q13) by hand afterwards. This is why building by
  hand is the primary path.

- [ ] **Step 1: Write the Apps Script**

Create `docs/client_intake/generate_forms.gs`:

```javascript
// Build the API-supported parts of Form A and Form B.
// Paste into script.google.com (new project) and run buildForms().
// LIMITATION: FormApp cannot add file-upload questions, so after running this,
// open Form A and add two File-upload questions (rooms file, courses file) by
// hand — see form_a_faculty_setup.md Sections 4 and 5.

var DEPARTMENTS = [
  'Computer Engineering',
  'Electrical & Electronic Engineering',
  'Civil Engineering',
  'Mechanical Engineering',
];

function buildForms() {
  buildFormA();
  buildFormB();
}

function buildFormA() {
  var form = FormApp.create('Engineering & Technology — Faculty Setup');
  form.setCollectEmail(true);

  form.addSectionHeaderItem().setTitle('Contact & faculty basics');
  form.addTextItem().setTitle('Your full name').setRequired(true);
  form.addTextItem().setTitle('Your email').setRequired(true);
  form.addTextItem().setTitle('Academic year, e.g. 2025/2026').setRequired(true);
  form.addMultipleChoiceItem().setTitle('Which semester is this data for?')
      .setChoiceValues(['Term 1', 'Term 2']).setRequired(true);
  form.addTextItem().setTitle('Sessions per week for a typical course (default 2)')
      .setRequired(true);
  form.addMultipleChoiceItem().setTitle('Session length in hours')
      .setChoiceValues(['1', '2', '3']).setRequired(true);

  form.addPageBreakItem().setTitle('Teaching week & time grid');
  var days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  form.addListItem().setTitle('First teaching day').setChoiceValues(days).setRequired(true);
  form.addListItem().setTitle('Last teaching day').setChoiceValues(days).setRequired(true);
  form.addTextItem().setTitle('Day start time, e.g. 07:30').setRequired(true);
  form.addTextItem().setTitle('Day end time, e.g. 18:00').setRequired(true);
  form.addTextItem().setTitle('Lunch/break window to keep free, e.g. 13:00-14:00')
      .setRequired(true);

  form.addPageBreakItem().setTitle('Departments, levels & classes');
  var levels = ['100', '200', '300', '400', '500'];
  DEPARTMENTS.forEach(function (dept) {
    form.addSectionHeaderItem().setTitle(dept);
    form.addMultipleChoiceItem().setTitle('Is ' + dept + ' part of this faculty?')
        .setChoiceValues(['Yes', 'No']);
    form.addCheckboxItem().setTitle('Which levels does ' + dept + ' run?')
        .setChoiceValues(levels);
    levels.forEach(function (lv) {
      form.addTextItem()
          .setTitle(dept + ' — Level ' + lv + ' class size (leave blank if not run)');
    });
  });
  form.addTextItem().setTitle('Any other department not listed above? (name)');
  form.addTextItem().setTitle('Other department levels and class sizes (e.g. 200:75, 300:60)');

  form.addPageBreakItem().setTitle('Rooms & Courses (uploads)')
      .setHelpText('After this script runs, add two File-upload questions here by '
        + 'hand: the completed rooms_template.xlsx and courses_template.xlsx. '
        + 'FormApp cannot create file-upload questions.');

  Logger.log('Form A: ' + form.getEditUrl());
}

function buildFormB() {
  var form = FormApp.create('Engineering & Technology — Lecturer Registration');
  form.setCollectEmail(true);
  form.addTextItem().setTitle('Full name').setRequired(true);
  form.addTextItem().setTitle('Email').setRequired(true);
  form.addListItem().setTitle('Department')
      .setChoiceValues(DEPARTMENTS.concat(['Other'])).setRequired(true);
  form.addTextItem().setTitle('Courses you teach (codes or names, comma-separated)');
  var grid = form.addCheckboxGridItem();
  grid.setTitle('Tick the half-days you are NOT available to teach')
      .setRows(['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'])
      .setColumns(['Morning', 'Afternoon'])
      .setRequired(true);
  Logger.log('Form B: ' + form.getEditUrl());
}
```

- [ ] **Step 2: Verify the script is self-consistent (static check)**

Run: `grep -n "buildFormA\|buildFormB\|addCheckboxGridItem\|file-upload\|FormApp cannot" docs/client_intake/generate_forms.gs`
Expected: both build functions defined and called, the availability grid uses
`addCheckboxGridItem`, and the file-upload limitation is documented. (The script
is only truly verified by running it in script.google.com, which is a manual
operator step — note that in the commit.)

- [ ] **Step 3: Commit**

```bash
git add docs/client_intake/generate_forms.gs
git commit -m "client intake: optional Apps Script to build the forms (file-upload questions added by hand)"
```

---

## Self-Review

**Spec coverage** (against `docs/superpowers/specs/2026-08-14-client-intake-forms-design.md`):
- Form A Sections 1–5 (contact, time grid, departments/levels/classes, rooms upload, courses upload) → Task 2 doc; the two uploads reference Task 1 templates. ✓
- Form B (identity, department, courses, availability grid, one-per-lecturer) → Task 3 doc. ✓
- Rooms Excel columns `building, room_name, capacity, room_type, active` → Task 1 generator + test. ✓
- Courses Excel columns match the faculty-head import incl. `|` sharing → Task 1 generator + `test_courses_header_matches_import_format`, `test_courses_has_a_shared_department_example`. ✓
- Ingestion runbook (order, courses via bulk import, rooms keyed in, lecturers individual, availability complement) → Task 4. ✓
- Deliverables list (2 form specs, 2 xlsx templates, runbook, optional Apps Script) → Tasks 1–5. ✓
- Google Forms caveats (file-upload sign-in, no dynamic dropdowns → linear per-dept blocks, bounded numbers) → Task 2 doc + Task 5 limitation note. ✓
- Enum distinction (course `studio` vs room `outdoor`) → Global Constraints + Task 1 notes sheets. ✓
- Acceptance criteria → Task 4 runbook "Acceptance check". ✓

**Placeholder scan:** No TBD/TODO. Every doc's full content is inlined; the generator and test are complete runnable code. ✓

**Type consistency:** Test header lists match the generator's `ROOMS_HEADER`/`COURSES_HEADER` exactly. `generate_templates` exposes `build_rooms(path)`/`build_courses(path)`, used verbatim by the test fixture. Apps Script `DEPARTMENTS` matches the department blocks in the Form A doc. ✓

**Scope:** One faculty, static documents + one small generator — a single coherent plan. ✓
