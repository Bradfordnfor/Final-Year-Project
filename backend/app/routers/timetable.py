import json
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.timetable import (
    TimetableRun, TimetableRunFaculty, TimetableRunBuilding,
    TimetableEntry, TimetableEntryClass,
    TimetableConflict, GenerationJob, Notification,
)
from app.models.user import User
from app.schemas.timetable import (
    RunCreate, RunResponse, TimetableEntryResponse,
    TimetableConflictResponse, ConflictResolutionRequest,
    GenerationJobResponse, ManualSlotMoveRequest, NotificationResponse,
)
from app.core.permissions import (
    get_current_user, require_university_admin,
    require_faculty_head, require_timetable_officer,
)

router = APIRouter(tags=["Timetable Runs"])

STATUS_FLOW = ["draft", "under_review", "approved", "published"]


def _run_to_response(run: TimetableRun) -> RunResponse:
    return RunResponse(
        id=run.id,
        name=run.name,
        status=run.status,
        semester_id=run.semester_id,
        created_by=run.created_by,
        generated_at=run.generated_at,
        created_at=run.created_at,
        faculty_ids=[rf.faculty_id for rf in run.faculties],
        building_ids=[rb.building_id for rb in run.buildings],
    )


@router.post("/runs/", response_model=RunResponse, status_code=status.HTTP_201_CREATED)
def create_run(
    data: RunCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_timetable_officer),
):
    run = TimetableRun(
        name=data.name,
        semester_id=data.semester_id,
        created_by=current_user.id,
    )
    db.add(run)
    db.flush()

    for fid in data.faculty_ids:
        db.add(TimetableRunFaculty(run_id=run.id, faculty_id=fid))
    for bid in data.building_ids:
        db.add(TimetableRunBuilding(run_id=run.id, building_id=bid))

    db.commit()
    db.refresh(run)
    return _run_to_response(run)


@router.get("/runs/", response_model=list[RunResponse])
def list_runs(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    runs = db.query(TimetableRun).all()
    return [_run_to_response(r) for r in runs]


@router.get("/runs/public", response_model=list[RunResponse])
def list_published_runs(db: Session = Depends(get_db)):
    runs = db.query(TimetableRun).filter(TimetableRun.status == "published").all()
    return [_run_to_response(r) for r in runs]


@router.get("/runs/{run_id}", response_model=RunResponse)
def get_run(run_id: int, db: Session = Depends(get_db)):
    run = db.get(TimetableRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Timetable run not found")
    return _run_to_response(run)


@router.delete("/runs/{run_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_run(
    run_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_timetable_officer),
):
    run = db.get(TimetableRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Timetable run not found")
    db.delete(run)
    db.commit()


@router.get("/runs/{run_id}/entries", response_model=list[TimetableEntryResponse])
def get_entries(run_id: int, db: Session = Depends(get_db)):
    entries = db.query(TimetableEntry).filter(TimetableEntry.run_id == run_id).all()
    result = []
    for entry in entries:
        class_ids = [ec.class_id for ec in entry.entry_classes]
        result.append(TimetableEntryResponse(
            id=entry.id, run_id=entry.run_id,
            course_id=entry.course_id, lecturer_id=entry.lecturer_id,
            room_id=entry.room_id, time_slot_id=entry.time_slot_id,
            group_id=entry.group_id, week_pattern=entry.week_pattern,
            rotation_sequence=entry.rotation_sequence,
            is_overcapacity=entry.is_overcapacity,
            is_merged=entry.is_merged, class_ids=class_ids,
        ))
    return result


@router.get("/runs/{run_id}/conflicts", response_model=list[TimetableConflictResponse])
def get_conflicts(run_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    return db.query(TimetableConflict).filter(
        TimetableConflict.run_id == run_id,
        TimetableConflict.resolved == False,  # noqa: E712
    ).all()


@router.post("/runs/{run_id}/advance-status", response_model=RunResponse)
def advance_status(
    run_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_timetable_officer),
):
    run = db.get(TimetableRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Timetable run not found")
    current_idx = STATUS_FLOW.index(run.status) if run.status in STATUS_FLOW else -1
    if current_idx >= len(STATUS_FLOW) - 1:
        raise HTTPException(status_code=400, detail="Timetable run is already published")
    run.status = STATUS_FLOW[current_idx + 1]
    db.commit()
    db.refresh(run)
    return _run_to_response(run)


@router.post("/runs/{run_id}/publish", response_model=RunResponse)
def publish_run(
    run_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    run = db.get(TimetableRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Timetable run not found")
    if run.status != "approved":
        raise HTTPException(status_code=400, detail="Timetable must be approved before publishing")
    run.status = "published"
    db.commit()
    db.refresh(run)
    _notify_run_published(run, db)
    return _run_to_response(run)


@router.get("/runs/{run_id}/job-status", response_model=GenerationJobResponse)
def get_job_status(run_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    job = (
        db.query(GenerationJob)
        .filter(GenerationJob.run_id == run_id)
        .order_by(GenerationJob.id.desc())
        .first()
    )
    if not job:
        return GenerationJobResponse(status="no_job")
    return job


@router.post("/runs/{run_id}/generate")
def trigger_generation(
    run_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    _: User = Depends(require_timetable_officer),
):
    run = db.get(TimetableRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Timetable run not found")
    if run.status != "draft":
        raise HTTPException(status_code=400, detail="Can only generate for a draft run")

    job = GenerationJob(run_id=run_id, status="pending")
    db.add(job)
    db.commit()
    db.refresh(job)

    background_tasks.add_task(_run_generation, run_id, job.id)
    return {"message": "Generation started", "job_id": job.id}


@router.post("/runs/{run_id}/conflicts/{conflict_id}/resolve", response_model=TimetableConflictResponse)
def resolve_conflict(
    run_id: int,
    conflict_id: int,
    data: ConflictResolutionRequest,
    db: Session = Depends(get_db),
    _: User = Depends(require_faculty_head),
):
    conflict = db.query(TimetableConflict).filter(
        TimetableConflict.id == conflict_id,
        TimetableConflict.run_id == run_id,
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


@router.put("/runs/{run_id}/entries/move", response_model=TimetableEntryResponse)
def move_entry(
    run_id: int,
    data: ManualSlotMoveRequest,
    db: Session = Depends(get_db),
    _: User = Depends(require_faculty_head),
):
    entry = db.query(TimetableEntry).filter(
        TimetableEntry.id == data.entry_id,
        TimetableEntry.run_id == run_id,
    ).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Entry not found")

    class_ids = [ec.class_id for ec in entry.entry_classes]

    lecturer_clash = db.query(TimetableEntry).filter(
        TimetableEntry.run_id == run_id,
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
                TimetableEntry.run_id == run_id,
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
        id=entry.id, run_id=entry.run_id, course_id=entry.course_id,
        lecturer_id=entry.lecturer_id, room_id=entry.room_id, time_slot_id=entry.time_slot_id,
        group_id=entry.group_id, week_pattern=entry.week_pattern,
        rotation_sequence=entry.rotation_sequence, is_overcapacity=entry.is_overcapacity,
        is_merged=entry.is_merged, class_ids=[ec.class_id for ec in entry.entry_classes],
    )


@router.get("/runs/{run_id}/analytics")
def get_analytics(
    run_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_faculty_head),
):
    from collections import Counter
    entries = db.query(TimetableEntry).filter(TimetableEntry.run_id == run_id).all()
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

def _run_generation(run_id: int, job_id: int) -> None:
    from app.database import SessionLocal
    from app.solver.db_preprocessor import build_solver_input
    from app.solver.solver import solve_timetable
    from app.solver.postprocessor import save_solver_result

    db = SessionLocal()
    try:
        job = db.get(GenerationJob, job_id)
        run = db.get(TimetableRun, run_id)

        job.status = "running"
        job.started_at = datetime.utcnow()
        db.commit()

        faculty_ids = [rf.faculty_id for rf in run.faculties]
        building_ids = [rb.building_id for rb in run.buildings]

        solver_input, conflicts = build_solver_input(
            run_id=run_id,
            semester_id=run.semester_id,
            faculty_ids=faculty_ids,
            building_ids=building_ids,
            db=db,
        )

        for c in conflicts:
            db.add(TimetableConflict(
                run_id=run_id,
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
                save_solver_result(run, result, db)
                run.generated_at = datetime.utcnow()
                job.status = "completed"
            else:
                job.status = "failed"
                job.error_message = f"Solver returned status: {result.status}"
        else:
            job.status = "completed"
            run.generated_at = datetime.utcnow()

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


def _notify_run_published(run: TimetableRun, db: Session) -> None:
    from app.models.university import Faculty, Department
    from app.models.academic import Level, Class
    from sqlalchemy import select

    faculty_ids = [rf.faculty_id for rf in run.faculties]
    dept_ids = [
        d.id for d in db.query(Department).filter(Department.faculty_id.in_(faculty_ids)).all()
    ]
    users = db.query(User).filter(User.faculty_id.in_(faculty_ids)).all()
    for user in users:
        db.add(Notification(
            user_id=user.id,
            message=f"Timetable run '{run.name}' has been published.",
            notification_type="timetable_published",
        ))
    db.commit()
