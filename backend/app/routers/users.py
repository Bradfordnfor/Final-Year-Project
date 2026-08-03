import csv
import io
import secrets
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.user import User, Lecturer, LecturerAvailability, Student
from app.schemas.user import (
    UserCreate, UserOut,
    LecturerCreate, LecturerOut,
    LecturerAvailabilityCreate, LecturerAvailabilityOut,
    StudentCreate, StudentUpdate, StudentOut,
)
from app.core.security import get_password_hash
from app.core.permissions import get_current_user, require_super_admin, require_university_admin, require_timetable_officer
from app.services.email import get_email_sender
from app.routers.auth import send_activation

router = APIRouter(tags=["Users"])


@router.post("/users/", response_model=UserOut, status_code=status.HTTP_201_CREATED)
def create_user(
    payload: UserCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    sender=Depends(get_email_sender),
):
    if current_user.role not in ("super_admin", "university_admin"):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    if db.query(User).filter(User.email == payload.email).first():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")
    if payload.role == "faculty_head":
        if not payload.faculty_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="A faculty head must be assigned to a faculty. Select a faculty.",
            )
        existing_head = db.query(User).filter(
            User.role == "faculty_head",
            User.faculty_id == payload.faculty_id,
            User.is_active == True,  # noqa: E712
        ).first()
        if existing_head:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="This faculty already has an active head.",
            )
    data = payload.model_dump()
    user = User(
        **data,
        hashed_password=get_password_hash(secrets.token_urlsafe(16)),
        is_verified=False,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    send_activation(db, sender, user)
    db.commit()
    return user


@router.get("/users/", response_model=list[UserOut])
def list_users(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if current_user.role not in ("super_admin", "university_admin"):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    query = db.query(User)
    # A university admin only sees the users of their own university.
    if current_user.role == "university_admin":
        query = query.filter(User.university_id == current_user.university_id)
    return query.all()


@router.get("/users/{user_id}", response_model=UserOut)
def get_user(user_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return user


@router.post("/lecturers/", response_model=LecturerOut, status_code=status.HTTP_201_CREATED)
def create_lecturer(
    payload: LecturerCreate,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    if db.query(Lecturer).filter(Lecturer.user_id == payload.user_id).first():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Lecturer profile already exists for this user")
    obj = Lecturer(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.get("/lecturers/", response_model=list[LecturerOut])
def list_lecturers(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return [LecturerOut.from_lecturer(l) for l in db.query(Lecturer).all()]


# NOTE: must be declared before "/lecturers/{lecturer_id}" so "me" is not
# matched as an integer id.
@router.get("/lecturers/me", response_model=LecturerOut)
def get_my_lecturer_profile(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """The current lecturer's own profile, used to manage their availability.

    A lecturer account does not always have a Lecturer profile (only bulk
    import creates one). We provision it on first use so any lecturer can set
    their availability, as long as their account is linked to a department.
    """
    if current_user.role != "lecturer":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only lecturers have an availability profile",
        )
    lecturer = db.query(Lecturer).filter(Lecturer.user_id == current_user.id).first()
    if not lecturer:
        if current_user.department_id is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Your account is not linked to a department. Ask an "
                       "administrator to set your department before setting availability.",
            )
        lecturer = Lecturer(user_id=current_user.id, department_id=current_user.department_id)
        db.add(lecturer)
        db.commit()
        db.refresh(lecturer)
    return LecturerOut.from_lecturer(lecturer)


@router.get("/lecturers/{lecturer_id}", response_model=LecturerOut)
def get_lecturer(lecturer_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    obj = db.get(Lecturer, lecturer_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Lecturer not found")
    return obj


# Roles that may manage any lecturer's availability. A lecturer may manage
# only their own (checked against their Lecturer record below).
_AVAILABILITY_MANAGER_ROLES = (
    "super_admin", "university_admin", "faculty_head", "timetable_officer",
)


def _assert_can_manage_availability(current_user: User, lecturer_id: int, db: Session) -> None:
    if current_user.role in _AVAILABILITY_MANAGER_ROLES:
        return
    if current_user.role == "lecturer":
        own = db.query(Lecturer).filter(Lecturer.user_id == current_user.id).first()
        if own and own.id == lecturer_id:
            return
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient permissions")


@router.post("/lecturers/availability/", response_model=LecturerAvailabilityOut, status_code=status.HTTP_201_CREATED)
def add_availability(
    payload: LecturerAvailabilityCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _assert_can_manage_availability(current_user, payload.lecturer_id, db)
    obj = LecturerAvailability(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.get("/lecturers/{lecturer_id}/availability", response_model=list[LecturerAvailabilityOut])
def get_lecturer_availability(
    lecturer_id: int,
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    return db.query(LecturerAvailability).filter(LecturerAvailability.lecturer_id == lecturer_id).all()


@router.delete("/lecturers/availability/{availability_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_availability(
    availability_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    obj = db.get(LecturerAvailability, availability_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Availability record not found")
    _assert_can_manage_availability(current_user, obj.lecturer_id, db)
    db.delete(obj)
    db.commit()


@router.post("/students/", response_model=StudentOut, status_code=status.HTTP_201_CREATED)
def create_student(
    payload: StudentCreate,
    db: Session = Depends(get_db),
    _=Depends(require_timetable_officer),
):
    if db.query(Student).filter(Student.user_id == payload.user_id).first():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Student profile already exists for this user")
    obj = Student(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.get("/students/", response_model=list[StudentOut])
def list_students(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return db.query(Student).all()


@router.put("/students/{student_id}", response_model=StudentOut)
def update_student(
    student_id: int,
    payload: StudentUpdate,
    db: Session = Depends(get_db),
    _=Depends(require_timetable_officer),
):
    obj = db.get(Student, student_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(obj, k, v)
    db.commit()
    db.refresh(obj)
    return obj


@router.post("/users/bulk-import/")
def bulk_import_lecturers(
    file: UploadFile = File(...),
    dry_run: bool = False,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    sender=Depends(get_email_sender),
):
    """Bulk-create lecturer accounts from a human-readable CSV.

    Columns: name, email, faculty, department. Faculty and department are
    matched by name (case-insensitive) within the importing admin's own
    university — no IDs needed. Each row is independent: a bad row is skipped
    with a reason rather than aborting the whole import.

    Every created lecturer account is pending: it has no usable password and
    gets an activation invitation emailed to it, the same as any other
    account-creation path.

    With ``dry_run=true`` the file is validated and the same created/skipped
    breakdown is returned, but nothing is written and no emails are sent. This
    drives the preview the admin reviews before confirming or cancelling. The
    response always carries the ``dry_run`` flag back.
    """
    from app.models.university import Faculty, Department

    if current_user.role not in ("super_admin", "university_admin"):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    if current_user.university_id is None:
        raise HTTPException(
            status_code=400,
            detail="Bulk import must be run by a university administrator; "
                   "it imports into that admin's university.",
        )
    university_id = current_user.university_id

    # A spreadsheet saved as .xlsx, an image, or any non-text upload is not
    # decodable — answer with a clear message instead of a 500.
    try:
        content = file.file.read().decode("utf-8-sig")
    except (UnicodeDecodeError, ValueError):
        raise HTTPException(
            status_code=400,
            detail="That file could not be read as CSV text. Please upload a "
                   "plain CSV file (in your spreadsheet, choose Save As / Export "
                   "→ CSV).",
        )

    reader = csv.DictReader(io.StringIO(content))
    try:
        header = reader.fieldnames or []
    except csv.Error:
        header = []

    required_cols = {"name", "email", "faculty", "department"}
    if not required_cols.issubset(set(header)):
        raise HTTPException(
            status_code=400,
            detail="CSV must contain columns: name, email, faculty, department.",
        )

    # Index this university's faculties and departments by lowercased name.
    faculties = db.query(Faculty).filter(
        Faculty.university_id == university_id).all()
    fac_by_name = {f.name.strip().lower(): f for f in faculties}
    fac_ids = [f.id for f in faculties]
    departments = (
        db.query(Department).filter(Department.faculty_id.in_(fac_ids)).all()
        if fac_ids else []
    )
    dept_by_key = {
        (d.faculty_id, d.name.strip().lower()): d for d in departments
    }

    created = []
    skipped = []
    seen_emails = set()

    for row in reader:
        name = (row.get("name") or "").strip()
        email = (row.get("email") or "").strip()
        faculty_name = (row.get("faculty") or "").strip()
        department_name = (row.get("department") or "").strip()

        if not (name and email and faculty_name and department_name):
            skipped.append({"email": email or "(missing)",
                            "reason": "missing required field"})
            continue

        faculty = fac_by_name.get(faculty_name.lower())
        if not faculty:
            skipped.append({"email": email,
                            "reason": f"faculty '{faculty_name}' not found"})
            continue

        dept = dept_by_key.get((faculty.id, department_name.lower()))
        if not dept:
            skipped.append({
                "email": email,
                "reason": f"department '{department_name}' not found in "
                          f"faculty '{faculty_name}'",
            })
            continue

        if email.lower() in seen_emails:
            skipped.append({"email": email, "reason": "duplicate row in file"})
            continue
        if db.query(User).filter(User.email == email).first():
            skipped.append({"email": email, "reason": "already exists"})
            continue
        seen_emails.add(email.lower())

        # Preview only describes what would happen — no account is minted.
        if dry_run:
            created.append({
                "name": name, "email": email,
                "faculty": faculty.name, "department": dept.name,
            })
            continue

        user = User(
            email=email,
            full_name=name,
            hashed_password=get_password_hash(secrets.token_urlsafe(16)),
            role="lecturer",
            is_active=True,
            is_verified=False,
            university_id=university_id,
            faculty_id=faculty.id,
            department_id=dept.id,
        )
        db.add(user)
        db.flush()
        db.add(Lecturer(user_id=user.id, department_id=dept.id))
        send_activation(db, sender, user)

        created.append({"name": name, "email": email})

    if dry_run:
        db.rollback()      # belt-and-braces: a preview must persist nothing
    else:
        db.commit()
    return {"created": created, "skipped": skipped, "dry_run": dry_run}
