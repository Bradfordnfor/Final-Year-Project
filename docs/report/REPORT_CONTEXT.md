# Final Year Report — Master Context

> Single source of truth for writing NFOR RINGDAH BRADFORD's FYP dissertation.
> If a session is lost, read THIS file first to restore full context.

---

## 1. Identity (verbatim — appears on cover, title page, certification)

- **Full name:** NFOR RINGDAH BRADFORD
- **Matriculation number:** FE22A257
- **Option:** Software Engineering
- **Supervisor:** Dr. Nde Nguti
- **Academic Year:** 2025/2026
- **Degree:** Bachelor of Engineering (B.Eng.) in Computer Engineering
- **Institution:** Department of Computer Engineering, Faculty of Engineering and Technology, University of Buea
- **Project Title:** *Design and Implementation of an Automated Timetable Generation and Management System for Universities*

---

## 2. Deliverable & tooling decisions

- **Output:** a formatted Microsoft Word `.docx` (submission-ready).
- **Build approach:** chapter content written as markdown in `docs/report/chapters/`, then assembled into the `.docx` by `docs/report/build_report.py` (python-docx).
- **Diagrams:** PlantUML sources in `docs/report/diagrams/` (ER, Use Case, Class, Sequence, Activity). User renders to PNG (plantuml.com / VS Code) and drops into the doc.
- **Pace:** chapter by chapter; user reviews each before the next.
- **Language:** Standard Formal English. MUST read human-like / natural — NOT AI-generic. Avoid: "In conclusion…", "leverage cutting-edge", "delve into", "it is worth noting", robotic parallelism, empty hedging. Write like a competent student who actually built the thing.

---

## 3. Formatting rules (UB 2026 guidelines — ENFORCE in build_report.py)

- Paper A4. Font **Times New Roman**.
- Font sizes: **Chapter titles 16pt**, **subheadings 14pt**, **body 12pt**.
- Margins: **2.5cm left & right**, **2cm top & bottom**.
- Line spacing **1.5** for body. Justified alignment.
- Page limit **45–65** incl. preliminary pages.
- Page numbering: **Roman (i, ii, iii)** for preliminary pages; **Arabic (1,2,3…)** starting at first page of Chapter 1.
- Heading numbering depth max **second subheading** (1 → 1.1 → 1.1.1; no 1.1.1.1).
- Blank line before/after every section & subsection. Paragraphs justified, separated by blank line.
- **No headers/footers** (page number only).
- Cover page colour: Blue. Spiral binding (physical only).
- References: **APA** style.

### Required structure (order)
Preliminary pages:
1. Cover page (blue, bordered — per sample)
2. Title page (Roman i)
3. **Certification of Originality** (REQUIRED — signed by student, supervisor, HOD)
4. Dedication (optional, ≤3 honourees)
5. Acknowledgement
6. **Abstract** (REQUIRED — ~400 words, 1–2 paragraphs, ends with Keywords) ← *NEW vs old sample which lacked it*
7. Table of Contents
8. List of Tables
9. List of Figures
10. List of Abbreviations

Chapters:
- **CH1 General Introduction (15–20 pp):** Background/Context; Problem Statement; Objectives (General+Specific); Proposed Methodology; Research Questions (*if applicable*); Research Hypothesis (*if applicable*); Significance; Scope; Delimitation; Definition of Keywords/Terms; Organization of Dissertation.
- **CH2 Literature Review (15–25 pp):** Introduction; General Concepts; Related Works; Partial Conclusion.
- **CH3 Analysis and Design (15–20 pp):** Introduction; Methodology; Analysis (functional/non-functional reqs); Design (ER, Use Case, Class, Sequence, Activity, UI); Global Architecture; Description of Algorithms; Description of Resolution Process; Partial Conclusion.
- **CH4 Implementation and Results (15–20 pp):** Introduction; Tools & Materials; Description of Implementation Process; Presentation & Interpretation of Results (screenshots); Evaluation of the Solution; Partial Conclusion.
- **CH5 Conclusion and Further Works (3–10 pp):** Summary of Findings; Contribution to Engineering & Technology; Recommendations; Difficulties Encountered; Further Works. *(NOTE: sample mislabels Ch5 as "Implementation and Results" — DO NOT repeat that error.)*

References (APA). Appendices (code, extra diagrams).

---

## 4. Project framing decision

This is an **engineering build project**, NOT an empirical study (unlike the AR sample which had participants/pre-post tests).
- Research Questions / Hypothesis / "Participants" / "pre-post assessment" mostly **DO NOT apply** → keep minimal or omit under "if applicable".
- Weight goes to: Problem Statement, Objectives, **Design (ER+UML)**, Implementation, and Evaluation (vs manual timetabling & existing systems).
- The technical contribution to foreground: **constraint-based automatic generation (OR-Tools CP-SAT)** + the **multi-role approval workflow**.

---

## 5. The system that was actually built (ground truth for accuracy)

**Architecture:** Web/app system. FastAPI (Python) backend + Flutter (Dart) frontend. Client–server, REST/JSON over HTTP.

**Backend stack:** FastAPI, SQLAlchemy 2.0 ORM, Alembic migrations, JWT auth, RBAC, OR-Tools 9.15 CP-SAT solver, ReportLab (PDF), SQLite (dev DB). Python 3.13.

**Frontend stack:** Flutter 3.22+, Dart, GetX (state mgmt + routing + DI), Dio (HTTP), flutter_secure_storage, fl_chart, google_fonts (Inter). Web-first, mobile-friendly, adaptive layout (sidebar ≥1100px / NavigationRail 720–1100 / BottomNav <720).

**Data hierarchy:** University → Faculty → Department → Level → Class (with population) → ClassGroup (lab splits). Building → Room (capacity, room_type: lecture_hall|lab|outdoor). Semester → TimeSlot. Course (belongs to level/department OR university-wide; has room_type_required, weekly_hours, optional lecturer). Lecturer (linked to User) with availability. Student (linked to class/group — note: students have NO login in final design; access timetable via shared public link).

**Roles (RBAC hierarchy):** super_admin (system-level, manages universities) → university_admin (buildings, users, semesters, courses) → faculty_head (faculty academic data, approves timetables) → timetable_officer (creates runs, generates, resolves conflicts, publishes) → lecturer (own schedule, availability) → student (public timetable only, no account).

**Timetable generation (the engineering core):**
- Preprocessor: builds solver input from DB; merge decision (shared courses across classes) + lab-split logic (large class → groups) + university-wide-course bin-packing (every class sits it; classes packed into hall-sized groups) + off-site/outdoor courses build sessions needing NO room.
- Solver: OR-Tools CP-SAT. Hard constraints — no lecturer/class/room double-booking, room-type match, lecturer unavailability, room capacity / overflow threshold (overflow permitted but flagged). NOW a constraint OPTIMISATION: objective minimises wasted seats (capacity − population) with a heavy penalty for too-small rooms, so big/joint sessions get the big halls. Off-site sessions get a per-session virtual room (negative id) so the uniform session-slot-room model holds.
- Postprocessor: writes solver output to DB as TimetableEntry rows; flags overcapacity/merged; stores room_id = NULL for off-site (virtual-room) placements.
- Async generation via background job; job-status polling.

**Workflow (status machine):** draft → under_review → approved → published.
- Timetable officer generates draft → submits for review.
- Each faculty head in the run approves/rejects their faculty's section (FacultyHeadApproval table). All approve → run becomes approved.
- Officer publishes approved run → notifications fired; run appears on public page.

**Conflict resolution:** lab-split conflicts flagged; resolved by add_session (extra weekly slot) or rotate_groups (alternating weeks).

**Other features built:** manual slot move with clash detection (click-to-edit dialog, 409 on clash shown inline); analytics endpoint (sessions/lecturer with click-through course breakdown, overcapacity count, room utilization) — NOT visible to officer; university_admin sees whole run, faculty_head sees only their faculty; PDF + CSV export (ReportLab) with optional class-scope filter (`class_ids=`); notifications on publish/review/approve/reject; **name-based bulk import** of lecturers via CSV (`name,email,faculty,department,password`; faculty/dept matched by name within the admin's university; password optional/auto-generated; per-row skip reasons); university creation with admin credentials; typed-name delete protection; university-wide courses; class population editable; lecturer→course assignment; lecturer self-service availability (`/lecturers/me` auto-provisions profile); class groups management; shareable public link (`/#/public?run=<id>`); public + internal timetable with Faculty→Dept→Level class filter supporting partial scope (faculty-wide / dept-wide / single class); free-rooms-by-period panel; **public timetable download** (CSV/PDF via unauthenticated `/export/public/runs/{id}/...`, published runs only, honours the class filter); **My Account** dialog showing name+role (read-only) and editable email (`POST /auth/change-email`, unverified — invitation/verification is future work), with change-password behind a button. **Run-list visibility by role+status:** officer & university_admin see all states; faculty_head & lecturer see only under_review + published; drafts private to officer/admin. **Regeneration replaces** the previous result (clears entries/conflicts first).

**Screens (Flutter):** login, dashboard (role-adaptive), timetable (run list + grid + generate/submit/approve/publish + filter + click-to-edit), generation, conflicts, management (buildings/users/semesters/courses tabs), faculty setup (faculties/depts/levels/courses/groups tree), bulk import, public timetable, universities (super admin), notifications, analytics, app shell (adaptive nav + My Account/change password).

**Design language:** Royal/electric blue primary (#1D4ED8), ember-orange accent, Inter font, Material 3, adaptive responsive.

---

## 6. Status of report

- [x] CH1 General Introduction → `docs/report/chapters/ch1.md` (DONE, user-approved; weekly-timetable terminology confirmed; no Research Hypothesis by design; voice = measured impersonal academic, UB-grounded)
- [x] CH2 Literature Review → `docs/report/chapters/ch2.md` (DONE, user-approved; gap argument = existing tools are single-planner/desktop, non-Cameroonian structure, no approval workflow, no student distribution)
- [x] CH3 Analysis and Design → `docs/report/chapters/ch3.md` (DONE; 11 figures with PlantUML sources in `docs/report/diagrams/`. Amended for the readiness-guard + faculty-scoping enhancements: §3.3.1 generation+access reqs, §3.3.2 security, §3.7 resolution process. **Further amended 2026-06-21 (§3.6):** solver reframed as constraint OPTIMISATION with a room-fit objective; §3.6.1 adds university-wide bin-packing and off-site/no-room courses; §3.6.3 notes nullable room; §3.3.3 (Monitoring) + §3.4.2 (use cases) add analytics role-scoping and run-visibility-by-status. seq_generation.puml and activity_generation.puml updated to show the readiness gate — user to re-render. Presentation-only diagram variants also exist: usecase_pres_a/b, class_pres_academic/timetable/solver, er_overview.)
- [~] CH4 Implementation and Results → `docs/report/chapters/ch4.md` (§4.1 Intro, §4.2 Tools & Materials [Tables 4.1, 4.2], §4.3 Implementation Process [4.3.1–4.3.7] DRAFTED; §4.3.4 amended 2026-06-21 to add the objective, university-wide packing, off-site placeholder-room handling; §4.3.5 notes regeneration-replaces; §4.3.3 now covers run-list status scoping + analytics role-scoping. §4.4 Results, §4.5 Evaluation, §4.6 Partial Conclusion DRAFTED 2026-06-21 from the regenerated Run 1 case study (FET, S1 2025/2026). Figures in Table 4.3: optimal, ~32s, 185 sessions, 89 courses (3 university-wide), 13 classes, 45 lecturers, 8 rooms, 34 periods, 32 merged, 2 off-site, 9 overcapacity, 4 lab conflicts, 0/0/0 clashes. §4.5 has objectives scorecard (Table 4.4) + correctness/speed/coordination + 45→9 overcapacity before/after objective + limitations. **PENDING: 10 user screenshots — Figures 4.1–4.10** (placeholders embedded with captions = shot list). Regen done via backend/scripts/regen_case_study.py. CH4 effectively complete bar the screenshots.)
- [x] CH5 Conclusion and Further Works → `docs/report/chapters/ch5.md` (DRAFTED 2026-06-21; titled correctly, NOT the sample's mislabel. Sections: 5.1 Summary of Findings, 5.2 Contribution to Engineering & Technology, 5.3 Recommendations, 5.4 Difficulties Encountered, 5.5 Further Works [email-backed invitation flow, soft preferences, scale/optimality, exams/calendar/mobile], 5.6 Concluding Remarks. Grounded in the case-study figures and §4.5.7 limitations.)
- [ ] Preliminary pages (abstract, dedication, ack, ToC, lists)
- [ ] build_report.py → final .docx
- [ ] References (APA)

Plans/specs already in repo: `docs/superpowers/specs/`, `docs/superpowers/plans/`.

### Voice/style lock (match across all chapters)
Measured impersonal academic ("This work…", "the system…"), grounded in UB specifics, varied sentence length, NO AI tells (no "delve/leverage/cutting-edge/in conclusion/seamless/robust"-spam). Human, like a competent student who built it.

### References used so far (all REAL — keep consistent, build APA list at end)
de Werra (1985); Even, Itai & Shamir (1976); Wren (1996); Schaerf (1999); Carter, Laporte & Lee (1996); Burke & Petrovic (2002); Abramson (1991); Colorni, Dorigo & Maniezzo (1990); Perron & Furnon (2019, OR-Tools). Systems: UniTime (Müller), FET, aSc Timetables, Lantiv, Mimosa. ITC 2002/2007/2019.

### CH3 plan (for next session)
Sections: 3.1 Introduction; 3.2 Methodology; 3.3 Analysis (functional + non-functional requirements); 3.4 Design [3.4.1 ER diagram, 3.4.2 Use Case, 3.4.3 Class, 3.4.4 Sequence (generation, approval, manual-move), 3.4.5 Activity (generation+approval), 3.4.6 UI design]; 3.5 Global Architecture (client–server: Flutter ↔ FastAPI ↔ SQLite + OR-Tools); 3.6 Description of the Algorithms (CP-SAT model: variables, hard constraints, preprocessor merge/lab-split, postprocessor); 3.7 Description of the Resolution Process; 3.8 Partial Conclusion.
Diagrams → PlantUML in `docs/report/diagrams/`. ER entities: University, Faculty, Department, Level, Class, ClassGroup, Building, Room, Semester, TimeSlot, Course, Lecturer, (User), TimetableRun, TimetableEntry, FacultyHeadApproval, Notification. Use Case actors: SuperAdmin, UniversityAdmin, FacultyHead, TimetableOfficer, Lecturer, Student.
