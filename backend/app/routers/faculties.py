from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.university import Faculty, Department
from app.models.academic import Level, Class
from app.models.course import Course, SharedCourse
from app.schemas.university import FacultyCreate, FacultyOut
from app.core.permissions import get_current_user, require_university_admin

router = APIRouter(prefix="/faculties", tags=["Faculties"])


@router.get("/", response_model=list[FacultyOut])
def list_faculties(db: Session = Depends(get_db)):
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
    current_user=Depends(require_university_admin),
):
    obj = db.get(Faculty, faculty_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Faculty not found")
    if current_user.role != "super_admin" and obj.university_id != current_user.university_id:
        # 404 (not 403) so a university admin can't probe for another
        # university's faculty IDs — mirrors the department rename pattern.
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Faculty not found")
    if not payload.name.strip():
        raise HTTPException(status_code=422, detail="Name cannot be empty")
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
    dept_ids = [d.id for d in db.query(Department).filter(Department.faculty_id == faculty_id).all()]
    if dept_ids:
        level_ids = [l.id for l in db.query(Level).filter(Level.department_id.in_(dept_ids)).all()]
        course_ids = [c.id for c in db.query(Course).filter(Course.department_id.in_(dept_ids)).all()]
        if course_ids:
            db.query(SharedCourse).filter(SharedCourse.course_id.in_(course_ids)).delete(synchronize_session=False)
        db.query(Course).filter(Course.department_id.in_(dept_ids)).delete(synchronize_session=False)
        if level_ids:
            db.query(Class).filter(Class.level_id.in_(level_ids)).delete(synchronize_session=False)
        db.query(Level).filter(Level.department_id.in_(dept_ids)).delete(synchronize_session=False)
        db.query(Department).filter(Department.faculty_id == faculty_id).delete(synchronize_session=False)
    db.delete(obj)
    db.commit()
