from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status
from sqlalchemy import func
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.course import Course, SharedCourse
from app.models.user import User, Lecturer
from app.models.university import Department
from app.models.academic import Level, Class
from app.schemas.course import (
    CourseCreate, CourseUpdate, CourseOut,
    SharedCourseCreate, SharedCourseOut,
)
from app.core.permissions import get_current_user, require_timetable_officer
from app.services.course_import import read_rows, match_lecturer, parse_int

ALLOWED_ROOM_TYPES = {"lecture_hall", "lab", "studio"}

router = APIRouter(tags=["Courses"])


@router.post("/courses/", response_model=CourseOut, status_code=status.HTTP_201_CREATED)
def create_course(
    payload: CourseCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in ("super_admin", "university_admin", "timetable_officer"):
        raise HTTPException(status_code=403, detail="Insufficient permissions")

    data = payload.model_dump()

    if current_user.role == "university_admin":
        # University admin adds university-wide requirements only
        data["university_id"] = current_user.university_id
        data["department_id"] = None
        data["level_id"] = None
    else:
        # Timetable officer / super_admin: department_id is required
        if data.get("department_id") is None and data.get("university_id") is None:
            raise HTTPException(
                status_code=400,
                detail="Provide either department_id (dept-specific course) or university_id (university-wide course)",
            )

    obj = Course(**data)
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.get("/courses/", response_model=list[CourseOut])
def list_courses(
    level_id: int | None = None,
    department_id: int | None = None,
    university_id: int | None = None,
    db: Session = Depends(get_db),
):
    q = db.query(Course)
    if level_id is not None:
        q = q.filter(Course.level_id == level_id)
    if department_id is not None:
        q = q.filter(Course.department_id == department_id)
    if university_id is not None:
        q = q.filter(Course.university_id == university_id)
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
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in ("super_admin", "university_admin", "timetable_officer"):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
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


@router.post("/courses/bulk-import/")
def bulk_import_courses(
    file: UploadFile = File(...),
    dry_run: bool = False,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Bulk-create courses from a CSV or Excel (.xlsx) file.

    The caller's role selects the mode. A faculty head imports departmental
    courses (semester 1 or 2) into their own faculty; a university admin imports
    year-long university-wide requirements (semester 0). Every row is
    independent: a bad row is skipped with a reason rather than aborting the
    batch. With ``dry_run=true`` the same breakdown is returned but nothing is
    written (this drives the preview the user confirms).
    """
    if current_user.role not in ("faculty_head", "university_admin"):
        raise HTTPException(
            status_code=403,
            detail="Only faculty heads and university admins can bulk-import courses.",
        )

    content = file.file.read()
    try:
        header, rows = read_rows(file.filename or "", content)
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail="That file could not be read. Please upload a CSV or Excel "
                   "(.xlsx) file.",
        )

    if current_user.role == "faculty_head":
        return _import_faculty_courses(db, current_user, header, rows, dry_run)
    return _import_university_courses(db, current_user, header, rows, dry_run)


def _normalize_room_type(raw) -> str:
    room_type = (raw or "").strip().lower()
    return room_type if room_type in ALLOWED_ROOM_TYPES else "lecture_hall"


def _import_faculty_courses(db, user, header, rows, dry_run):
    required = {"code", "name", "level", "department"}
    if not required.issubset(set(header)):
        raise HTTPException(
            status_code=400,
            detail="File must contain columns: code, name, level, department "
                   "(semester, weekly_hours, room_type, lecturer are optional).",
        )

    depts = db.query(Department).filter(Department.faculty_id == user.faculty_id).all()
    dept_by_name = {d.name.strip().lower(): d for d in depts}
    dept_ids = [d.id for d in depts]

    levels = (
        db.query(Level).filter(Level.department_id.in_(dept_ids)).all()
        if dept_ids else []
    )
    level_by_key = {(l.department_id, l.number): l for l in levels}

    # Classes at each level, for wiring shared courses to other departments.
    level_ids = [l.id for l in levels]
    classes = (
        db.query(Class).filter(Class.level_id.in_(level_ids)).all()
        if level_ids else []
    )
    classes_by_level: dict[int, list[Class]] = {}
    for c in classes:
        classes_by_level.setdefault(c.level_id, []).append(c)

    # Lecturers of these departments, grouped by department for scoped matching.
    candidates_by_dept: dict[int, list[tuple[int, str]]] = {}
    if dept_ids:
        lect_rows = (
            db.query(Lecturer, User)
            .join(User, Lecturer.user_id == User.id)
            .filter(Lecturer.department_id.in_(dept_ids))
            .all()
        )
        for lect, u in lect_rows:
            candidates_by_dept.setdefault(lect.department_id, []).append(
                (lect.id, u.full_name)
            )

    created, skipped, seen = [], [], set()

    for row in rows:
        code = (row.get("code") or "").strip()
        name = (row.get("name") or "").strip()
        level_raw = (row.get("level") or "").strip()
        dept_raw = (row.get("department") or "").strip()

        if not (code and name and level_raw and dept_raw):
            skipped.append({"code": code or "(missing)", "reason": "missing required field"})
            continue

        # First department owns the course; the rest are shared with it.
        dept_names = [d.strip() for d in dept_raw.split("|") if d.strip()]
        owner_name = dept_names[0]
        shared_names = dept_names[1:]

        dept = dept_by_name.get(owner_name.lower())
        if not dept:
            skipped.append({"code": code,
                            "reason": f"department '{owner_name}' not found in your faculty"})
            continue

        try:
            level_num = int(float(level_raw))
        except (ValueError, TypeError):
            skipped.append({"code": code, "reason": f"level '{level_raw}' is not a number"})
            continue

        level = level_by_key.get((dept.id, level_num))
        if not level:
            skipped.append({"code": code,
                            "reason": f"level {level_num} not found in department '{dept.name}'"})
            continue

        sem_raw = (row.get("semester") or "").strip()
        if not sem_raw:
            semester = 1
        else:
            try:
                semester = int(float(sem_raw))
            except (ValueError, TypeError):
                skipped.append({"code": code, "reason": f"semester '{sem_raw}' is not a number"})
                continue
        if semester == 0:
            skipped.append({"code": code,
                            "reason": "year-long courses are added by the university admin, not here"})
            continue
        if semester not in (1, 2):
            skipped.append({"code": code, "reason": f"semester {semester} must be 1 or 2"})
            continue

        weekly_hours = parse_int(row.get("weekly_hours"), 2)
        room_type = _normalize_room_type(row.get("room_type"))

        key = (dept.id, level.id, code.lower())
        if key in seen:
            skipped.append({"code": code, "reason": "duplicate row in file"})
            continue
        exists = (
            db.query(Course)
            .filter(Course.department_id == dept.id,
                    Course.level_id == level.id,
                    func.lower(Course.code) == code.lower())
            .first()
        )
        if exists:
            skipped.append({"code": code, "reason": "already exists"})
            continue
        seen.add(key)

        lecturer_raw = (row.get("lecturer") or "").strip()
        lect_id, lect_note = match_lecturer(lecturer_raw, candidates_by_dept.get(dept.id, []))

        # Resolve shared departments (best-effort; a problem is noted, never fatal).
        shared_with, shared_problems, shared_class_ids = [], [], []
        seen_share_ids = set()
        for sname in shared_names:
            sdept = dept_by_name.get(sname.lower())
            if not sdept:
                shared_problems.append(f"{sname}: department not found in your faculty - not shared")
                continue
            if sdept.id == dept.id:
                continue  # owner listed again; its own classes are already covered
            slevel = level_by_key.get((sdept.id, level_num))
            if not slevel:
                shared_problems.append(f"{sdept.name}: no level {level_num} - not shared")
                continue
            sclasses = classes_by_level.get(slevel.id, [])
            if not sclasses:
                shared_problems.append(f"{sdept.name}: level {level_num} has no classes - not shared")
                continue
            shared_with.append(sdept.name)
            for c in sclasses:
                if c.id not in seen_share_ids:
                    seen_share_ids.add(c.id)
                    shared_class_ids.append(c.id)
        shared_note = "; ".join(shared_problems) or None

        entry = {
            "code": code, "name": name, "level": level_num,
            "department": dept.name, "shared_with": shared_with,
            "semester": semester,
            "lecturer": lecturer_raw or None, "lecturer_note": lect_note,
            "shared_note": shared_note,
        }

        if not dry_run:
            course = Course(
                code=code, name=name, room_type_required=room_type,
                level_id=level.id, department_id=dept.id, university_id=None,
                lecturer_id=lect_id, weekly_hours=weekly_hours, semester=semester,
            )
            db.add(course)
            db.flush()  # assign course.id before adding shared links
            for cid in shared_class_ids:
                db.add(SharedCourse(course_id=course.id, class_id=cid))
        created.append(entry)

    if dry_run:
        db.rollback()
    else:
        db.commit()
    return {"created": created, "skipped": skipped, "dry_run": dry_run}


def _import_university_courses(db, user, header, rows, dry_run):
    required = {"code", "name"}
    if not required.issubset(set(header)):
        raise HTTPException(
            status_code=400,
            detail="File must contain columns: code, name "
                   "(weekly_hours, room_type, lecturer are optional).",
        )

    lect_rows = (
        db.query(Lecturer, User)
        .join(User, Lecturer.user_id == User.id)
        .filter(User.university_id == user.university_id)
        .all()
    )
    candidates = [(lect.id, u.full_name) for lect, u in lect_rows]

    created, skipped, seen = [], [], set()

    for row in rows:
        code = (row.get("code") or "").strip()
        name = (row.get("name") or "").strip()
        if not (code and name):
            skipped.append({"code": code or "(missing)", "reason": "missing required field"})
            continue

        weekly_hours = parse_int(row.get("weekly_hours"), 2)
        room_type = _normalize_room_type(row.get("room_type"))

        if code.lower() in seen:
            skipped.append({"code": code, "reason": "duplicate row in file"})
            continue
        exists = (
            db.query(Course)
            .filter(Course.university_id == user.university_id,
                    Course.department_id.is_(None),
                    func.lower(Course.code) == code.lower())
            .first()
        )
        if exists:
            skipped.append({"code": code, "reason": "already exists"})
            continue
        seen.add(code.lower())

        lecturer_raw = (row.get("lecturer") or "").strip()
        lect_id, lect_note = match_lecturer(lecturer_raw, candidates)

        entry = {
            "code": code, "name": name, "semester": 0,
            "lecturer": lecturer_raw or None, "lecturer_note": lect_note,
        }
        if not dry_run:
            db.add(Course(
                code=code, name=name, room_type_required=room_type,
                level_id=None, department_id=None,
                university_id=user.university_id,
                lecturer_id=lect_id, weekly_hours=weekly_hours, semester=0,
            ))
        created.append(entry)

    if dry_run:
        db.rollback()
    else:
        db.commit()
    return {"created": created, "skipped": skipped, "dry_run": dry_run}
