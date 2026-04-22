"""
Faculty-head scoped data management.
A faculty head can only manage data within their own faculty.
"""
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.university import Department, Faculty
from app.models.academic import Level, Class, ClassGroup
from app.models.course import Course
from app.models.user import User
from app.core.permissions import require_faculty_head, get_current_user

router = APIRouter(prefix="/faculty-setup", tags=["Faculty Setup"])


def _my_faculty_id(current_user: User) -> int:
    if not current_user.faculty_id:
        raise HTTPException(status_code=403, detail="No faculty assigned to your account")
    return current_user.faculty_id


# ─── Faculty tree overview ───────────────────────────────────────────────────

@router.get("/tree")
def get_faculty_tree(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    """Full hierarchy: departments → levels → classes for this faculty head's faculty."""
    fac_id = _my_faculty_id(current_user)
    faculty = db.get(Faculty, fac_id)
    if not faculty:
        raise HTTPException(status_code=404, detail="Faculty not found")

    result = {"id": faculty.id, "name": faculty.name, "code": faculty.code, "departments": []}

    for dept in faculty.departments:
        dept_node = {"id": dept.id, "name": dept.name, "code": dept.code, "levels": []}
        for level in dept.levels:
            level_node = {
                "id": level.id, "number": level.number,
                "classes": [
                    {"id": c.id, "name": c.name, "population": c.population}
                    for c in level.classes
                ],
                "courses": [
                    {
                        "id": co.id, "code": co.code, "name": co.name,
                        "room_type_required": co.room_type_required,
                        "lecturer_id": co.lecturer_id,
                    }
                    for co in db.query(Course).filter(Course.level_id == level.id).all()
                ],
            }
            dept_node["levels"].append(level_node)
        result["departments"].append(dept_node)

    return result


# ─── Departments ─────────────────────────────────────────────────────────────

class DepartmentCreate(BaseModel):
    name: str
    code: str


class DepartmentOut(BaseModel):
    id: int
    name: str
    code: str
    faculty_id: int
    model_config = {"from_attributes": True}


@router.get("/departments", response_model=list[DepartmentOut])
def list_my_departments(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _my_faculty_id(current_user)
    return db.query(Department).filter(Department.faculty_id == fac_id).all()


@router.post("/departments", response_model=DepartmentOut, status_code=status.HTTP_201_CREATED)
def create_department(
    payload: DepartmentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _my_faculty_id(current_user)
    obj = Department(name=payload.name, code=payload.code, faculty_id=fac_id)
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/departments/{dept_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_department(
    dept_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _my_faculty_id(current_user)
    obj = db.query(Department).filter(Department.id == dept_id, Department.faculty_id == fac_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="Department not found")
    db.delete(obj)
    db.commit()


# ─── Levels ──────────────────────────────────────────────────────────────────

class LevelCreate(BaseModel):
    number: int
    department_id: int


class LevelOut(BaseModel):
    id: int
    number: int
    department_id: int
    model_config = {"from_attributes": True}


@router.post("/levels", response_model=LevelOut, status_code=status.HTTP_201_CREATED)
def create_level(
    payload: LevelCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _my_faculty_id(current_user)
    dept = db.query(Department).filter(
        Department.id == payload.department_id, Department.faculty_id == fac_id
    ).first()
    if not dept:
        raise HTTPException(status_code=403, detail="Department not in your faculty")
    obj = Level(number=payload.number, department_id=payload.department_id)
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.get("/departments/{dept_id}/levels", response_model=list[LevelOut])
def list_levels_for_dept(
    dept_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _my_faculty_id(current_user)
    dept = db.query(Department).filter(Department.id == dept_id, Department.faculty_id == fac_id).first()
    if not dept:
        raise HTTPException(status_code=403, detail="Department not in your faculty")
    return db.query(Level).filter(Level.department_id == dept_id).all()


@router.delete("/levels/{level_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_level(
    level_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _my_faculty_id(current_user)
    level = db.get(Level, level_id)
    if not level:
        raise HTTPException(status_code=404, detail="Level not found")
    dept = db.query(Department).filter(
        Department.id == level.department_id, Department.faculty_id == fac_id
    ).first()
    if not dept:
        raise HTTPException(status_code=403, detail="Level not in your faculty")
    db.delete(level)
    db.commit()


# ─── Classes ─────────────────────────────────────────────────────────────────

class ClassCreate(BaseModel):
    name: str
    population: int
    level_id: int


class ClassOut(BaseModel):
    id: int
    name: str
    population: int
    level_id: int
    model_config = {"from_attributes": True}


@router.post("/classes", response_model=ClassOut, status_code=status.HTTP_201_CREATED)
def create_class(
    payload: ClassCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _my_faculty_id(current_user)
    level = db.get(Level, payload.level_id)
    if not level:
        raise HTTPException(status_code=404, detail="Level not found")
    dept = db.query(Department).filter(
        Department.id == level.department_id, Department.faculty_id == fac_id
    ).first()
    if not dept:
        raise HTTPException(status_code=403, detail="Level not in your faculty")
    obj = Class(name=payload.name, population=payload.population, level_id=payload.level_id)
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.get("/levels/{level_id}/classes", response_model=list[ClassOut])
def list_classes_for_level(
    level_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _my_faculty_id(current_user)
    level = db.get(Level, level_id)
    if not level:
        raise HTTPException(status_code=404, detail="Level not found")
    dept = db.query(Department).filter(
        Department.id == level.department_id, Department.faculty_id == fac_id
    ).first()
    if not dept:
        raise HTTPException(status_code=403, detail="Level not in your faculty")
    return db.query(Class).filter(Class.level_id == level_id).all()


# ─── Courses ─────────────────────────────────────────────────────────────────

class FacultyCourseCreate(BaseModel):
    code: str
    name: str
    room_type_required: str = "lecture_hall"
    level_id: int
    department_id: int
    lecturer_id: Optional[int] = None


class FacultyCourseOut(BaseModel):
    id: int
    code: str
    name: str
    room_type_required: str
    level_id: int
    department_id: int
    lecturer_id: Optional[int]
    model_config = {"from_attributes": True}


@router.post("/courses", response_model=FacultyCourseOut, status_code=status.HTTP_201_CREATED)
def create_course(
    payload: FacultyCourseCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _my_faculty_id(current_user)
    dept = db.query(Department).filter(
        Department.id == payload.department_id, Department.faculty_id == fac_id
    ).first()
    if not dept:
        raise HTTPException(status_code=403, detail="Department not in your faculty")
    level = db.get(Level, payload.level_id)
    if not level or level.department_id != payload.department_id:
        raise HTTPException(status_code=400, detail="Level does not belong to that department")
    obj = Course(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.get("/levels/{level_id}/courses", response_model=list[FacultyCourseOut])
def list_courses_for_level(
    level_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    return db.query(Course).filter(Course.level_id == level_id).all()


@router.put("/courses/{course_id}", response_model=FacultyCourseOut)
def update_course(
    course_id: int,
    payload: FacultyCourseCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _my_faculty_id(current_user)
    obj = db.get(Course, course_id)
    if not obj:
        raise HTTPException(status_code=404, detail="Course not found")
    dept = db.query(Department).filter(
        Department.id == obj.department_id, Department.faculty_id == fac_id
    ).first()
    if not dept:
        raise HTTPException(status_code=403, detail="Course not in your faculty")
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(obj, k, v)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/courses/{course_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_course(
    course_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _my_faculty_id(current_user)
    obj = db.get(Course, course_id)
    if not obj:
        raise HTTPException(status_code=404, detail="Course not found")
    dept = db.query(Department).filter(
        Department.id == obj.department_id, Department.faculty_id == fac_id
    ).first()
    if not dept:
        raise HTTPException(status_code=403, detail="Course not in your faculty")
    db.delete(obj)
    db.commit()
