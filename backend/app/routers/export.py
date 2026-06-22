import csv
import io
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph
from reportlab.lib.styles import getSampleStyleSheet
from app.database import get_db
from app.models.timetable import TimetableRun, TimetableEntry
from app.models.academic import TimeSlot, Class
from app.models.course import Course
from app.models.room import Room
from app.models.user import Lecturer, User as UserModel
from app.core.permissions import get_current_user

router = APIRouter(prefix="/export", tags=["Export"])


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


def _pdf_response(rows: list[dict], title: str, filename: str) -> StreamingResponse:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=landscape(A4))
    styles = getSampleStyleSheet()

    headers = list(rows[0].keys())
    table_data = [headers] + [[r[h] for h in headers] for r in rows]

    table = Table(table_data, repeatRows=1)
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1a237e")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f5f5f5")]),
        ("BACKGROUND", (7, 1), (7, -1), colors.HexColor("#fff3e0")),
    ]))

    doc.build([Paragraph(title, styles["Title"]), table])
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
    return _pdf_response(rows, f"Timetable Run — {run.name}",
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
    return _pdf_response(rows, f"Timetable — {run.name}",
                         f"timetable_{run_id}{suffix}.pdf")
