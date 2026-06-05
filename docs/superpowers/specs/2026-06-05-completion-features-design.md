# Completion Features Design

**Date:** 2026-06-05
**Project:** UniFord — University Timetabling System (Final Year Project)
**Purpose:** Seven features required to make the system complete and report-ready.

---

## Context

The core system (RBAC, timetable generation, approval workflow, public view, bulk import) is implemented. This spec covers the remaining gaps identified before writing the final year project report.

Students have **no accounts** in the system. They access the timetable via a shareable link the timetable officer copies after publishing and distributes (WhatsApp, email, notice board). Bulk import is for **staff only** (faculty heads, timetable officers, lecturers).

---

## Features

### 1. Lecturer → Course Assignment UI

**Where:** Courses tab inside Management screen (`management_screen.dart` → `_CoursesTab`)

**Behaviour:**
- Each course row gains an edit icon button on the trailing end.
- Tapping opens a dialog showing the course code + name and a dropdown of all users with role `lecturer`, pre-selected on the course's current `lecturerId` (shows "Unassigned" if null).
- A "Save" button calls `PUT /courses/{id}` with `{ "lecturer_id": selectedId }`.
- On success the course list reloads and the row updates.

**API:** `CourseApi.updateCourseLecturer(int courseId, int? lecturerId)` — calls existing `PUT /courses/{id}`.

**Data needed:** `UserApi.getUsers()` filtered client-side to `role == 'lecturer'`. Loaded once when the Courses tab initialises.

---

### 2. Class Groups Management

**Where:** Faculty Setup screen (`faculty_setup_screen.dart`) → inside `_LevelTile`

**Header changes:**
- Add an orange "N groups" badge next to the existing population and courses badges.
- Add a "Add Group" icon button (`Icons.group_add`) next to the existing "Add Course" button in the tile header row.

**Expanded view — tab switcher:**
- When the level tile is expanded, show a tab row with two tabs: **Courses** and **Lab Groups**.
- Courses tab: existing course list (unchanged).
- Lab Groups tab: lists existing groups (name + delete icon). An inline text field + confirm button appears when "Add Group" is tapped; submits `POST /groups/` with `{ "name": name, "class_id": classId }`. Delete calls `DELETE /groups/{id}`.

**API:** Uses existing `POST /groups/`, `DELETE /groups/{id}`, and `GET /groups/?class_id=<id>` endpoints in `academic.py`. Add `getGroups(int classId)` and `createGroup(Map data)` and `deleteGroup(int id)` to `AcademicApi`.

**Data source:** `classId` comes from `widget.level['class_id']` (already returned by the faculty tree endpoint).

---

### 3. Shareable Link on Published Run

**Where:** `timetable_screen.dart` — the run card / detail panel for published runs

**Behaviour:**
- On run cards where `run.status == 'published'`, show a "Copy Link" `IconButton` (`Icons.link`).
- Tapping copies `<origin>/#/public?run=<runId>` to the clipboard using `Clipboard.setData`.
- Shows a snackbar: "Link copied — share with students".
- The public timetable screen reads `?run=<runId>` from `Get.parameters` on load and auto-selects that run.

**No backend change needed.** The public `/runs/public` endpoint already exists and is unauthenticated.

**Flutter web note:** `Uri.base.origin` gives the correct base URL in Flutter web.

---

### 4. Class Filter — Public Timetable

**Where:** `public_timetable_screen.dart`

**Layout:** Horizontal filter bar (Option A from design review) inserted between the AppBar and the timetable grid.

**Controls:** Three cascading dropdowns — Faculty → Department → Level — followed by a filled "View" button and a text "Clear" button.

**Cascade logic:**
- Faculty dropdown loads all faculties via `UniversityApi.getFaculties()` on screen init.
- Selecting a faculty populates the Department dropdown (filtered client-side from all departments).
- Selecting a department populates the Level dropdown from the faculty tree (`GET /faculty-setup/tree?faculty_id=<id>`).
- Tapping "View" sets `_selectedClassId` from the selected level's `class_id`.
- The timetable grid filters entries to only those where `entry.classIds.contains(_selectedClassId)`.
- "Clear" resets `_selectedClassId` to null (shows all entries).

**Deep-link support:** On init, if `Get.parameters['run']` is present, auto-select that run. If `Get.parameters['class']` is also present, auto-apply the class filter.

---

### 5. Class Filter — Internal Timetable

**Where:** `timetable_screen.dart` — above the timetable grid inside the run detail view

**Layout:** Same horizontal filter bar as Feature 4.

**Difference from public filter:**
- Faculty dropdown is pre-filtered to only the faculties included in the current run (`run.facultyIds`).
- Department and Level cascade the same way.
- Visible to all logged-in users (timetable officers, faculty heads, lecturers).
- "Clear" shows all entries for the run.

**Shared widget:** Extract the filter bar into a reusable `_ClassFilterBar` widget used by both screens to avoid duplication.

---

### 6. Manual Entry Editing (Click-to-Edit)

**Where:** `timetable_screen.dart` — tapping a filled session cell on the timetable grid

**Who can use it:** Timetable officers and faculty heads (`user.canManageTimetable || user.isFacultyHead`). For other roles the cell tap does nothing.

**Dialog layout (Option B from design review):**
- Header: course code + name
- 2×2 info cards: Lecturer name, Class(es) — comma-joined names for merged entries, Current slot (blue highlight), Current room with capacity in brackets e.g. "LT-A (120 seats)"
- "Move to slot" dropdown: all time slots for the run's semester
- "Move to room" dropdown: all rooms
- Cancel and Move buttons
- If the backend returns 409, the error message is shown **inside the dialog** in red (not a snackbar) so the user can try a different slot without dismissing.

**API:** Calls existing `PUT /runs/{run_id}/entries/move` with `{ entry_id, new_time_slot_id, new_room_id }`.

**Data needed:** Time slots (already loaded in `TimetableController`), rooms (loaded from `UniversityApi.getRooms()`), lecturer names and room capacities (loaded once when the screen opens).

---

### 7. Change Password

**Where:** Sidebar (`app_shell.dart`) — a "My Account" `ListTile` above the Logout tile

**Behaviour:**
- Tapping opens a dialog with three fields: Current Password, New Password, Confirm New Password (all obscured with show/hide toggles).
- "Save" is disabled until New Password == Confirm New Password and both are non-empty.
- Calls `POST /auth/change-password` with `{ current_password, new_password }`.
- Backend verifies current password against stored hash; if wrong returns 400. On success returns 200.
- On success: dialog closes, snackbar "Password updated".
- On error: inline red message in the dialog.

**Backend:** New endpoint `POST /auth/change-password` in `auth.py`. Requires `get_current_user`. Verifies current password with `verify_password`, then sets `user.hashed_password = get_password_hash(new_password)`.

---

## Shared Widget: `_ClassFilterBar`

Both the public timetable and the internal timetable use the same filter bar. Extract it as:

```dart
class _ClassFilterBar extends StatefulWidget {
  final List<Faculty> faculties;
  final void Function(int? classId) onClassSelected;
  // ...
}
```

Departments and levels are loaded inside the widget as the user makes selections.

---

## What is NOT in scope

- Drag-and-drop timetable editing (click-to-edit covers the use case)
- Student accounts or login
- Email notifications (out of scope for this project phase)
- Exam timetabling (separate problem, not in scope)

---

## Backend changes summary

| File | Change |
|------|--------|
| `backend/app/routers/auth.py` | Add `POST /auth/change-password` endpoint |

All other backend routes already exist.

## Frontend changes summary

| File | Change |
|------|--------|
| `frontend/lib/core/api/academic_api.dart` | Add `getGroups`, `createGroup`, `deleteGroup` |
| `frontend/lib/core/api/course_api.dart` | Add `updateCourseLecturer` |
| `frontend/lib/core/api/auth_api.dart` | Add `changePassword` |
| `frontend/lib/features/management/management_screen.dart` | Lecturer assignment edit on course rows |
| `frontend/lib/features/faculty_setup/faculty_setup_screen.dart` | Groups tab in level tile |
| `frontend/lib/features/timetable/timetable_screen.dart` | Shareable link, class filter bar, click-to-edit dialog |
| `frontend/lib/features/public_timetable/public_timetable_screen.dart` | Class filter bar, deep-link run auto-select |
| `frontend/lib/core/widgets/app_shell.dart` | "My Account" tile → change password dialog |
