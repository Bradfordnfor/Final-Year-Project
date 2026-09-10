# Timetable Grid PDF Download Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the timetable PDF download a readable days×slots grid (each cell stacking every concurrent session as Course · Lecturer · Hall), with a course-code legend, a faded system-logo watermark, a minimal footer, and a track option in the download filter — while the CSV export stays exactly as-is.

**Architecture:** All rendering is backend ReportLab in `app/routers/export.py`. A pure `build_grid(rows)` turns the existing detail rows into an in-memory grid model (days, slots, cells, legend) that is unit-tested without parsing PDF bytes. A `_grid_pdf_response` renders that model to a landscape PDF; a `_NumberedCanvas` + watermark callback add the footer and faded logo on every page. Both PDF endpoints (internal and public) switch from the flat-list `_pdf_response` to the grid. The frontend filter bar gains a Track dropdown fed by an extended `public-levels` endpoint.

**Tech Stack:** FastAPI, SQLAlchemy 2.0, ReportLab, Pillow (both already installed), pytest (SQLite), Flutter/GetX.

## Global Constraints

- **CSV export is unchanged** — `/export/runs/{id}/csv`, `/export/public/runs/{id}/csv`, `_get_entries_with_details`'s existing 9 columns, and `_csv_response` must produce byte-for-byte the same output. Verify with a column-header regression assertion.
- **No change to the on-screen grid widgets** (`timetable_screen.dart`, `public_timetable_screen.dart`). Only the filter bar (`class_filter_bar.dart`) changes on the frontend.
- The grid replaces the flat-list PDF for **both** `export_pdf` and `export_public_pdf`. The old `_pdf_response` (flat-list PDF) is removed once unused.
- The watermark is the **fixed system logo**, identical on every timetable; no per-university logo. If the asset is missing, the PDF still renders (watermark skipped, not an error).
- Weekdays order by a canonical `WEEKDAY_ORDER` (Mon→Sun), never alphabetically. Unknown day strings sort last.
- Backend commands run from `backend/` via the venv: `./venv/Scripts/python.exe -m pytest ...`. Frontend from `frontend/`: `flutter analyze`.
- Commit style: plain messages, no `feat:`/`fix:` prefixes, no `Co-Authored-By` line.
- `flutter analyze` baseline is 37 info-level issues; add zero new.

---

### Task 1: Grid model — `build_grid` (pure, unit-tested)

**Files:**
- Modify: `backend/app/routers/export.py` (add `WEEKDAY_ORDER`, `build_grid`)
- Test: `backend/tests/test_grid_build.py`

**Interfaces:**
- Consumes: detail rows from `_get_entries_with_details` — dicts with keys `"Day"` (e.g. `"Monday"`), `"Time"` (e.g. `"07:00-09:00"`), `"Course"` (e.g. `"CEF401 — Internet Programming"`), `"Lecturer"`, `"Room"`.
- Produces: `WEEKDAY_ORDER: list[str]`; `build_grid(rows: list[dict]) -> dict` returning
  `{"days": list[str], "slots": list[str], "cells": dict[tuple[str,str], list[dict]], "legend": list[tuple[str,str]]}`
  where each cell dict is `{"code": str, "lecturer": str, "hall": str}` sorted by code, and `legend` is `(code, name)` pairs sorted by code. Code/name are derived by splitting `"Course"` on the first `" — "` (course codes never contain `" — "`, so this is safe and leaves CSV untouched).

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_grid_build.py`:

```python
from app.routers.export import build_grid, WEEKDAY_ORDER


def _row(day, time, course, lecturer, room):
    return {"Day": day, "Time": time, "Course": course,
            "Lecturer": lecturer, "Room": room}


def test_concurrent_sessions_share_a_cell():
    rows = [
        _row("Monday", "07:00-09:00", "CEF401 — Internet Programming", "Dr A", "Hall 1"),
        _row("Monday", "07:00-09:00", "EEF305 — Signals", "Dr B", "Hall 3"),
    ]
    grid = build_grid(rows)
    cell = grid["cells"][("Monday", "07:00-09:00")]
    codes = [c["code"] for c in cell]
    assert codes == ["CEF401", "EEF305"]  # sorted by code
    assert cell[0]["lecturer"] == "Dr A" and cell[0]["hall"] == "Hall 1"


def test_days_use_canonical_order_not_alphabetical():
    rows = [
        _row("Friday", "07:00-09:00", "X1 — A", "L", "H"),
        _row("Monday", "07:00-09:00", "X2 — B", "L", "H"),
    ]
    grid = build_grid(rows)
    assert grid["days"] == ["Monday", "Friday"]


def test_slots_ordered_by_start_time():
    rows = [
        _row("Monday", "13:00-15:00", "X1 — A", "L", "H"),
        _row("Monday", "07:00-09:00", "X2 — B", "L", "H"),
    ]
    grid = build_grid(rows)
    assert grid["slots"] == ["07:00-09:00", "13:00-15:00"]


def test_legend_lists_each_code_once_sorted():
    rows = [
        _row("Monday", "07:00-09:00", "EEF305 — Signals", "L", "H"),
        _row("Tuesday", "07:00-09:00", "EEF305 — Signals", "L", "H"),
        _row("Monday", "09:00-11:00", "CEF401 — Internet Programming", "L", "H"),
    ]
    grid = build_grid(rows)
    assert grid["legend"] == [
        ("CEF401", "Internet Programming"),
        ("EEF305", "Signals"),
    ]


def test_outdoor_session_hall_text():
    rows = [_row("Monday", "07:00-09:00", "AGF200 — Field Work", "Dr C",
                 "Outdoor / off-site")]
    grid = build_grid(rows)
    assert grid["cells"][("Monday", "07:00-09:00")][0]["hall"] == "Outdoor / off-site"


def test_weekday_order_constant():
    assert WEEKDAY_ORDER[:2] == ["Monday", "Tuesday"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./venv/Scripts/python.exe -m pytest tests/test_grid_build.py -v`
Expected: FAIL with `ImportError: cannot import name 'build_grid'`.

- [ ] **Step 3: Implement `WEEKDAY_ORDER` and `build_grid`**

In `backend/app/routers/export.py`, after the imports (before `_resolve_class_filter`), add:

```python
WEEKDAY_ORDER = ["Monday", "Tuesday", "Wednesday", "Thursday",
                 "Friday", "Saturday", "Sunday"]


def build_grid(rows: list[dict]) -> dict:
    """Turn flat detail rows into a days×slots grid model.

    Pure and side-effect free so it can be unit-tested without rendering a PDF.
    Course code and name are split from the existing "Course" field
    ("<code> — <name>"), so the CSV export's row shape is untouched.
    """
    def _split_course(course: str) -> tuple[str, str]:
        parts = course.split(" — ", 1)
        code = parts[0].strip()
        name = parts[1].strip() if len(parts) > 1 else ""
        return code, name

    def _day_key(day: str) -> int:
        return WEEKDAY_ORDER.index(day) if day in WEEKDAY_ORDER else len(WEEKDAY_ORDER)

    def _slot_start(slot: str) -> str:
        return slot.split("-", 1)[0]

    cells: dict[tuple[str, str], list[dict]] = {}
    legend: dict[str, str] = {}
    day_set: set[str] = set()
    slot_set: set[str] = set()

    for r in rows:
        day = r.get("Day", "")
        slot = r.get("Time", "")
        code, name = _split_course(r.get("Course", ""))
        day_set.add(day)
        slot_set.add(slot)
        cells.setdefault((day, slot), []).append({
            "code": code,
            "lecturer": r.get("Lecturer", ""),
            "hall": r.get("Room", ""),
        })
        if code:
            legend[code] = name

    for cell in cells.values():
        cell.sort(key=lambda c: c["code"])

    days = sorted(day_set, key=_day_key)
    slots = sorted(slot_set, key=_slot_start)
    return {
        "days": days,
        "slots": slots,
        "cells": cells,
        "legend": sorted(legend.items(), key=lambda kv: kv[0]),
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./venv/Scripts/python.exe -m pytest tests/test_grid_build.py -v`
Expected: PASS (6 passed).

- [ ] **Step 5: Commit**

```bash
git add backend/app/routers/export.py backend/tests/test_grid_build.py
git commit -m "timetable export: pure build_grid model with canonical weekday ordering and course-code legend"
```

---

### Task 2: Render the grid PDF with watermark and footer; rewire both PDF endpoints

**Files:**
- Create: `backend/app/assets/watermark_logo.png` (copy of the system logo)
- Modify: `backend/app/routers/export.py` (grid renderer, watermark, footer, rewire `export_pdf` + `export_public_pdf`, remove `_pdf_response`, pin CSV fieldnames)
- Test: `backend/tests/test_grid_pdf.py`

**Interfaces:**
- Consumes: `build_grid` (Task 1); the run's `faculties` relationship (`run.faculties[i].faculty.university.name`, `.faculty.code`/`.name`).
- Produces: `_grid_pdf_response(grid, run, filtered, filename) -> StreamingResponse`; `_load_faded_logo(path) -> ImageReader | None`. `export_pdf`/`export_public_pdf` now return the grid PDF.

- [ ] **Step 1: Bundle the logo asset**

Run (from `backend/`):

```bash
mkdir -p app/assets && cp ../frontend/assets/images/logo.png app/assets/watermark_logo.png && ls -la app/assets/watermark_logo.png
```

Expected: the file exists (~148 KB).

- [ ] **Step 2: Write the failing tests**

Create `backend/tests/test_grid_pdf.py`:

```python
from app.routers.export import _load_faded_logo
from app.models.timetable import (
    TimetableRun, TimetableEntry, TimetableEntryClass,
)


def _run_with_two_classes(db, creator_id):
    run = TimetableRun(name="R", semester_id=1, created_by=creator_id,
                       status="draft")
    db.add(run); db.flush()
    e1 = TimetableEntry(run_id=run.id, course_id=1, lecturer_id=1, room_id=1,
                        time_slot_id=1, week_pattern="every_week")
    e2 = TimetableEntry(run_id=run.id, course_id=1, lecturer_id=1, room_id=1,
                        time_slot_id=1, week_pattern="every_week")
    db.add_all([e1, e2]); db.flush()
    db.add(TimetableEntryClass(entry_id=e1.id, class_id=101))
    db.add(TimetableEntryClass(entry_id=e2.id, class_id=202))
    db.commit()
    return run


def test_grid_pdf_endpoint_returns_pdf(client, auth_headers, db, admin_user):
    run = _run_with_two_classes(db, admin_user.id)
    r = client.get(f"/export/runs/{run.id}/pdf", headers=auth_headers)
    assert r.status_code == 200
    assert r.headers["content-type"] == "application/pdf"
    assert r.content[:4] == b"%PDF"


def test_grid_pdf_filtered_returns_pdf(client, auth_headers, db, admin_user):
    run = _run_with_two_classes(db, admin_user.id)
    r = client.get(f"/export/runs/{run.id}/pdf?class_ids=101", headers=auth_headers)
    assert r.status_code == 200
    assert r.content[:4] == b"%PDF"


def test_public_grid_pdf_requires_published(client, db, admin_user):
    run = _run_with_two_classes(db, admin_user.id)  # draft
    assert client.get(f"/export/public/runs/{run.id}/pdf").status_code == 404
    run.status = "published"; db.commit()
    r = client.get(f"/export/public/runs/{run.id}/pdf")
    assert r.status_code == 200 and r.content[:4] == b"%PDF"


def test_missing_logo_asset_is_not_fatal():
    assert _load_faded_logo("/no/such/logo.png") is None
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `./venv/Scripts/python.exe -m pytest tests/test_grid_pdf.py -v`
Expected: FAIL — `ImportError: cannot import name '_load_faded_logo'`.

- [ ] **Step 4: Implement the renderer, watermark, footer, and rewiring**

In `backend/app/routers/export.py`:

(a) Extend the imports at the top:

```python
import os
from xml.sax.saxutils import escape
from io import BytesIO
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from PIL import Image
```

(Keep the existing `import io` / other imports; the `csv`, `StreamingResponse`, model imports stay.)

(b) Add the module-level logo path and loader (after `WEEKDAY_ORDER`):

```python
_LOGO_PATH = os.path.join(os.path.dirname(__file__), "..", "assets", "watermark_logo.png")
_FADED_LOGO_CACHE: dict = {}


def _load_faded_logo(path: str):
    """Return an ImageReader of the logo faded to a light watermark, or None if
    the asset is missing (so the PDF still renders without it). Cached per path."""
    if path in _FADED_LOGO_CACHE:
        return _FADED_LOGO_CACHE[path]
    result = None
    if os.path.exists(path):
        img = Image.open(path).convert("RGBA")
        alpha = img.split()[3].point(lambda a: int(a * 0.08))  # 8% opacity
        img.putalpha(alpha)
        buf = BytesIO()
        img.save(buf, format="PNG")
        buf.seek(0)
        result = ImageReader(buf)
    _FADED_LOGO_CACHE[path] = result
    return result
```

(c) Add the run-identity helper and the per-page canvas that draws watermark + footer:

```python
def _run_identity(run) -> str:
    """University · faculty codes for the run's footer (minimal, no departments)."""
    uni_name = ""
    fac_labels = []
    for rf in run.faculties:
        fac = rf.faculty
        if not fac:
            continue
        fac_labels.append(fac.code or fac.name)
        if fac.university:
            uni_name = fac.university.name
    parts = [p for p in [uni_name, *fac_labels] if p]
    return " · ".join(parts)


class _StampCanvas(canvas.Canvas):
    """Draws the faded logo watermark (centered) and a footer line
    (identity left, 'Page X of Y' right) on every page. Page total is known
    only at save time, so pages are buffered."""
    identity = ""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved = []

    def showPage(self):
        self._saved.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        total = len(self._saved)
        for state in self._saved:
            self.__dict__.update(state)
            self._draw_stamps(total)
            super().showPage()
        super().save()

    def _draw_stamps(self, total):
        w, h = self._pagesize
        logo = _load_faded_logo(_LOGO_PATH)
        if logo is not None:
            size = 90 * mm
            self.drawImage(logo, (w - size) / 2, (h - size) / 2,
                           width=size, height=size, mask="auto")
        self.setFont("Helvetica", 8)
        self.setFillColor(colors.grey)
        self.drawString(15 * mm, 8 * mm, self.identity)
        self.drawRightString(w - 15 * mm, 8 * mm,
                             f"Page {self._pageNumber} of {total}")
```

(d) Add the grid renderer:

```python
def _grid_pdf_response(grid: dict, run, filtered: bool, filename: str) -> StreamingResponse:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=landscape(A4),
                            leftMargin=12 * mm, rightMargin=12 * mm,
                            topMargin=12 * mm, bottomMargin=14 * mm)
    styles = getSampleStyleSheet()
    cell_style = ParagraphStyle("cell", parent=styles["Normal"],
                                fontSize=7, leading=8)
    legend_style = ParagraphStyle("legend", parent=styles["Normal"],
                                  fontSize=8, leading=10)

    days = grid["days"]
    slots = grid["slots"]

    def _cell(day, slot):
        sessions = grid["cells"].get((day, slot), [])
        if not sessions:
            return ""
        blocks = []
        for s in sessions:
            blocks.append(
                f"<b>{escape(s['code'])}</b><br/>"
                f"{escape(s['lecturer'])} · {escape(s['hall'])}"
            )
        return Paragraph("<br/><br/>".join(blocks), cell_style)

    header = ["Time"] + days
    table_data = [header]
    for slot in slots:
        table_data.append([slot] + [_cell(day, slot) for day in days])

    time_w = 22 * mm
    day_w = (doc.width - time_w) / max(len(days), 1)
    col_widths = [time_w] + [day_w] * len(days)

    table = Table(table_data, colWidths=col_widths, repeatRows=1)
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1a237e")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, 0), 9),
        ("FONTSIZE", (0, 1), (0, -1), 8),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f5f5f5")]),
    ]))

    title = f"Timetable — {run.name}" + (" (filtered)" if filtered else "")
    story = [Paragraph(title, styles["Title"]), Spacer(1, 6), table, Spacer(1, 12)]

    if grid["legend"]:
        story.append(Paragraph("<b>Course codes</b>", legend_style))
        legend_lines = "<br/>".join(
            f"{escape(code)} — {escape(name)}" for code, name in grid["legend"]
        )
        story.append(Paragraph(legend_lines, legend_style))

    _StampCanvas.identity = _run_identity(run)
    doc.build(story, canvasmaker=_StampCanvas)
    buffer.seek(0)
    return StreamingResponse(
        buffer,
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )
```

(e) Rewire `export_pdf` to build the grid:

```python
@router.get("/runs/{run_id}/pdf")
def export_pdf(
    run_id: int,
    class_id: int | None = None,
    class_ids: str | None = None,
    db: Session = Depends(get_db),
    _: UserModel = Depends(get_current_user),
):
    run = db.get(TimetableRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Timetable run not found")
    ids = _resolve_class_filter(class_ids, class_id)
    rows = _rows_or_404(run_id, db, ids)
    suffix = "_filtered" if ids else ""
    grid = build_grid(rows)
    return _grid_pdf_response(grid, run, bool(ids),
                             f"timetable_run_{run_id}{suffix}.pdf")
```

(f) Rewire `export_public_pdf` the same way:

```python
@router.get("/public/runs/{run_id}/pdf")
def export_public_pdf(
    run_id: int,
    class_id: int | None = None,
    class_ids: str | None = None,
    db: Session = Depends(get_db),
):
    run = _published_run_or_404(run_id, db)
    ids = _resolve_class_filter(class_ids, class_id)
    rows = _rows_or_404(run_id, db, ids)
    suffix = "_filtered" if ids else ""
    grid = build_grid(rows)
    return _grid_pdf_response(grid, run, bool(ids),
                             f"timetable_{run_id}{suffix}.pdf")
```

(g) Delete the now-unused `_pdf_response` function (the flat-list PDF builder).

- [ ] **Step 5: Keep CSV byte-for-byte unchanged — pin its columns**

Because `build_grid` reads `"Course"` and does not add keys to the rows, `_get_entries_with_details` is untouched and CSV is unaffected. Add a regression test to lock the CSV header. Append to `backend/tests/test_grid_pdf.py`:

```python
def test_csv_columns_unchanged(client, auth_headers, db, admin_user):
    run = _run_with_two_classes(db, admin_user.id)
    r = client.get(f"/export/runs/{run.id}/csv", headers=auth_headers)
    assert r.status_code == 200
    header = r.text.strip().splitlines()[0]
    assert header == ("Day,Time,Course,Classes,Lecturer,Room,Capacity,"
                      "Overcapacity,Week Pattern")
```

- [ ] **Step 6: Run the new tests, then the full suite**

Run: `./venv/Scripts/python.exe -m pytest tests/test_grid_pdf.py tests/test_export_filter.py -v`
Expected: all pass.

Run: `./venv/Scripts/python.exe -m pytest -q`
Expected: all pass, no regressions.

- [ ] **Step 7: Commit**

```bash
git add backend/app/routers/export.py backend/app/assets/watermark_logo.png backend/tests/test_grid_pdf.py
git commit -m "timetable export: PDF is now a grid with course-code legend, faded system-logo watermark and identity footer"
```

---

### Task 3: `public-levels` returns each level's classes with tracks

**Files:**
- Modify: `backend/app/routers/faculty_setup.py` (`get_public_levels`)
- Test: `backend/tests/test_track_admin.py` (add one test)

**Interfaces:**
- Produces: each level node in `GET /faculty-setup/public-levels` gains `"classes": [{"id": int, "name": str, "track": str | None}]`, alongside the existing `"class_id"` and `"class_ids"`.

- [ ] **Step 1: Write the failing test**

Add to `backend/tests/test_track_admin.py`:

```python
def test_public_levels_includes_classes_with_tracks(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    lid = _level_id(client, ctx)
    sw, net = _two_track_classes(client, ctx, lid)

    levels = client.get(
        f"/faculty-setup/public-levels?department_id={ctx['dept']['id']}"
    ).json()
    node = next(l for l in levels if l["number"] == 400)
    by_track = {c["track"]: c for c in node["classes"]}
    assert by_track["Software"]["id"] == sw["id"]
    assert by_track["Networking"]["id"] == net["id"]
```

(`setup_faculty_head`, `_level_id`, and `_two_track_classes` already exist in `test_track_admin.py`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `./venv/Scripts/python.exe -m pytest tests/test_track_admin.py::test_public_levels_includes_classes_with_tracks -v`
Expected: FAIL with `KeyError: 'classes'`.

- [ ] **Step 3: Add the `classes` list**

In `backend/app/routers/faculty_setup.py`, in `get_public_levels`, extend the per-level dict:

```python
        result.append({
            "id": level.id,
            "number": level.number,
            # Kept for backward compatibility (single-class levels).
            "class_id": first_class.id if first_class else None,
            # Every class at the level, so a filtered/exported timetable
            # includes all specialization tracks, not just the first.
            "class_ids": [c.id for c in level.classes],
            # Full classes so the filter can offer a per-track choice.
            "classes": [
                {"id": c.id, "name": c.name, "track": c.track}
                for c in level.classes
            ],
        })
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./venv/Scripts/python.exe -m pytest tests/test_track_admin.py -v`
Expected: PASS (existing + the new test).

- [ ] **Step 5: Commit**

```bash
git add backend/app/routers/faculty_setup.py backend/tests/test_track_admin.py
git commit -m "public-levels: expose each level's classes with track labels for the download filter"
```

---

### Task 4: Track dropdown in the download filter bar (frontend)

**Files:**
- Modify: `frontend/lib/core/widgets/class_filter_bar.dart`

**Interfaces:**
- Consumes: `public-levels` now returns per-level `classes: [{id, name, track}]` (Task 3). The existing `onScopeSelected(List<int>? classIds)` callback and `_scope()` are unchanged in shape.

- [ ] **Step 1: Add track state and a helper**

In `class_filter_bar.dart`, add a selected-track-class field near `_selectedLevel`:

```dart
  Map<String, dynamic>? _selectedLevel;
  Map<String, dynamic>? _selectedTrackClass; // one class of the level, or null = whole level
```

Add a helper that lists a level's track-classes (only those with a non-null track):

```dart
  List<Map<String, dynamic>> _tracksOf(Map<String, dynamic>? level) {
    if (level == null) return [];
    final classes = (level['classes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return classes.where((c) => (c['track'] as String?) != null).toList();
  }
```

- [ ] **Step 2: Reset the track when the level changes**

In the Level dropdown's `onChanged`, clear the selected track:

```dart
              onChanged: _selectedDept == null
                  ? null
                  : (l) => setState(() {
                        _selectedLevel = l;
                        _selectedTrackClass = null;
                      }),
```

Also clear it in `_onDeptSelected` and `_clear` (set `_selectedTrackClass = null` alongside the existing `_selectedLevel = null`).

- [ ] **Step 3: Show the Track dropdown only when the level has tracks**

Immediately after the Level `Expanded(...)` widget (before the `View` button), insert:

```dart
          if (_tracksOf(_selectedLevel).isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<Map<String, dynamic>?>(
                value: _selectedTrackClass,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Track (all)',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                items: [
                  const DropdownMenuItem<Map<String, dynamic>?>(
                    value: null, child: Text('All tracks'),
                  ),
                  ..._tracksOf(_selectedLevel).map(
                    (c) => DropdownMenuItem<Map<String, dynamic>?>(
                      value: c, child: Text(c['track'] as String),
                    ),
                  ),
                ],
                onChanged: (c) => setState(() => _selectedTrackClass = c),
              ),
            ),
          ],
```

- [ ] **Step 4: Narrow the scope to the chosen track**

In `_scope()`, when a level is selected, prefer a chosen track class:

```dart
    if (_selectedLevel != null) {
      if (_selectedTrackClass != null) {
        return [_selectedTrackClass!['id'] as int];
      }
      return _classIdsOf(_selectedLevel!);
    }
```

(The department- and faculty-level branches are unchanged.)

- [ ] **Step 5: Verify analyze**

Run (from `frontend/`): `flutter analyze`
Expected: `37 issues found` — the existing baseline, zero new.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/core/widgets/class_filter_bar.dart
git commit -m "download filter: offer a track choice when a specialization level is selected"
```

---

## Notes for the implementer

- **Watermark faintness:** the logo is faded to 8% opacity in `_load_faded_logo`. If it reads too strong/weak in a real PDF, adjust the `0.08` factor — but that is a visual tweak, not a test change.
- **`_pageNumber` / `_pagesize`** are standard ReportLab `Canvas` attributes available inside `_StampCanvas`; no extra wiring needed.
- **Why split "Course" instead of adding Code/CourseName columns:** it keeps `_get_entries_with_details` and therefore the CSV output completely untouched (the Global Constraint), with no risk of new columns leaking into the CSV.
- The frontend dropdown is verified by `flutter analyze` plus interactive click-through by the user; there is no widget test in this suite.
