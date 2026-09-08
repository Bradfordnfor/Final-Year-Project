"""
Faculty-head scoped data management.
Faculty heads manage data within their own faculty.
Admins (super_admin / university_admin) can pass ?faculty_id=X to manage any faculty.
"""
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.university import Department, Faculty
from app.models.academic import Level, Class
from app.models.course import Course, SharedCourse
from app.models.user import User
from app.core.permissions import require_faculty_head, get_current_user

router = APIRouter(prefix="/faculty-setup", tags=["Faculty Setup"])

_ADMIN_ROLES = {"super_admin", "university_admin"}


def _resolve_faculty_id(current_user: User, faculty_id: Optional[int]) -> int:
    if current_user.role in _ADMIN_ROLES:
        if not faculty_id:
            raise HTTPException(
                status_code=400,
                detail="Admins must provide ?faculty_id=<id> to manage a faculty",
            )
        return faculty_id
    if not current_user.faculty_id:
        raise HTTPException(status_code=403, detail="No faculty assigned to your account")
    return current_user.faculty_id


# ─── Faculties list (for admin picker) ───────────────────────────────────────

@router.get("/faculties")
def list_faculties(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    if current_user.role in _ADMIN_ROLES:
        return db.query(Faculty).all()
    if current_user.faculty_id:
        fac = db.get(Faculty, current_user.faculty_id)
        return [fac] if fac else []
    return []


# ─── Public levels (no auth — used by public timetable class filter) ─────────

@router.get("/public-levels")
def get_public_levels(department_id: int, db: Session = Depends(get_db)):
    """Returns level numbers and class IDs for a department. No auth required."""
    levels = db.query(Level).filter(Level.department_id == department_id).all()
    result = []
    for level in levels:
        first_class = level.classes[0] if level.classes else None
        result.append({
            "id": level.id,
            "number": level.number,
            # Kept for backward compatibility (single-class levels).
            "class_id": first_class.id if first_class else None,
            # Every class at the level, so a filtered/exported timetable
            # includes all specialization tracks, not just the first.
            "class_ids": [c.id for c in level.classes],
        })
    return result


@router.get("/classes")
def list_all_classes(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """Every class with its name and population — used to label timetable
    entries (e.g. "CE200 (200)") for any internal user, the officer included."""
    return [
        {"id": c.id, "name": c.name, "population": c.population}
        for c in db.query(Class).all()
    ]


# ─── Faculty tree overview ───────────────────────────────────────────────────

@router.get("/tree")
def get_faculty_tree(
    faculty_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _resolve_faculty_id(current_user, faculty_id)
    faculty = db.get(Faculty, fac_id)
    if not faculty:
        raise HTTPException(status_code=404, detail="Faculty not found")

    result = {"id": faculty.id, "name": faculty.name, "code": faculty.code, "departments": []}

    for dept in faculty.departments:
        dept_node = {"id": dept.id, "name": dept.name, "code": dept.code, "levels": []}
        for level in dept.levels:
            first_class = level.classes[0] if level.classes else None
            level_node = {
                "id": level.id,
                "number": level.number,
                # Kept for backward compatibility: single-class levels show one
                # population. The `classes` list below carries every class at
                # the level (specialization tracks), each with its track label.
                "population": first_class.population if first_class else 0,
                "class_id": first_class.id if first_class else None,
                "classes": [
                    {"id": c.id, "name": c.name,
                     "population": c.population, "track": c.track}
                    for c in level.classes
                ],
                "courses": [
                    {
                        "id": co.id, "code": co.code, "name": co.name,
                        "room_type_required": co.room_type_required,
                        "lecturer_id": co.lecturer_id,
                        "weekly_hours": co.weekly_hours,
                        "semester": co.semester,
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
    faculty_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _resolve_faculty_id(current_user, faculty_id)
    return db.query(Department).filter(Department.faculty_id == fac_id).all()


@router.post("/departments", response_model=DepartmentOut, status_code=status.HTTP_201_CREATED)
def create_department(
    payload: DepartmentCreate,
    faculty_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _resolve_faculty_id(current_user, faculty_id)
    obj = Department(name=payload.name, code=payload.code, faculty_id=fac_id)
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/departments/{dept_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_department(
    dept_id: int,
    faculty_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _resolve_faculty_id(current_user, faculty_id)
    obj = db.query(Department).filter(Department.id == dept_id, Department.faculty_id == fac_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail="Department not found")
    level_ids = [l.id for l in db.query(Level).filter(Level.department_id == dept_id).all()]
    course_ids = [c.id for c in db.query(Course).filter(Course.department_id == dept_id).all()]
    if course_ids:
        db.query(SharedCourse).filter(SharedCourse.course_id.in_(course_ids)).delete(synchronize_session=False)
    db.query(Course).filter(Course.department_id == dept_id).delete(synchronize_session=False)
    if level_ids:
        db.query(Class).filter(Class.level_id.in_(level_ids)).delete(synchronize_session=False)
    db.query(Level).filter(Level.department_id == dept_id).delete(synchronize_session=False)
    db.delete(obj)
    db.commit()


# ─── Levels (each level auto-creates its single class) ───────────────────────

class LevelCreate(BaseModel):
    number: int
    department_id: int
    population: int = 0


class LevelOut(BaseModel):
    id: int
    number: int
    department_id: int
    model_config = {"from_attributes": True}


@router.post("/levels", response_model=LevelOut, status_code=status.HTTP_201_CREATED)
def create_level(
    payload: LevelCreate,
    faculty_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _resolve_faculty_id(current_user, faculty_id)
    dept = db.query(Department).filter(
        Department.id == payload.department_id, Department.faculty_id == fac_id
    ).first()
    if not dept:
        raise HTTPException(status_code=403, detail="Department not in your faculty")
    obj = Level(number=payload.number, department_id=payload.department_id)
    db.add(obj)
    db.flush()
    # Auto-create the single class for this level (e.g. "EE200")
    cls = Class(
        name=f"{dept.code}{payload.number}",
        population=payload.population,
        level_id=obj.id,
    )
    db.add(cls)
    db.commit()
    db.refresh(obj)
    return obj


@router.get("/departments/{dept_id}/levels", response_model=list[LevelOut])
def list_levels_for_dept(
    dept_id: int,
    faculty_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _resolve_faculty_id(current_user, faculty_id)
    dept = db.query(Department).filter(Department.id == dept_id, Department.faculty_id == fac_id).first()
    if not dept:
        raise HTTPException(status_code=403, detail="Department not in your faculty")
    return db.query(Level).filter(Level.department_id == dept_id).all()


@router.delete("/levels/{level_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_level(
    level_id: int,
    faculty_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _resolve_faculty_id(current_user, faculty_id)
    level = db.get(Level, level_id)
    if not level:
        raise HTTPException(status_code=404, detail="Level not found")
    dept = db.query(Department).filter(
        Department.id == level.department_id, Department.faculty_id == fac_id
    ).first()
    if not dept:
        raise HTTPException(status_code=403, detail="Level not in your faculty")
    course_ids = [c.id for c in db.query(Course).filter(Course.level_id == level_id).all()]
    if course_ids:
        db.query(SharedCourse).filter(SharedCourse.course_id.in_(course_ids)).delete(synchronize_session=False)
    db.query(Course).filter(Course.level_id == level_id).delete(synchronize_session=False)
    db.query(Class).filter(Class.level_id == level_id).delete(synchronize_session=False)
    db.delete(level)
    db.commit()


# ─── Courses ─────────────────────────────────────────────────────────────────

class FacultyCourseCreate(BaseModel):
    code: str
    name: str
    room_type_required: str = "lecture_hall"
    level_id: int
    department_id: int
    lecturer_id: Optional[int] = None
    weekly_hours: int = 2
    semester: int = 1  # 1 = first, 2 = second, 0 = both
    shared_class_ids: list[int] = []  # other classes that jointly attend this course


class FacultyCourseOut(BaseModel):
    id: int
    code: str
    name: str
    room_type_required: str
    level_id: int
    department_id: int
    lecturer_id: Optional[int]
    weekly_hours: int
    semester: int
    model_config = {"from_attributes": True}


@router.post("/courses", response_model=FacultyCourseOut, status_code=status.HTTP_201_CREATED)
def create_course(
    payload: FacultyCourseCreate,
    faculty_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _resolve_faculty_id(current_user, faculty_id)
    dept = db.query(Department).filter(
        Department.id == payload.department_id, Department.faculty_id == fac_id
    ).first()
    if not dept:
        raise HTTPException(status_code=403, detail="Department not in your faculty")
    level = db.get(Level, payload.level_id)
    if not level or level.department_id != payload.department_id:
        raise HTTPException(status_code=400, detail="Level does not belong to that department")
    data = payload.model_dump()
    shared_class_ids = data.pop("shared_class_ids", [])
    obj = Course(**data)
    db.add(obj)
    db.flush()
    # Link the other classes that jointly attend this course.
    for cid in shared_class_ids:
        db.add(SharedCourse(course_id=obj.id, class_id=cid))
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
    faculty_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _resolve_faculty_id(current_user, faculty_id)
    obj = db.get(Course, course_id)
    if not obj:
        raise HTTPException(status_code=404, detail="Course not found")
    dept = db.query(Department).filter(
        Department.id == obj.department_id, Department.faculty_id == fac_id
    ).first()
    if not dept:
        raise HTTPException(status_code=403, detail="Course not in your faculty")
    data = payload.model_dump(exclude_unset=True)
    data.pop("shared_class_ids", None)
    for k, v in data.items():
        setattr(obj, k, v)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/courses/{course_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_course(
    course_id: int,
    faculty_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_faculty_head),
):
    fac_id = _resolve_faculty_id(current_user, faculty_id)
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
