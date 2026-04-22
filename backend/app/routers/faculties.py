from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.university import Faculty
from app.schemas.university import FacultyCreate, FacultyOut
from app.core.permissions import get_current_user, require_university_admin

router = APIRouter(prefix="/faculties", tags=["Faculties"])


@router.get("/", response_model=list[FacultyOut])
def list_faculties(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return db.query(Faculty).all()


@router.get("/{faculty_id}", response_model=FacultyOut)
def get_faculty(faculty_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    obj = db.get(Faculty, faculty_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Faculty not found")
    return obj


@router.post("/", response_model=FacultyOut, status_code=status.HTTP_201_CREATED)
def create_faculty(
    payload: FacultyCreate,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = Faculty(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.put("/{faculty_id}", response_model=FacultyOut)
def update_faculty(
    faculty_id: int,
    payload: FacultyCreate,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = db.get(Faculty, faculty_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Faculty not found")
    for k, v in payload.model_dump().items():
        setattr(obj, k, v)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/{faculty_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_faculty(
    faculty_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = db.get(Faculty, faculty_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Faculty not found")
    db.delete(obj)
    db.commit()
