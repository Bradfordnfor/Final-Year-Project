from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.university import University
from app.schemas.university import UniversityCreate, UniversityOut
from app.core.permissions import get_current_user, require_university_admin

router = APIRouter(prefix="/universities", tags=["Universities"])


@router.get("/", response_model=list[UniversityOut])
def list_universities(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return db.query(University).all()


@router.get("/{university_id}", response_model=UniversityOut)
def get_university(university_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    obj = db.get(University, university_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="University not found")
    return obj


@router.post("/", response_model=UniversityOut, status_code=status.HTTP_201_CREATED)
def create_university(
    payload: UniversityCreate,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = University(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.put("/{university_id}", response_model=UniversityOut)
def update_university(
    university_id: int,
    payload: UniversityCreate,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = db.get(University, university_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="University not found")
    for k, v in payload.model_dump().items():
        setattr(obj, k, v)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/{university_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_university(
    university_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = db.get(University, university_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="University not found")
    db.delete(obj)
    db.commit()
