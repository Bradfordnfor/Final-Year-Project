import json
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.timetable import (
    Timetable, TimetableEntry, TimetableEntryClass,
    TimetableConflict, GenerationJob, Notification,
)
from app.models.user import User
from app.schemas.timetable import (
    TimetableCreate, TimetableResponse, TimetableEntryResponse,
    TimetableConflictResponse, ConflictResolutionRequest,
    GenerationJobResponse, ManualSlotMoveRequest, NotificationResponse,
)
from app.core.permissions import (
    get_current_user, require_university_admin,
    require_faculty_head, require_timetable_officer,
)

router = APIRouter(prefix="/timetables", tags=["Timetables"])

STATUS_FLOW = ["draft", "under_review", "approved", "published"]


@router.post("/", response_model=TimetableResponse, status_code=status.HTTP_201_CREATED)
def create_timetable(
    data: TimetableCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_timetable_officer),
):
    timetable = Timetable(**data.model_dump())
    db.add(timetable)
    db.commit()
    db.refresh(timetable)
    return timetable


@router.get("/", response_model=list[TimetableResponse])
def list_timetables(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    return db.query(Timetable).all()


@router.get("/{timetable_id}", response_model=TimetableResponse)
def get_timetable(timetable_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    tt = db.get(Timetable, timetable_id)
    if not tt:
        raise HTTPException(status_code=404, detail="Timetable not found")
    return tt


@router.get("/{timetable_id}/entries", response_model=list[TimetableEntryResponse])
def get_entries(timetable_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    entries = db.query(TimetableEntry).filter(TimetableEntry.timetable_id == timetable_id).all()
    result = []
    for entry in entries:
        class_ids = [ec.class_id for ec in entry.entry_classes]
        result.append(TimetableEntryResponse(
            id=entry.id, timetable_id=entry.timetable_id,
            course_id=entry.course_id, lecturer_id=entry.lecturer_id,
            room_id=entry.room_id, time_slot_id=entry.time_slot_id,
            group_id=entry.group_id, week_pattern=entry.week_pattern,
            rotation_sequence=entry.rotation_sequence,
            is_overcapacity=entry.is_overcapacity,
            is_merged=entry.is_merged, class_ids=class_ids,
        ))
    return result


@router.get("/{timetable_id}/conflicts", response_model=list[TimetableConflictResponse])
def get_conflicts(timetable_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    return db.query(TimetableConflict).filter(
        TimetableConflict.timetable_id == timetable_id,
        TimetableConflict.resolved == False,  # noqa: E712
    ).all()


@router.post("/{timetable_id}/advance-status", response_model=TimetableResponse)
def advance_status(
    timetable_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_timetable_officer),
):
    tt = db.get(Timetable, timetable_id)
    if not tt:
        raise HTTPException(status_code=404, detail="Timetable not found")
    current_idx = STATUS_FLOW.index(tt.status) if tt.status in STATUS_FLOW else -1
    if current_idx >= len(STATUS_FLOW) - 1:
        raise HTTPException(status_code=400, detail="Timetable is already published")
    tt.status = STATUS_FLOW[current_idx + 1]
    db.commit()
    db.refresh(tt)
    return tt


@router.post("/{timetable_id}/publish", response_model=TimetableResponse)
def publish_timetable(
    timetable_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_faculty_head),
):
    tt = db.get(Timetable, timetable_id)
    if not tt:
        raise HTTPException(status_code=404, detail="Timetable not found")
    if tt.status != "approved":
        raise HTTPException(status_code=400, detail="Timetable must be approved before publishing")
    tt.status = "published"
    db.commit()
    db.refresh(tt)
    _notify_department(tt, db)
    return tt


@router.get("/{timetable_id}/job-status", response_model=GenerationJobResponse)
def get_job_status(timetable_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    job = (
        db.query(GenerationJob)
        .filter(GenerationJob.timetable_id == timetable_id)
        .order_by(GenerationJob.id.desc())
        .first()
    )
    if not job:
        return GenerationJobResponse(status="no_job")
    return job


@router.post("/{timetable_id}/generate")
def trigger_generation(
    timetable_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    _: User = Depends(require_timetable_officer),
):
    tt = db.get(Timetable, timetable_id)
    if not tt:
        raise HTTPException(status_code=404, detail="Timetable not found")
    if tt.status != "draft":
        raise HTTPException(status_code=400, detail="Can only generate for a draft timetable")

    job = GenerationJob(timetable_id=timetable_id, status="pending")
    db.add(job)
    db.commit()
    db.refresh(job)

    background_tasks.add_task(_run_generation, timetable_id, job.id)
    return {"message": "Generation started", "job_id": job.id}


@router.post("/{timetable_id}/conflicts/{conflict_id}/resolve", response_model=TimetableConflictResponse)
def resolve_conflict(
    timetable_id: int,
    conflict_id: int,
    data: ConflictResolutionRequest,
    db: Session = Depends(get_db),
    _: User = Depends(require_faculty_head),
):
    conflict = db.query(TimetableConflict).filter(
        TimetableConflict.id == conflict_id,
        TimetableConflict.timetable_id == timetable_id,
    ).first()
    if not conflict:
        raise HTTPException(status_code=404, detail="Conflict not found")
    if data.resolution not in ("add_session", "rotate_groups"):
        raise HTTPException(status_code=400, detail="resolution must be 'add_session' or 'rotate_groups'")

    from app.solver.conflict_resolver import apply_resolution
    apply_resolution(conflict, data.resolution, db)

    conflict.resolved = True
    conflict.resolution = data.resolution
    db.commit()
    db.refresh(conflict)
    return conflict


@router.put("/{timetable_id}/entries/move", response_model=TimetableEntryResponse)
def move_entry(
    timetable_id: int,
    data: ManualSlotMoveRequest,
    db: Session = Depends(get_db),
    _: User = Depends(require_faculty_head),
):
    entry = db.query(TimetableEntry).filter(
        TimetableEntry.id == data.entry_id,
        TimetableEntry.timetable_id == timetable_id,
    ).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Entry not found")

    class_ids = [ec.class_id for ec in entry.entry_classes]

    lecturer_clash = db.query(TimetableEntry).filter(
        TimetableEntry.timetable_id == timetable_id,
        TimetableEntry.time_slot_id == data.new_time_slot_id,
        TimetableEntry.lecturer_id == entry.lecturer_id,
        TimetableEntry.id != entry.id,
    ).first()
    if lecturer_clash:
        raise HTTPException(status_code=409, detail="Lecturer already has a session in that slot")

    for class_id in class_ids:
        class_clash = (
            db.query(TimetableEntryClass)
            .join(TimetableEntry, TimetableEntry.id == TimetableEntryClass.entry_id)
            .filter(
                TimetableEntry.timetable_id == timetable_id,
                TimetableEntry.time_slot_id == data.new_time_slot_id,
                TimetableEntryClass.class_id == class_id,
                TimetableEntryClass.entry_id != entry.id,
            ).first()
        )
        if class_clash:
            raise HTTPException(status_code=409, detail=f"Class {class_id} already has a session in that slot")

    entry.time_slot_id = data.new_time_slot_id
    entry.room_id = data.new_room_id
    db.commit()
    db.refresh(entry)

    return TimetableEntryResponse(
        id=entry.id, timetable_id=entry.timetable_id, course_id=entry.course_id,
        lecturer_id=entry.lecturer_id, room_id=entry.room_id, time_slot_id=entry.time_slot_id,
        group_id=entry.group_id, week_pattern=entry.week_pattern,
        rotation_sequence=entry.rotation_sequence, is_overcapacity=entry.is_overcapacity,
        is_merged=entry.is_merged, class_ids=[ec.class_id for ec in entry.entry_classes],
    )


@router.get("/{timetable_id}/analytics")
def get_analytics(
    timetable_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_faculty_head),
):
    from collections import Counter
    entries = db.query(TimetableEntry).filter(TimetableEntry.timetable_id == timetable_id).all()
    room_usage = Counter(e.room_id for e in entries)
    lecturer_sessions = Counter(e.lecturer_id for e in entries)
    overcapacity_ids = [e.id for e in entries if e.is_overcapacity]
    return {
        "total_entries": len(entries),
        "overcapacity_count": len(overcapacity_ids),
        "overcapacity_entry_ids": overcapacity_ids,
        "room_utilization": dict(room_usage),
        "lecturer_session_counts": dict(lecturer_sessions),
    }


@router.get("/notifications/mine", response_model=list[NotificationResponse])
def get_my_notifications(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return (
        db.query(Notification)
        .filter(Notification.user_id == current_user.id)
        .order_by(Notification.created_at.desc())
        .limit(50)
        .all()
    )


@router.post("/notifications/{notification_id}/read")
def mark_notification_read(
    notification_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    notif = db.query(Notification).filter(
        Notification.id == notification_id,
        Notification.user_id == current_user.id,
    ).first()
    if not notif:
        raise HTTPException(status_code=404, detail="Notification not found")
    notif.is_read = True
    db.commit()
    return {"ok": True}


# --- Internal helpers ---

def _run_generation(timetable_id: int, job_id: int) -> None:
    from app.database import SessionLocal
    from app.solver.db_preprocessor import build_solver_input
    from app.solver.solver import solve_timetable
    from app.solver.postprocessor import save_solver_result

    db = SessionLocal()
    try:
        job = db.get(GenerationJob, job_id)
        timetable = db.get(Timetable, timetable_id)

        job.status = "running"
        job.started_at = datetime.utcnow()
        db.commit()

        solver_input, conflicts = build_solver_input(
            timetable_id=timetable_id,
            semester_id=timetable.semester_id,
            department_id=timetable.department_id,
            db=db,
        )

        for c in conflicts:
            db.add(TimetableConflict(
                timetable_id=timetable_id,
                conflict_type=c.conflict_type,
                course_id=c.course_id,
                class_id=c.class_id,
                details=json.dumps({
                    "groups_needed": c.groups_needed,
                    "sessions_available": c.sessions_available,
                    "message": c.details,
                }),
            ))
        db.commit()

        if solver_input.sessions:
            result = solve_timetable(solver_input)
            if result.status in ("optimal", "feasible"):
                save_solver_result(timetable, result, db)
                timetable.generated_at = datetime.utcnow()
                job.status = "completed"
            else:
                job.status = "failed"
                job.error_message = f"Solver returned status: {result.status}"
        else:
            job.status = "completed"
            timetable.generated_at = datetime.utcnow()

        job.completed_at = datetime.utcnow()
        db.commit()

    except Exception as exc:
        job = db.get(GenerationJob, job_id)
        if job:
            job.status = "failed"
            job.error_message = str(exc)
            job.completed_at = datetime.utcnow()
            db.commit()
    finally:
        db.close()


def _notify_department(timetable: Timetable, db: Session) -> None:
    users = db.query(User).filter(User.department_id == timetable.department_id).all()
    for user in users:
        db.add(Notification(
            user_id=user.id,
            message=f"Timetable for department {timetable.department_id} has been published.",
            notification_type="timetable_published",
        ))
    db.commit()
