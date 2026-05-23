import json
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.timetable import (
    TimetableRun, TimetableRunFaculty, TimetableRunBuilding,
    TimetableEntry, TimetableEntryClass,
    TimetableConflict, GenerationJob, Notification,
    FacultyHeadApproval,
)
from app.models.user import User
from app.schemas.timetable import (
    RunCreate, RunResponse, TimetableEntryResponse,
    TimetableConflictResponse, ConflictResolutionRequest,
    GenerationJobResponse, ManualSlotMoveRequest, NotificationResponse,
    FacultyApprovalOut, RejectRequest,
)
from app.core.permissions import (
    get_current_user,
    require_faculty_head, require_timetable_officer,
)

router = APIRouter(tags=["Timetable Runs"])


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


# ── Status transitions ────────────────────────────────────────────────────────

@router.post("/runs/{run_id}/submit-for-review", response_model=RunResponse)
def submit_for_review(
    run_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_timetable_officer),
):
    """Timetable officer submits a draft run for faculty-head review."""
    run = db.get(TimetableRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Timetable run not found")
    if run.status != "draft":
        raise HTTPException(status_code=400, detail="Only draft runs can be submitted for review")

    # Ensure every faculty in the run has a faculty head
    for run_faculty in run.faculties:
        head = db.query(User).filter(
            User.role == "faculty_head",
            User.faculty_id == run_faculty.faculty_id,
            User.is_active == True,  # noqa: E712
        ).first()
        if not head:
            raise HTTPException(
                status_code=400,
                detail=f"Faculty {run_faculty.faculty_id} has no active faculty head. Assign one before submitting for review.",
            )

    # Create or reset approval records
    for run_faculty in run.faculties:
        head = db.query(User).filter(
            User.role == "faculty_head",
            User.faculty_id == run_faculty.faculty_id,
            User.is_active == True,  # noqa: E712
        ).first()
        existing = db.query(FacultyHeadApproval).filter(
            FacultyHeadApproval.run_id == run_id,
            FacultyHeadApproval.faculty_id == run_faculty.faculty_id,
        ).first()
        if existing:
            existing.status = "pending"
            existing.comment = None
            existing.decided_at = None
            existing.faculty_head_id = head.id
        else:
            db.add(FacultyHeadApproval(
                run_id=run_id,
                faculty_id=run_faculty.faculty_id,
                faculty_head_id=head.id,
                status="pending",
            ))

        db.add(Notification(
            user_id=head.id,
            message=f"Timetable run '{run.name}' has been submitted for your review.",
            notification_type="timetable_review",
        ))

    run.status = "under_review"
    db.commit()
    db.refresh(run)
    return _run_to_response(run)


@router.get("/runs/{run_id}/approvals", response_model=list[FacultyApprovalOut])
def get_approvals(
    run_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    run = db.get(TimetableRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Timetable run not found")
    return db.query(FacultyHeadApproval).filter(
        FacultyHeadApproval.run_id == run_id
    ).all()


@router.post("/runs/{run_id}/approvals/{approval_id}/approve", response_model=FacultyApprovalOut)
def approve_run(
    run_id: int,
    approval_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    """Faculty head approves their faculty's section."""
    approval = db.query(FacultyHeadApproval).filter(
        FacultyHeadApproval.id == approval_id,
        FacultyHeadApproval.run_id == run_id,
    ).first()
    if not approval:
        raise HTTPException(status_code=404, detail="Approval record not found")
    if approval.faculty_head_id != current_user.id:
        raise HTTPException(status_code=403, detail="You can only approve your own faculty's section")
    if approval.status != "pending":
        raise HTTPException(status_code=400, detail="This approval has already been decided")

    run = db.get(TimetableRun, run_id)
    if not run or run.status != "under_review":
        raise HTTPException(status_code=400, detail="Run is not under review")

    approval.status = "approved"
    approval.decided_at = datetime.utcnow()
    db.commit()

    # If every approval is now approved, auto-advance run to approved
    all_approvals = db.query(FacultyHeadApproval).filter(
        FacultyHeadApproval.run_id == run_id
    ).all()
    if all(a.status == "approved" for a in all_approvals):
        run.status = "approved"
        creator = db.get(User, run.created_by)
        if creator:
            db.add(Notification(
                user_id=creator.id,
                message=f"All faculty heads have approved '{run.name}'. You can now publish it.",
                notification_type="timetable_approved",
            ))
        db.commit()

    db.refresh(approval)
    return approval


@router.post("/runs/{run_id}/approvals/{approval_id}/reject")
def reject_run(
    run_id: int,
    approval_id: int,
    data: RejectRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    """Faculty head rejects their faculty's section; run goes back to draft."""
    approval = db.query(FacultyHeadApproval).filter(
        FacultyHeadApproval.id == approval_id,
        FacultyHeadApproval.run_id == run_id,
    ).first()
    if not approval:
        raise HTTPException(status_code=404, detail="Approval record not found")
    if approval.faculty_head_id != current_user.id:
        raise HTTPException(status_code=403, detail="You can only reject your own faculty's section")
    if approval.status != "pending":
        raise HTTPException(status_code=400, detail="This approval has already been decided")

    run = db.get(TimetableRun, run_id)
    if not run or run.status != "under_review":
        raise HTTPException(status_code=400, detail="Run is not under review")

    approval.status = "rejected"
    approval.comment = data.comment
    approval.decided_at = datetime.utcnow()
    run.status = "draft"  # back to draft so timetable officer can fix and resubmit
    db.commit()

    creator = db.get(User, run.created_by)
    if creator:
        db.add(Notification(
            user_id=creator.id,
            message=f"Timetable run '{run.name}' was rejected: {data.comment}",
            notification_type="timetable_rejected",
        ))
    db.commit()
    return {"ok": True}


@router.post("/runs/{run_id}/publish", response_model=RunResponse)
def publish_run(
    run_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_timetable_officer),
):
    """Timetable officer publishes an approved run."""
    run = db.get(TimetableRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Timetable run not found")
    if run.status != "approved":
        raise HTTPException(
            status_code=400,
            detail="All faculty heads must approve the timetable before it can be published",
        )
    run.status = "published"
    db.commit()
    db.refresh(run)
    _notify_run_published(run, db)
    return _run_to_response(run)


# ── Generation ────────────────────────────────────────────────────────────────

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


# ── Conflicts / manual edits ─────────────────────────────────────────────────

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


# ── Internal helpers ─────────────────────────────────────────────────────────

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
    from app.models.university import Department
    faculty_ids = [rf.faculty_id for rf in run.faculties]
    users = db.query(User).filter(User.faculty_id.in_(faculty_ids)).all()
    for user in users:
        db.add(Notification(
            user_id=user.id,
            message=f"Timetable run '{run.name}' has been published.",
            notification_type="timetable_published",
        ))
    db.commit()
