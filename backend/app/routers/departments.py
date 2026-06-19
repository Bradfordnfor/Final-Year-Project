from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.university import Department
from app.schemas.university import DepartmentCreate, DepartmentOut
from app.core.permissions import get_current_user, require_university_admin

router = APIRouter(prefix="/departments", tags=["Departments"])


@router.get("/", response_model=list[DepartmentOut])
def list_departments(db: Session = Depends(get_db)):
    return db.query(Department).all()


@router.get("/{department_id}", response_model=DepartmentOut)
def get_department(department_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    obj = db.get(Department, department_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Department not found")
    return obj


@router.post("/", response_model=DepartmentOut, status_code=status.HTTP_201_CREATED)
def create_department(
    payload: DepartmentCreate,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = Department(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.put("/{department_id}", response_model=DepartmentOut)
def update_department(
    department_id: int,
    payload: DepartmentCreate,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = db.get(Department, department_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Department not found")
    for k, v in payload.model_dump().items():
        setattr(obj, k, v)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/{department_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_department(
    department_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = db.get(Department, department_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Department not found")
    db.delete(obj)
    db.commit()
