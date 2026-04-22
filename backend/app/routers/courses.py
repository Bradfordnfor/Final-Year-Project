from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.course import Course, SharedCourse
from app.schemas.course import (
    CourseCreate, CourseUpdate, CourseOut,
    SharedCourseCreate, SharedCourseOut,
)
from app.core.permissions import get_current_user, require_timetable_officer

router = APIRouter(tags=["Courses"])


@router.post("/courses/", response_model=CourseOut, status_code=status.HTTP_201_CREATED)
def create_course(
    payload: CourseCreate,
    db: Session = Depends(get_db),
    _=Depends(require_timetable_officer),
):
    obj = Course(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.get("/courses/", response_model=list[CourseOut])
def list_courses(
    level_id: int | None = None,
    department_id: int | None = None,
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    q = db.query(Course)
    if level_id is not None:
        q = q.filter(Course.level_id == level_id)
    if department_id is not None:
        q = q.filter(Course.department_id == department_id)
    return q.all()


@router.get("/courses/{course_id}", response_model=CourseOut)
def get_course(course_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    obj = db.get(Course, course_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found")
    return obj


@router.put("/courses/{course_id}", response_model=CourseOut)
def update_course(
    course_id: int,
    payload: CourseUpdate,
    db: Session = Depends(get_db),
    _=Depends(require_timetable_officer),
):
    obj = db.get(Course, course_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found")
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(obj, k, v)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/courses/{course_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_course(
    course_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_timetable_officer),
):
    obj = db.get(Course, course_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found")
    db.delete(obj)
    db.commit()


@router.post("/courses/shared/", response_model=SharedCourseOut, status_code=status.HTTP_201_CREATED)
def add_shared_course(
    payload: SharedCourseCreate,
    db: Session = Depends(get_db),
    _=Depends(require_timetable_officer),
):
    existing = db.query(SharedCourse).filter(
        SharedCourse.course_id == payload.course_id,
        SharedCourse.class_id == payload.class_id,
    ).first()
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="Course already shared with that class")
    obj = SharedCourse(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.get("/courses/{course_id}/shared", response_model=list[SharedCourseOut])
def list_shared_classes(
    course_id: int,
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    return db.query(SharedCourse).filter(SharedCourse.course_id == course_id).all()


@router.delete("/courses/shared/{shared_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_shared_course(
    shared_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_timetable_officer),
):
    obj = db.get(SharedCourse, shared_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Shared course relationship not found")
    db.delete(obj)
    db.commit()
