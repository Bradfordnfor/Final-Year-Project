# University Timetabling System — Design Spec
**Date:** 2026-04-19
**Case Study:** University of Buea (UB)
**Project Type:** Final Year Project

---

## 1. Overview

A multi-tenant, web-first university timetabling system that automatically generates clash-free timetables while respecting room capacities, lecturer availability, shared courses, lab splits, and group rotations. Built with Flutter (frontend), Python FastAPI (backend), PostgreSQL (database), and Google OR-Tools (constraint solver).

The system targets university admins, faculty/department heads, timetable officers, lecturers, and students. The University of Buea is the reference implementation, but the architecture supports any university.

---

## 2. Tech Stack

| Layer | Technology |
|---|---|
| Frontend / Mobile | Flutter (Web + Android/iOS) |
| Backend API | Python FastAPI |
| Constraint Solver | Google OR-Tools |
| Background Jobs | FastAPI BackgroundTasks |
| Database | PostgreSQL |
| Authentication | JWT tokens |
| Export | PDF + Excel/CSV |

---

## 3. Roles & Permissions

```
Super Admin
  └── University Admin (per university)
        └── Faculty / Department Head
              ├── Timetable Officer
              ├── Lecturer
              └── Student
```

| Role | Permissions |
|---|---|
| Super Admin | Create/manage universities, system-wide settings |
| University Admin | Manage faculties, semesters, academic calendar, rooms, overflow threshold |
| Faculty/Dept Head | Configure session rules, approve/tweak timetable, resolve flagged conflicts |
| Timetable Officer | Input courses/lecturers/populations, trigger generation, review drafts |
| Lecturer | View personal schedule, declare unavailable slots |
| Student | View timetable by department + level + group |

---

## 4. Academic Structure

- **Calendar model:** Semester-based (2 semesters per academic year)
- **Session frequency:** Configurable per faculty/department by the head (e.g. FET = 2 × 2hr sessions per course per week)
- **Time slots:** Defined by University Admin (e.g. 7–9am, 9–11am, 11am–1pm...)
- **Mid-semester changes:** Department heads can move an existing session to a different day/timeslot on a published timetable. They cannot change room type requirements, merge/unmerge classes, or add new courses mid-semester. All changes trigger re-notification to affected users.

---

## 5. Core Data Model

```
University
  └── Faculty
        └── Department
              ├── Level (100, 200, 300...)
              │     └── Class (e.g. EE300, CE300)
              │           ├── Student
              │           └── ClassGroup (subdivision for lab splits)
              └── Course
                    ├── Lecturer (assigned)
                    ├── room_type_required (lecture | lab | studio)
                    └── SharedWith → [other Classes]

Room
  ├── capacity
  ├── type (lecture_hall | lab | studio)
  └── belongs_to → University

Semester
  ├── start_date / end_date
  ├── time_slots[]
  ├── days_of_week[]
  └── belongs_to → University

LecturerAvailability
  ├── Lecturer
  └── unavailable_slots[]

Timetable
  ├── status (draft | under_review | approved | published)
  ├── belongs_to → Semester + Department
  └── TimetableEntry
        ├── Course
        ├── Lecturer
        ├── Room
        ├── Day + TimeSlot
        ├── Classes[] (1 or more — supports merged classes)
        ├── ClassGroup (nullable — set when class is split into groups)
        ├── week_pattern (every_week | odd_weeks | even_weeks | rotation_group)
        └── is_overcapacity (boolean flag)
```

---

## 6. Timetable Generation Algorithm

### 6.1 Timetable Status Workflow
```
Draft → Under Review → Approved → Published
```
Students only see Published timetables. Heads approve before publishing.

### 6.2 Generation Steps

**Step 1 — Input Collection**
- All courses for the semester (per department/level)
- Available rooms + capacities + types
- Lecturer assignments + availability constraints
- Faculty session rules (sessions/week, duration)
- University time slots + days
- Class populations
- Shared course relationships

**Step 2 — Pre-processing: Merge Decision**
For each shared course (e.g. EE300 + CE300 both take ENG 116):
```
combined_population ≤ largest_available_room_capacity
  AND same lecturer available at same slot
  → MERGE into one TimetableEntry (both classes attend together)

otherwise → SEPARATE into two independent TimetableEntries
```

**Step 3 — Pre-processing: Lab Split Decision**
For courses requiring a lab where `class_population > lab_capacity`:
```
groups_needed = ceil(population / lab_capacity)

if groups_needed ≤ sessions_per_week:
  → assign each group to a different session day (same week)

if groups_needed > sessions_per_week:
  → FLAG for head resolution (see Section 6.4)
```

**Step 4 — OR-Tools Constraint Solver**

| Constraint | Type |
|---|---|
| No lecturer teaches two classes simultaneously | Hard |
| No room used by two classes simultaneously | Hard |
| No two courses for the same class at the same time | Hard |
| Right room type for course (lab, lecture, studio) | Hard |
| Lecturer unavailability slots respected | Hard |
| Room capacity ≥ class population | Soft (warn + override) |
| No back-to-back sessions for same lecturer | Soft |
| Spread sessions across the week | Soft |
| Balance lecturer workload across days | Soft |

Hard constraints are never violated. Soft constraints are satisfied where possible; failures generate warnings.

**Step 5 — Output**
Solver returns a complete TimetableEntry list → saved as Draft → officer reviews → forwarded to head → head approves → published.

### 6.3 Overcapacity Handling
Room capacity is a soft constraint. When population > room capacity:
- System assigns the largest available room
- Entry is flagged with `is_overcapacity = true` and shown with an amber highlight
- Officer/Head acknowledges with a one-click override to confirm awareness
- University Admin configures an overflow tolerance threshold (e.g. up to 20% overflow auto-approved; beyond requires explicit head sign-off)
- All overcapacity entries are visible in the analytics dashboard per semester

This reflects real-world university operation (e.g. UB amphitheatres regularly operate above stated capacity).

### 6.4 Head Conflict Resolution Flow
When the system flags a lab split conflict (more groups than weekly sessions):

System shows:
> "EE Lab 201: 3 groups needed but only 2 weekly slots available. Choose a resolution:"

**Option 1 — Add a session this week**
Solver finds an available slot and adds a third session within the week.

**Option 2 — Rotate groups across weeks**
Groups take turns on a weekly rotation:
```
Week 1: Group A → Monday,  Group B → Wednesday
Week 2: Group C → Monday,  Group A → Wednesday
Week 3: Group B → Monday,  Group C → Wednesday
... repeats
```
TimetableEntry `week_pattern` is set to `rotation_group` with rotation sequence stored.

Head can adjust group sizes and rotation order before approving.

### 6.5 Group Assignment & Consistency
When a lab split is created, the system auto-distributes students equally across groups (e.g. 120 students → Group A: 60, Group B: 60). The timetable officer can manually reassign individual students to a different group before the timetable is approved. Once a student is assigned to Group A for a course, they remain in Group A for all sessions of that course throughout the semester.

---

## 7. Flutter App — Screens per Role

**Super Admin**
- Universities list → create/manage universities
- System-wide settings

**University Admin**
- Academic calendar (semesters, time slots, days)
- Faculty & department management
- Room management (capacity, type)
- Overflow tolerance configuration

**Faculty / Department Head**
- Session rule configuration (sessions/week, duration per course)
- Timetable review & approval
- Manual slot adjustments (real-time clash detection)
- Conflict resolution (lab split options)
- Analytics dashboard (room utilization, lecturer workload, overcapacity report)

**Timetable Officer**
- Course input (assign lecturers, set populations, mark shared courses)
- Timetable generation trigger
- Generation status monitor (in progress / completed / failed)
- Draft review before forwarding to head

**Lecturer**
- Personal weekly schedule (across all departments and classes)
- Unavailability declaration (before semester generation)
- Change notifications

**Student**
- Timetable view filtered by department + level + group
- Week pattern indicator (odd/even weeks, rotation group label)
- Shareable read-only link (no login required)

**Shared across all roles**
- In-app notification bell
- PDF + Excel/CSV export
- Dark / light mode

---

## 8. Notifications

Triggered for:
- Timetable published for a semester
- Manual slot change by head (notifies affected lecturers and students)
- Conflict flag requiring head resolution
- Generation completed / failed

Delivery: push notification (mobile), in-app bell (web).

---

## 9. Export

Any timetable view can be exported to:
- **PDF** — formatted for printing (notice boards)
- **Excel/CSV** — for records and further processing

---

## 10. Analytics Dashboard (Head / Admin)

- Room utilization per semester (overbooked, underused, unassigned)
- Lecturer workload distribution (sessions per week per lecturer)
- Overcapacity report (which courses, by how much, how often)
- Group rotation summary

---

## 11. Future Work

The following features are explicitly out of scope for the current implementation but are identified as priority extensions for future development cycles.

### 11.1 Examination Timetabling

The current system addresses **course timetabling** — the assignment of lecture and lab sessions to time slots and rooms across a full semester. A natural and high-value extension is **examination timetabling**, which handles the end-of-semester examination period.

Examination timetabling is a structurally different problem from course timetabling and warrants its own implementation phase:

**Key differences from course timetabling:**

| Aspect | Course Timetabling | Examination Timetabling |
|---|---|---|
| Primary hard constraint | No lecturer or room double-booking | No student sits two exams simultaneously |
| Scheduling period | Full semester (14–16 weeks) | Examination period (1–2 weeks) |
| Constraint target | Lecturer + class group | Individual student registration |
| Room usage | Normal capacity | Often combined rooms, strict seating plans |
| Additional assignment | None | Invigilation (lecturer per exam room) |
| Soft constraints | Spread sessions, balance workload | No student has two exams on the same day |

**What examination timetabling would add to the system:**

- A new `ExamTimetable` entity tied to a semester, separate from the course `Timetable`
- An exam session model: each exam is associated with a course, a duration, and a set of registered students
- A student-conflict constraint in the solver: two exams whose registered student sets overlap must not be scheduled at the same time
- An invigilation assignment module: lecturers are assigned as invigilators to exam rooms, with constraints on workload and availability
- A student-facing exam schedule view showing their personal exam timetable
- A room-split feature: if the number of students sitting an exam exceeds a single room's capacity, the exam is split across multiple rooms with different invigilators

**Why it is deferred:**

The data foundation for examination timetabling — rooms, students, courses, departments, and semesters — is already present in the current system. However, the solver model requires a fundamentally different constraint formulation (student-conflict detection requires access to individual student course registrations, not just class-level population counts), and the invigilation assignment problem adds a second constraint layer on top of the exam scheduling layer. Implementing both correctly within the scope of the current project would risk compromising the quality of the core course timetabling features.

This feature is therefore documented here as a first-priority increment for the next development phase, building directly on the data model and infrastructure established by the current system.

### 11.2 Additional Future Increments

- **Email notifications** — in addition to push and in-app notifications, send email alerts for timetable publication and slot changes
- **Celery + Redis background jobs** — upgrade from FastAPI BackgroundTasks to Celery for higher concurrency and job persistence across server restarts
- **Student group self-assignment** — allow students to choose their own lab group within a defined window, with admin override
- **Timetable version history with rollback** — keep a full audit trail of all published timetables and allow reverting to a previous version
- **Multi-language support** — French language interface for Francophone institutions in Cameroon and the broader Central African region
- **Calendar export** — export personal timetables to Google Calendar / Outlook (.ics format)
- **Public shareable timetable links** — generate a read-only public URL for any published timetable, accessible without login

---

## 12. Constraints Summary

| Decision | Choice | Reason |
|---|---|---|
| Multi-tenant | Yes | Designed for any university, UB as reference |
| Semester-based | Yes | Matches UB academic calendar |
| Session frequency | Faculty-configurable | Differs per faculty (FET = 2 × 2hr) |
| Generation | Hybrid (auto + manual override) | Accuracy + flexibility |
| Capacity constraint | Soft with override | Reflects real-world university operation |
| Lab split | Auto-detect, head resolves flags | Handles UB lab capacity realities |
| Auth | JWT | Standard, stateless, Flutter-compatible |
| DB | PostgreSQL | Handles relational complexity of this domain |
