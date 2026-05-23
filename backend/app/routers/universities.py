from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.university import University
from app.models.user import User
from app.schemas.university import (
    UniversityCreate, UniversityOut,
    UniversityWithAdminCreate, UniversityCreateResponse,
)
from app.core.permissions import get_current_user, require_super_admin
from app.core.security import get_password_hash

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


@router.get("/{university_id}/structure")
def get_university_structure(
    university_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_super_admin),
):
    """Returns faculties and their departments for display — read-only."""
    obj = db.get(University, university_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="University not found")
    return {
        "id": obj.id,
        "name": obj.name,
        "faculties": [
            {
                "id": f.id,
                "name": f.name,
                "code": f.code,
                "departments": [
                    {"id": d.id, "name": d.name, "code": d.code}
                    for d in f.departments
                ],
            }
            for f in obj.faculties
        ],
    }


@router.post("/", response_model=UniversityCreateResponse, status_code=status.HTTP_201_CREATED)
def create_university(
    payload: UniversityWithAdminCreate,
    db: Session = Depends(get_db),
    _=Depends(require_super_admin),
):
    if db.query(University).filter(University.slug == payload.slug).first():
        raise HTTPException(status_code=400, detail="A university with that slug already exists")
    if db.query(User).filter(User.email == payload.admin_email).first():
        raise HTTPException(status_code=400, detail="An account with that email already exists")

    university = University(
        name=payload.name,
        slug=payload.slug,
        overflow_threshold=payload.overflow_threshold,
    )
    db.add(university)
    db.flush()

    admin = User(
        email=payload.admin_email,
        full_name=payload.admin_full_name,
        hashed_password=get_password_hash(payload.admin_password),
        role="university_admin",
        university_id=university.id,
        is_active=True,
    )
    db.add(admin)
    db.flush()

    db.commit()
    db.refresh(university)
    db.refresh(admin)

    return UniversityCreateResponse(
        id=university.id,
        name=university.name,
        slug=university.slug,
        overflow_threshold=university.overflow_threshold,
        admin_id=admin.id,
        admin_email=admin.email,
        admin_full_name=admin.full_name,
    )


@router.put("/{university_id}", response_model=UniversityOut)
def update_university(
    university_id: int,
    payload: UniversityCreate,
    db: Session = Depends(get_db),
    _=Depends(require_super_admin),
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
    _=Depends(require_super_admin),
):
    obj = db.get(University, university_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="University not found")
    db.delete(obj)
    db.commit()
