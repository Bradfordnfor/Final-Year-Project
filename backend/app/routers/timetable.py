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
    SplitClassRequest, MergeClassRequest,
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


# Which run statuses each role may see in the run list. Officers and admins
# follow a run through every state; a faculty head only sees it once it is up
# for review or has been published; a lecturer likewise. Anyone else (e.g. a
# student hitting this) sees only published runs.
_ALL_STATUSES = {"draft", "under_review", "approved", "published"}
_VISIBLE_STATUSES = {
    "super_admin": _ALL_STATUSES,
    "university_admin": _ALL_STATUSES,
    "timetable_officer": _ALL_STATUSES,
    "faculty_head": {"under_review", "published"},
    "lecturer": {"under_review", "published"},
}


@router.get("/runs/", response_model=list[RunResponse])
def list_runs(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    query = db.query(TimetableRun)

    # Restrict to the statuses this role is allowed to see.
    allowed = _VISIBLE_STATUSES.get(current_user.role, {"published"})
    query = query.filter(TimetableRun.status.in_(allowed))

    # A faculty head only sees runs that include their own faculty.
    if current_user.role == "faculty_head" and current_user.faculty_id:
        run_ids = [
            rf.run_id for rf in
            db.query(TimetableRunFaculty).filter(
                TimetableRunFaculty.faculty_id == current_user.faculty_id
            ).all()
        ]
        query = query.filter(TimetableRun.id.in_(run_ids))

    runs = query.all()
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


@router.get("/runs/{run_id}/readiness")
def get_run_readiness(run_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    """Checklist of what must be in place before this run can generate."""
    from app.solver.readiness import check_run_readiness, is_ready
    run = db.get(TimetableRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Timetable run not found")
    items = check_run_readiness(run, db)
    return {
        "ready": is_ready(items),
        "checks": [
            {"key": i.key, "label": i.label, "ok": i.ok, "detail": i.detail}
            for i in items
        ],
    }


@router.post("/runs/{run_id}/generate")
def trigger_generation(
    run_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    _: User = Depends(require_timetable_officer),
):
    from app.solver.readiness import check_run_readiness, is_ready
    run = db.get(TimetableRun, run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Timetable run not found")
    if run.status != "draft":
        raise HTTPException(status_code=400, detail="Can only generate for a draft run")

    items = check_run_readiness(run, db)
    if not is_ready(items):
        failures = [i.detail or i.label for i in items if not i.ok]
        raise HTTPException(
            status_code=400,
            detail="Timetable is not ready to generate. " + " ".join(failures),
        )

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
    _: User = Depends(require_timetable_officer),
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
    _: User = Depends(require_timetable_officer),
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


def _entry_population(entry, db) -> int:
    from app.models.academic import Class
    total = 0
    for ec in entry.entry_classes:
        cls = db.get(Class, ec.class_id)
        if cls:
            total += cls.population or 0
    return total


def _recompute_flags(entry, db) -> None:
    """Refresh an entry's merged / over-capacity flags after its classes change."""
    from app.models.room import Room
    n_classes = len(entry.entry_classes)
    entry.is_merged = n_classes > 1
    if entry.room_id is None:
        entry.is_overcapacity = False
        return
    room = db.get(Room, entry.room_id)
    entry.is_overcapacity = bool(room and _entry_population(entry, db) > room.capacity)


def _run_overflow_threshold(run_id, db) -> float:
    run = db.get(TimetableRun, run_id)
    fac = run.faculties[0].faculty if run and run.faculties else None
    if fac and fac.university:
        return fac.university.overflow_threshold
    return 0.20


@router.post("/runs/{run_id}/entries/{entry_id}/split-class",
             status_code=status.HTTP_200_OK)
def split_class(
    run_id: int,
    entry_id: int,
    data: SplitClassRequest,
    db: Session = Depends(get_db),
    _: User = Depends(require_timetable_officer),
):
    """Peel one class out of a merged session into its own new session at a
    chosen period and room. Used to relieve an over-capacity merged session."""
    from app.models.room import Room

    entry = db.query(TimetableEntry).filter(
        TimetableEntry.id == entry_id, TimetableEntry.run_id == run_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Entry not found")
    class_ids = [ec.class_id for ec in entry.entry_classes]
    if data.class_id not in class_ids:
        raise HTTPException(status_code=400, detail="That class is not in this session")
    if len(class_ids) < 2:
        raise HTTPException(status_code=400, detail="Nothing to split — the session has only this class")

    slot = data.new_time_slot_id
    # No room clash at the target period.
    if db.query(TimetableEntry).filter(
            TimetableEntry.run_id == run_id, TimetableEntry.time_slot_id == slot,
            TimetableEntry.room_id == data.new_room_id).first():
        raise HTTPException(status_code=409, detail="That room is already used in that period")
    # The lecturer must be free at the target period.
    if db.query(TimetableEntry).filter(
            TimetableEntry.run_id == run_id, TimetableEntry.time_slot_id == slot,
            TimetableEntry.lecturer_id == entry.lecturer_id).first():
        raise HTTPException(status_code=409, detail="The lecturer already has a session in that period")
    # The class must be free at the target period.
    if (db.query(TimetableEntryClass)
            .join(TimetableEntry, TimetableEntry.id == TimetableEntryClass.entry_id)
            .filter(TimetableEntry.run_id == run_id,
                    TimetableEntry.time_slot_id == slot,
                    TimetableEntryClass.class_id == data.class_id).first()):
        raise HTTPException(status_code=409, detail="That class already has a session in that period")

    # Remove the class from the merged session.
    db.query(TimetableEntryClass).filter(
        TimetableEntryClass.entry_id == entry.id,
        TimetableEntryClass.class_id == data.class_id).delete()

    # Create its own session.
    new_entry = TimetableEntry(
        run_id=run_id, course_id=entry.course_id, lecturer_id=entry.lecturer_id,
        room_id=data.new_room_id, time_slot_id=slot,
        group_id=entry.group_id, week_pattern="every_week",
    )
    db.add(new_entry)
    db.flush()
    db.add(TimetableEntryClass(entry_id=new_entry.id, class_id=data.class_id))
    db.flush()

    db.refresh(entry)
    _recompute_flags(entry, db)
    _recompute_flags(new_entry, db)
    db.commit()
    return {"ok": True, "new_entry_id": new_entry.id}


@router.post("/runs/{run_id}/entries/{entry_id}/merge-class",
             status_code=status.HTTP_200_OK)
def merge_class(
    run_id: int,
    entry_id: int,
    data: MergeClassRequest,
    db: Session = Depends(get_db),
    _: User = Depends(require_timetable_officer),
):
    """Fold a class out of one session into another session of the SAME course,
    so the two classes attend together — if the combined population fits the
    target room within the university's overflow allowance."""
    from app.models.room import Room

    source = db.query(TimetableEntry).filter(
        TimetableEntry.id == entry_id, TimetableEntry.run_id == run_id).first()
    target = db.query(TimetableEntry).filter(
        TimetableEntry.id == data.target_entry_id, TimetableEntry.run_id == run_id).first()
    if not source or not target:
        raise HTTPException(status_code=404, detail="Entry not found")
    if source.id == target.id:
        raise HTTPException(status_code=400, detail="Source and target are the same session")
    if source.course_id != target.course_id:
        raise HTTPException(status_code=400, detail="Both sessions must be of the same course")
    if data.class_id not in [ec.class_id for ec in source.entry_classes]:
        raise HTTPException(status_code=400, detail="That class is not in the source session")
    if data.class_id in [ec.class_id for ec in target.entry_classes]:
        raise HTTPException(status_code=400, detail="That class is already in the target session")

    # The class must be free at the target's period.
    if (db.query(TimetableEntryClass)
            .join(TimetableEntry, TimetableEntry.id == TimetableEntryClass.entry_id)
            .filter(TimetableEntry.run_id == run_id,
                    TimetableEntry.time_slot_id == target.time_slot_id,
                    TimetableEntryClass.class_id == data.class_id,
                    TimetableEntryClass.entry_id != target.id).first()):
        raise HTTPException(status_code=409, detail="That class already has a session in the target period")

    # Capacity: combined must fit the target room within the overflow allowance.
    from app.models.academic import Class
    moving = db.get(Class, data.class_id)
    combined = _entry_population(target, db) + (moving.population if moving else 0)
    if target.room_id is not None:
        room = db.get(Room, target.room_id)
        if room and combined > room.capacity * (1 + _run_overflow_threshold(run_id, db)):
            raise HTTPException(
                status_code=409,
                detail=f"Won't fit: {combined} students exceed {room.name} "
                       f"({room.capacity} seats plus the overflow allowance)",
            )

    # Move the class from source to target.
    db.query(TimetableEntryClass).filter(
        TimetableEntryClass.entry_id == source.id,
        TimetableEntryClass.class_id == data.class_id).delete()
    db.add(TimetableEntryClass(entry_id=target.id, class_id=data.class_id))
    db.flush()

    db.refresh(source)
    db.refresh(target)
    if not source.entry_classes:          # source emptied — remove it
        db.delete(source)
    else:
        _recompute_flags(source, db)
    _recompute_flags(target, db)
    db.commit()
    return {"ok": True}


@router.get("/runs/{run_id}/analytics")
def get_analytics(
    run_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    from collections import Counter
    from app.models.user import Lecturer
    from app.models.course import Course
    from app.models.university import Department

    entries = db.query(TimetableEntry).filter(TimetableEntry.run_id == run_id).all()

    # Scope: a university admin (or super admin) sees the whole run — every
    # faculty. A faculty head sees only their own faculty's sessions.
    if current_user.role == "faculty_head" and current_user.faculty_id:
        dept_ids = [
            row[0] for row in
            db.query(Department.id)
            .filter(Department.faculty_id == current_user.faculty_id).all()
        ]
        faculty_course_ids = {
            row[0] for row in
            db.query(Course.id).filter(Course.department_id.in_(dept_ids)).all()
        } if dept_ids else set()
        entries = [e for e in entries if e.course_id in faculty_course_ids]

    room_usage = Counter(e.room_id for e in entries if e.room_id is not None)
    lecturer_sessions = Counter(e.lecturer_id for e in entries)
    overcapacity_ids = [e.id for e in entries if e.is_overcapacity]

    # Per-lecturer breakdown: total periods and the courses they teach (with the
    # number of periods per course). Drives the click-through detail dialog.
    detail: dict[int, dict] = {}
    for e in entries:
        d = detail.setdefault(e.lecturer_id, {"sessions": 0, "courses": {}})
        d["sessions"] += 1
        d["courses"][e.course_id] = d["courses"].get(e.course_id, 0) + 1

    lecturers = []
    for lid, d in detail.items():
        lect = db.get(Lecturer, lid)
        name = lect.user.full_name if lect and lect.user else f"Lecturer #{lid}"
        courses = []
        for cid, periods in d["courses"].items():
            c = db.get(Course, cid)
            courses.append({
                "code": c.code if c else "?",
                "name": c.name if c else "",
                "periods": periods,
            })
        courses.sort(key=lambda x: x["code"])
        lecturers.append({
            "lecturer_id": lid,
            "name": name,
            "total_periods": d["sessions"],
            "courses": courses,
        })
    lecturers.sort(key=lambda x: x["total_periods"], reverse=True)

    return {
        "total_entries": len(entries),
        "overcapacity_count": len(overcapacity_ids),
        "overcapacity_entry_ids": overcapacity_ids,
        "room_utilization": dict(room_usage),
        "lecturer_session_counts": dict(lecturer_sessions),
        "lecturers": lecturers,
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

def clear_run_result(run_id: int, db: Session) -> None:
    """Remove a run's generated entries (and their class links) and conflicts.

    Used before regenerating so a new timetable replaces the old one instead of
    stacking on top. Link rows are deleted before entries to respect the foreign
    key, since a bulk delete does not trigger the ORM cascade.
    """
    entry_ids = [
        e.id for e in
        db.query(TimetableEntry.id).filter(TimetableEntry.run_id == run_id).all()
    ]
    if entry_ids:
        db.query(TimetableEntryClass).filter(
            TimetableEntryClass.entry_id.in_(entry_ids)
        ).delete(synchronize_session=False)
        db.query(TimetableEntry).filter(
            TimetableEntry.run_id == run_id
        ).delete(synchronize_session=False)
    db.query(TimetableConflict).filter(
        TimetableConflict.run_id == run_id
    ).delete(synchronize_session=False)
    db.commit()


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

        # A draft run can be generated more than once. Clear the previous
        # result first so we REPLACE it rather than stacking a second timetable
        # on top — stacking is what produced duplicate sessions and same-class
        # clashes.
        clear_run_result(run_id, db)

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
            job.status = "failed"
            job.error_message = (
                "No sessions to schedule. Check that courses have lecturers "
                "assigned and that the selected faculties have courses."
            )

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
