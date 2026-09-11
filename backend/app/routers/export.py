import csv
import functools
import io
import os
from xml.sax.saxutils import escape
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from PIL import Image
from app.database import get_db
from app.models.timetable import TimetableRun, TimetableEntry
from app.models.academic import TimeSlot, Class
from app.models.course import Course
from app.models.room import Room
from app.models.user import Lecturer, User as UserModel
from app.core.permissions import get_current_user

router = APIRouter(prefix="/export", tags=["Export"])


WEEKDAY_ORDER = ["Monday", "Tuesday", "Wednesday", "Thursday",
                 "Friday", "Saturday", "Sunday"]


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
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        buf.seek(0)
        result = ImageReader(buf)
    _FADED_LOGO_CACHE[path] = result
    return result


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


def _resolve_class_filter(class_ids: str | None,
                          class_id: int | None) -> set[int] | None:
    """Build the set of class IDs to filter by from the request params.

    `class_ids` is a comma-separated list (faculty/department/level scope);
    `class_id` is the legacy single-class param. Returns None for no filter.
    """
    if class_ids:
        parsed = {int(x) for x in class_ids.split(",") if x.strip().isdigit()}
        return parsed or None
    if class_id is not None:
        return {class_id}
    return None


def _get_entries_with_details(run_id: int, db: Session,
                              class_ids: set[int] | None = None) -> list[dict]:
    entries = db.query(TimetableEntry).filter(TimetableEntry.run_id == run_id).all()
    rows = []
    for entry in entries:
        # When a class filter is given, keep only sessions attended by at least
        # one of those classes (a single class, a department, or a faculty).
        if class_ids is not None and not (
            {ec.class_id for ec in entry.entry_classes} & class_ids
        ):
            continue
        timeslot = db.get(TimeSlot, entry.time_slot_id)
        course = db.get(Course, entry.course_id)
        room = db.get(Room, entry.room_id)
        lecturer = db.get(Lecturer, entry.lecturer_id)
        lecturer_name = lecturer.user.full_name if lecturer and lecturer.user else "N/A"
        class_names = []
        for ec in entry.entry_classes:
            cls = db.get(Class, ec.class_id)
            if cls:
                class_names.append(cls.name)
        rows.append({
            "Day": timeslot.day_of_week if timeslot else "",
            "Time": f"{timeslot.start_time}-{timeslot.end_time}" if timeslot else "",
            "Course": f"{course.code} — {course.name}" if course else "",
            "Classes": ", ".join(class_names),
            "Lecturer": lecturer_name,
            "Room": room.name if room else "Outdoor / off-site",
            "Capacity": str(room.capacity) if room else "",
            "Overcapacity": "YES" if entry.is_overcapacity else "No",
            "Week Pattern": entry.week_pattern,
        })
    return sorted(rows, key=lambda r: (r["Day"], r["Time"]))


def _csv_response(rows: list[dict], filename: str) -> StreamingResponse:
    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)
    output.seek(0)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )


def _run_identity(run) -> str:
    """University · faculty codes for the run's footer (minimal, no departments).

    A run is normally scoped to one university, but collect distinct university
    names (order-preserving) so a cross-university run lists all of them rather
    than silently showing only the last faculty's institution."""
    uni_names: list[str] = []
    fac_labels = []
    for rf in run.faculties:
        fac = rf.faculty
        if not fac:
            continue
        fac_labels.append(fac.code or fac.name)
        if fac.university and fac.university.name not in uni_names:
            uni_names.append(fac.university.name)
    parts = [p for p in [*uni_names, *fac_labels] if p]
    return " · ".join(parts)


class _StampCanvas(canvas.Canvas):
    """Draws the faded logo watermark (centered) and a footer line
    (identity left, 'Page X of Y' right) on every page. Page total is known
    only at save time, so pages are buffered.

    `identity` is an instance attribute (injected per request via the
    canvasmaker), never a class attribute — the endpoints are sync ``def`` and
    thus run concurrently in a threadpool, so shared class state would let two
    overlapping exports show each other's university in the footer."""

    def __init__(self, *args, identity="", **kwargs):
        super().__init__(*args, **kwargs)
        self._saved = []
        self.identity = identity

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


def _pdf_title(run_name: str, filtered: bool) -> str:
    """The grid PDF title, XML-escaped so names with & < > render literally
    (e.g. "Electrical & Electronic Engineering") instead of being mangled or
    silently dropped by ReportLab's Paragraph parser."""
    title = f"Timetable — {escape(run_name)}"
    if filtered:
        title += " (filtered)"
    return title


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

    title = _pdf_title(run.name, filtered)
    story = [Paragraph(title, styles["Title"]), Spacer(1, 6), table, Spacer(1, 12)]

    if grid["legend"]:
        story.append(Paragraph("<b>Course codes</b>", legend_style))
        legend_lines = "<br/>".join(
            f"{escape(code)} — {escape(name)}" for code, name in grid["legend"]
        )
        story.append(Paragraph(legend_lines, legend_style))

    stamp = functools.partial(_StampCanvas, identity=_run_identity(run))
    doc.build(story, canvasmaker=stamp)
    buffer.seek(0)
    return StreamingResponse(
        buffer,
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )


def _rows_or_404(run_id: int, db: Session, ids: set[int] | None) -> list[dict]:
    rows = _get_entries_with_details(run_id, db, ids)
    if not rows:
        raise HTTPException(status_code=404, detail="No entries to export")
    return rows


@router.get("/runs/{run_id}/csv")
def export_csv(
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
    return _csv_response(rows, f"timetable_run_{run_id}{suffix}.csv")


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


# ── Public exports (no auth; published runs only — for students) ──────────────

def _published_run_or_404(run_id: int, db: Session) -> TimetableRun:
    run = db.get(TimetableRun, run_id)
    if not run or run.status != "published":
        raise HTTPException(status_code=404, detail="Published timetable not found")
    return run


@router.get("/public/runs/{run_id}/csv")
def export_public_csv(
    run_id: int,
    class_id: int | None = None,
    class_ids: str | None = None,
    db: Session = Depends(get_db),
):
    _published_run_or_404(run_id, db)
    ids = _resolve_class_filter(class_ids, class_id)
    rows = _rows_or_404(run_id, db, ids)
    suffix = "_filtered" if ids else ""
    return _csv_response(rows, f"timetable_{run_id}{suffix}.csv")


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
