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
