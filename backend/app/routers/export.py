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
from app.models.timetable import Timetable, TimetableEntry
from app.models.academic import TimeSlot, Class
from app.models.course import Course
from app.models.room import Room
from app.models.user import Lecturer, User as UserModel
from app.core.permissions import get_current_user

router = APIRouter(prefix="/export", tags=["Export"])


def _get_entries_with_details(timetable_id: int, db: Session) -> list[dict]:
    entries = db.query(TimetableEntry).filter(TimetableEntry.timetable_id == timetable_id).all()
    rows = []
    for entry in entries:
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
            "Room": room.name if room else "",
            "Capacity": str(room.capacity) if room else "",
            "Overcapacity": "YES" if entry.is_overcapacity else "No",
            "Week Pattern": entry.week_pattern,
        })
    return sorted(rows, key=lambda r: (r["Day"], r["Time"]))


@router.get("/timetables/{timetable_id}/csv")
def export_csv(
    timetable_id: int,
    db: Session = Depends(get_db),
    _: UserModel = Depends(get_current_user),
):
    tt = db.get(Timetable, timetable_id)
    if not tt:
        raise HTTPException(status_code=404, detail="Timetable not found")

    rows = _get_entries_with_details(timetable_id, db)
    if not rows:
        raise HTTPException(status_code=404, detail="No entries to export")

    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)
    output.seek(0)

    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename=timetable_{timetable_id}.csv"},
    )


@router.get("/timetables/{timetable_id}/pdf")
def export_pdf(
    timetable_id: int,
    db: Session = Depends(get_db),
    _: UserModel = Depends(get_current_user),
):
    tt = db.get(Timetable, timetable_id)
    if not tt:
        raise HTTPException(status_code=404, detail="Timetable not found")

    rows = _get_entries_with_details(timetable_id, db)
    if not rows:
        raise HTTPException(status_code=404, detail="No entries to export")

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

    doc.build([
        Paragraph(f"Timetable #{timetable_id}", styles["Title"]),
        table,
    ])
    buffer.seek(0)

    return StreamingResponse(
        buffer,
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=timetable_{timetable_id}.pdf"},
    )
