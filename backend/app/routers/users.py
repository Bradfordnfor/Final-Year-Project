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

router = APIRouter(tags=["Users"])


@router.post("/users/", response_model=UserOut, status_code=status.HTTP_201_CREATED)
def create_user(
    payload: UserCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role not in ("super_admin", "university_admin"):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    if db.query(User).filter(User.email == payload.email).first():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")
    data = payload.model_dump()
    password = data.pop("password")
    user = User(**data, hashed_password=get_password_hash(password))
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@router.get("/users/", response_model=list[UserOut])
def list_users(db: Session = Depends(get_db), _=Depends(require_super_admin)):
    return db.query(User).all()


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
    return db.query(Lecturer).all()


@router.get("/lecturers/{lecturer_id}", response_model=LecturerOut)
def get_lecturer(lecturer_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    obj = db.get(Lecturer, lecturer_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Lecturer not found")
    return obj


@router.post("/lecturers/availability/", response_model=LecturerAvailabilityOut, status_code=status.HTTP_201_CREATED)
def add_availability(
    payload: LecturerAvailabilityCreate,
    db: Session = Depends(get_db),
    _=Depends(require_timetable_officer),
):
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
    _=Depends(require_timetable_officer),
):
    obj = db.get(LecturerAvailability, availability_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Availability record not found")
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
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    CSV columns: full_name, email, department_id, faculty_id, university_id
    Creates a User (role=lecturer) and Lecturer profile for each row.
    Returns created accounts with auto-generated passwords.
    """
    if current_user.role not in ("super_admin", "university_admin"):
        raise HTTPException(status_code=403, detail="Insufficient permissions")

    content = file.file.read().decode("utf-8")
    reader = csv.DictReader(io.StringIO(content))

    required_cols = {"full_name", "email", "department_id"}
    if not required_cols.issubset(set(reader.fieldnames or [])):
        raise HTTPException(
            status_code=400,
            detail=f"CSV must contain columns: {required_cols}",
        )

    created = []
    skipped = []

    for row in reader:
        email = row["email"].strip()
        full_name = row["full_name"].strip()
        department_id = int(row["department_id"].strip())
        faculty_id = int(row["faculty_id"].strip()) if row.get("faculty_id", "").strip() else None
        university_id = int(row["university_id"].strip()) if row.get("university_id", "").strip() else None

        if db.query(User).filter(User.email == email).first():
            skipped.append({"email": email, "reason": "already exists"})
            continue

        temp_password = secrets.token_urlsafe(10)
        user = User(
            email=email,
            full_name=full_name,
            hashed_password=get_password_hash(temp_password),
            role="lecturer",
            faculty_id=faculty_id,
            university_id=university_id,
        )
        db.add(user)
        db.flush()

        lecturer = Lecturer(user_id=user.id, department_id=department_id)
        db.add(lecturer)

        created.append({
            "email": email,
            "full_name": full_name,
            "temp_password": temp_password,
        })

    db.commit()
    return {"created": created, "skipped": skipped}
