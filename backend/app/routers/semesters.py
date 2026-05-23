from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.academic import Semester, TimeSlot
from app.models.timetable import TimetableRun
from app.schemas.academic import (
    SemesterCreate, SemesterUpdate, SemesterOut,
    TimeSlotCreate, TimeSlotOut,
)
from app.core.permissions import get_current_user, require_university_admin

router = APIRouter(tags=["Semesters"])


@router.post("/semesters/", response_model=SemesterOut, status_code=status.HTTP_201_CREATED)
def create_semester(
    payload: SemesterCreate,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = Semester(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.get("/semesters/", response_model=list[SemesterOut])
def list_semesters(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return db.query(Semester).all()


@router.get("/semesters/{semester_id}", response_model=SemesterOut)
def get_semester(semester_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    obj = db.get(Semester, semester_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Semester not found")
    return obj


@router.put("/semesters/{semester_id}", response_model=SemesterOut)
def update_semester(
    semester_id: int,
    payload: SemesterUpdate,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = db.get(Semester, semester_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Semester not found")
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(obj, k, v)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/semesters/{semester_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_semester(
    semester_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = db.get(Semester, semester_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Semester not found")
    # Delete timetable runs for this semester (their children cascade via ORM)
    for run in db.query(TimetableRun).filter(TimetableRun.semester_id == semester_id).all():
        db.delete(run)
    # Delete time slots
    db.query(TimeSlot).filter(TimeSlot.semester_id == semester_id).delete(synchronize_session=False)
    db.delete(obj)
    db.commit()


@router.post("/semesters/timeslots/", response_model=TimeSlotOut, status_code=status.HTTP_201_CREATED)
def create_timeslot(
    payload: TimeSlotCreate,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = TimeSlot(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.get("/semesters/{semester_id}/timeslots", response_model=list[TimeSlotOut])
def list_timeslots(
    semester_id: int,
    db: Session = Depends(get_db),
):
    return db.query(TimeSlot).filter(TimeSlot.semester_id == semester_id).all()


@router.delete("/semesters/timeslots/{timeslot_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_timeslot(
    timeslot_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = db.get(TimeSlot, timeslot_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="TimeSlot not found")
    db.delete(obj)
    db.commit()
