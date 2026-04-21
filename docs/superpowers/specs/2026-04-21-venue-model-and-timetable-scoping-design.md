# Venue Model & Timetable Scoping — Design Spec

**Date:** 2026-04-21
**Amends:** `2026-04-19-timetabling-system-design.md`
**Scope:** Room types, Building entity, TimetableRun scope, Faculty extract, Role rename

---

## 1. Overview

This spec refines three areas of the original timetabling system design based on UB-specific realities:

1. Rooms belong to **buildings**, not directly to universities
2. Timetable generation is **scoped** — some faculties have dedicated buildings and generate independently; the rest share central buildings and generate one combined timetable
3. Faculty heads can **extract** their faculty's slice from a master timetable
4. The `department_head` role is renamed to `faculty_head`
5. Room types are updated: `studio` removed, `outdoor` added

---

## 2. Updated Room Types

| Type | Description | Capacity enforced by solver? |
|---|---|---|
| `lecture_hall` | Standard classroom or amphitheatre | Yes |
| `lab` | Laboratory requiring small groups | Yes |
| `outdoor` | Open-air venue (e.g. FAVM Teaching Farm) | **No** |

- `studio` is removed entirely — not applicable at UB.
- When a course is assigned to an `outdoor` venue the solver skips all capacity checks for that entry. The slot is still booked normally (no double-booking the venue at the same time).
- Outdoor venues are fixed, named locations entered by the university admin like any other room (e.g. "FAVM Teaching Farm", capacity stored for reference but never used as a hard constraint).

---

## 3. Building Entity

A `Building` sits between `University` and `Room`:

```
University
  └── Building  (e.g. "FET Main Block", "Amphi Complex", "FAVM Teaching Farm")
        └── Room  (e.g. "Amphi 750", "EE Lab 1", "FAVM Open Field")
              ├── capacity
              └── room_type: lecture_hall | lab | outdoor
```

### 3.1 Data Model

```
Building
  ├── id
  ├── name          String(200)
  ├── description   String(500), nullable
  └── university_id → universities.id

Room
  ├── id
  ├── name          String(100)
  ├── capacity      Integer
  ├── room_type     String(20)  — lecture_hall | lab | outdoor
  ├── is_active     Boolean, default True  — False = archived (referenced in history, not bookable)
  └── building_id   → buildings.id   (replaces university_id)
```

### 3.2 Building Management Rules

- University admins create, edit, and delete buildings.
- A building with no rooms deletes cleanly.
- A building with rooms requires the admin to confirm deletion. Rooms that have never appeared in a timetable entry are deleted. Rooms referenced in past timetable entries are **archived** (marked inactive, preserved for historical record).
- A building that is part of an **active or published** `TimetableRun` cannot be deleted until that run is archived.
- New buildings can be added at any time — there is no "setup phase." Adding a new building mid-year just makes its rooms available for the next generation run.

---

## 4. Timetable Generation Scope (TimetableRun)

### 4.1 Concept

At UB, two or three faculties own dedicated buildings and generate their timetables independently. All remaining faculties share central campus buildings and generate one combined master timetable.

Both cases use the same generation engine. The only difference is the **scope** — which faculties and which buildings feed into a given run.

### 4.2 Data Model

```
TimetableRun
  ├── id
  ├── name          String(200)  — e.g. "FET Sem 1 2025/2026"
  ├── semester_id   → semesters.id
  ├── status        String(20)   — draft | generating | generated | published | archived
  ├── created_by    → users.id

TimetableRunFaculty  (many-to-many join)
  ├── run_id        → timetable_runs.id
  └── faculty_id    → faculties.id

TimetableRunBuilding  (many-to-many join)
  ├── run_id        → timetable_runs.id
  └── building_id   → buildings.id
```

### 4.3 How a Run is Configured

1. University admin or timetable officer creates a `TimetableRun` and gives it a name.
2. They select which **faculties** are in scope for this run.
3. They select which **buildings** (and therefore rooms) are available for this run.
4. They trigger generation. The solver uses only the rooms from the selected buildings and schedules only the courses of the selected faculties.

### 4.4 Typical UB Setup Per Semester

| Run name | Faculties | Buildings |
|---|---|---|
| FET Semester Run | Faculty of Engineering & Technology | FET Main Block, FET Labs |
| FHS Semester Run | Faculty of Health Sciences | FHS Building |
| Central Campus Run | All remaining faculties | Amphi Complex, Central Lecture Halls, etc. |

Any faculty that acquires its own building in the future simply gets its own dedicated run. No data migration required — just configure a new run.

### 4.5 TimetableEntry Relationship

`TimetableEntry` (defined in the original spec) links to its parent `TimetableRun`:

```
TimetableEntry
  ├── run_id        → timetable_runs.id   (new field)
  ├── course_id
  ├── lecturer_id
  ├── room_id
  ├── time_slot_id
  ├── classes[]
  ├── class_group_id (nullable)
  ├── week_pattern
  └── is_overcapacity
```

---

## 5. Faculty Extract

### 5.1 What It Is

After a `TimetableRun` is published, every faculty head sees two views:

- **Master view** — the full timetable for the entire run (all faculties, all rooms). Read-only.
- **Faculty extract** — filtered to show only entries where the course belongs to their faculty. Same data, narrower scope.

The extract is **not a separate stored object**. It is computed on the fly by filtering `TimetableEntry` rows where `course.department.faculty_id = current_user.faculty_id`.

### 5.2 Download

Both views offer a download button:
- Full run export → PDF or Excel covering all entries in the run
- Faculty extract export → PDF or Excel covering only that faculty's entries

### 5.3 Permissions

| Action | Who |
|---|---|
| View master timetable | All roles (once published) |
| View faculty extract | Faculty head (scoped to their faculty) |
| Download either | Faculty head, timetable officer, university admin |
| Edit timetable entries | Timetable officer only (via approval flow) |

---

## 6. Role Rename: department_head → faculty_head

`department_head` is renamed to `faculty_head` everywhere — database, API, permissions, Flutter UI.

### 6.1 Updated Role Hierarchy

```
super_admin
  └── university_admin
        └── faculty_head
              ├── timetable_officer
              ├── lecturer
              └── student
```

### 6.2 What Changes

| Before | After |
|---|---|
| `role = "department_head"` | `role = "faculty_head"` |
| User has `department_id` | Faculty head user has `faculty_id` (stored on `users.faculty_id`, a new nullable FK) |
| Approves timetable at department level | Approves timetable at faculty level (sees all departments in their faculty) |
| Cannot see master timetable | Sees master timetable + faculty extract |

### 6.3 User Model Addition

A `faculty_id` nullable foreign key is added to the `users` table to identify which faculty a `faculty_head` belongs to. Other roles continue using `university_id` and `department_id` as before.

---

## 7. Impact on Existing Plans

### Plan 1 (Backend Foundation) — already implemented, needs migrations
| Change | Action |
|---|---|
| `room.university_id` → `room.building_id` | New Alembic migration |
| New `buildings` table | New Alembic migration |
| New `timetable_runs`, `timetable_run_faculties`, `timetable_run_buildings` tables | Part of Plan 2 |
| `role = "department_head"` → `"faculty_head"` | Data migration + code update |
| `users.faculty_id` added | New Alembic migration |
| Room type validator: remove `studio`, add `outdoor` | Code update in `schemas/room.py` |

### Plan 2 (Timetable Generation Engine) — not yet started
- `TimetableRun` replaces the implicit per-department timetable scope
- Solver input collection is scoped to the run's faculties and buildings
- Outdoor venue capacity skip added as a pre-check before constraint loading

### Plan 3 (Flutter Frontend) — not yet started
- Building management screen (create, edit, delete building; add/remove rooms)
- TimetableRun configuration screen (name, select faculties, select buildings, trigger generation)
- Master timetable view + faculty extract tab for faculty heads
- Role label "Department Head" → "Faculty Head" throughout UI
- Offline cache implementation (see Section 8)

---

## 8. Offline Support Strategy

### 8.1 Approach: Partial Offline (Read Cache)

Full offline-first sync is out of scope — it requires a local database, conflict resolution, and dirty state management that adds disproportionate complexity for a final year project.

Instead, the app implements **read-cache offline support**: the last successfully fetched data is stored locally and served when the device has no internet connection.

### 8.2 What Works Offline

| Feature | Offline behaviour |
|---|---|
| View published timetable | Served from local cache (last fetched version) |
| View personal schedule (lecturer / student) | Served from local cache |
| Browse course list, room list, lecturer profiles | Served from local cache |
| View faculty extract | Served from local cache |

### 8.3 What Requires Internet

| Feature | Offline behaviour |
|---|---|
| Login | Disabled — shows "No internet connection" message |
| Timetable generation | Disabled — server-side computation |
| Any create / edit / delete operation | Disabled — shows "No internet connection" message |
| Timetable approval / publishing | Disabled |
| Lecturer availability declaration | Disabled |

### 8.4 User Experience

- A persistent **connectivity banner** appears at the top of the app when offline: `"You're offline — showing saved data"`
- All action buttons (create, save, generate, approve) are disabled while offline
- Read-only views load normally from cache
- When internet is restored the banner disappears and the app silently re-fetches fresh data in the background

### 8.5 Implementation (Flutter)

- **Local storage**: `Hive` (fast, lightweight, no SQL schema needed for caching JSON responses)
- **Connectivity detection**: `connectivity_plus` package
- **Cache invalidation**: cached timetable is replaced on every successful API fetch — no manual invalidation needed
- **What is cached**: the full published timetable response and the current user's profile, stored as JSON keyed by semester + user ID
- **What is not cached**: admin data (buildings, rooms, users list) — these are management screens that always require internet anyway
