import secrets
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.university import University, Faculty, Department
from app.models.academic import Level, Class, ClassGroup, Semester, TimeSlot
from app.models.building import Building
from app.models.room import Room
from app.models.course import Course, SharedCourse
from app.models.user import User, Lecturer, LecturerAvailability, Student
from app.models.timetable import (
    TimetableRun, TimetableRunFaculty, TimetableRunBuilding,
    TimetableEntry, TimetableEntryClass, TimetableConflict,
    GenerationJob, FacultyHeadApproval, Notification,
)
from app.schemas.university import (
    UniversityCreate, UniversityOut,
    UniversityWithAdminCreate, UniversityCreateResponse,
)
from app.core.permissions import get_current_user, require_super_admin
from app.core.security import get_password_hash
from app.services.email import get_email_sender, activation_link
from app.routers.auth import send_activation

router = APIRouter(prefix="/universities", tags=["Universities"])


def _delete_university_cascade(db: Session, university_id: int) -> None:
    """Delete a university and everything it owns, in child-to-parent order.

    The owned graph is large and not fully reachable through ORM relationships,
    so the rows are removed explicitly. Deleting the university on its own would
    fail, because SQLAlchemy would try to null the NOT NULL university_id on its
    faculties, buildings, and semesters.
    """
    def ids(model, *conditions):
        if not conditions:
            return []
        return [row[0] for row in db.query(model.id).filter(*conditions).all()]

    faculty_ids = ids(Faculty, Faculty.university_id == university_id)
    dept_ids = ids(Department, Department.faculty_id.in_(faculty_ids)) if faculty_ids else []
    level_ids = ids(Level, Level.department_id.in_(dept_ids)) if dept_ids else []
    class_ids = ids(Class, Class.level_id.in_(level_ids)) if level_ids else []
    group_ids = ids(ClassGroup, ClassGroup.class_id.in_(class_ids)) if class_ids else []

    course_filters = []
    if dept_ids:
        course_filters.append(Course.department_id.in_(dept_ids))
    if level_ids:
        course_filters.append(Course.level_id.in_(level_ids))
    course_filters.append(Course.university_id == university_id)
    from sqlalchemy import or_
    course_ids = ids(Course, or_(*course_filters))

    building_ids = ids(Building, Building.university_id == university_id)
    room_ids = ids(Room, Room.building_id.in_(building_ids)) if building_ids else []
    semester_ids = ids(Semester, Semester.university_id == university_id)
    timeslot_ids = ids(TimeSlot, TimeSlot.semester_id.in_(semester_ids)) if semester_ids else []
    run_ids = ids(TimetableRun, TimetableRun.semester_id.in_(semester_ids)) if semester_ids else []
    entry_ids = ids(TimetableEntry, TimetableEntry.run_id.in_(run_ids)) if run_ids else []
    lecturer_ids = ids(Lecturer, Lecturer.department_id.in_(dept_ids)) if dept_ids else []

    # Users tied to this university: its admins/heads/officers, anyone linked to
    # one of its faculties or departments, and the accounts behind its lecturers
    # and students. All of these reference rows we are about to delete, so every
    # one must be removed before its referent.
    user_conditions = [User.university_id == university_id]
    if faculty_ids:
        user_conditions.append(User.faculty_id.in_(faculty_ids))
    if dept_ids:
        user_conditions.append(User.department_id.in_(dept_ids))
    user_ids = set(ids(User, or_(*user_conditions)))
    if lecturer_ids:
        user_ids.update(
            row[0] for row in
            db.query(Lecturer.user_id).filter(Lecturer.id.in_(lecturer_ids)).all()
        )
    student_conditions = []
    if class_ids:
        student_conditions.append(Student.class_id.in_(class_ids))
    if group_ids:
        student_conditions.append(Student.group_id.in_(group_ids))
    student_ids = ids(Student, or_(*student_conditions)) if student_conditions else []
    if student_ids:
        user_ids.update(
            row[0] for row in
            db.query(Student.user_id).filter(Student.id.in_(student_ids)).all()
        )
    user_ids = list(user_ids)

    def purge(model, condition):
        db.query(model).filter(condition).delete(synchronize_session=False)

    # The order is child-to-parent: every referencing row is deleted before the
    # row it points at, which the database (PostgreSQL) enforces.

    # Timetable run graph (references runs, courses, rooms, slots, classes, users)
    if entry_ids:
        purge(TimetableEntryClass, TimetableEntryClass.entry_id.in_(entry_ids))
    if run_ids:
        purge(TimetableEntry, TimetableEntry.run_id.in_(run_ids))
        purge(TimetableConflict, TimetableConflict.run_id.in_(run_ids))
        purge(GenerationJob, GenerationJob.run_id.in_(run_ids))
        purge(FacultyHeadApproval, FacultyHeadApproval.run_id.in_(run_ids))
        purge(TimetableRunFaculty, TimetableRunFaculty.run_id.in_(run_ids))
        purge(TimetableRunBuilding, TimetableRunBuilding.run_id.in_(run_ids))
        purge(TimetableRun, TimetableRun.id.in_(run_ids))

    # Lecturer availability and shared-course links
    if lecturer_ids:
        purge(LecturerAvailability, LecturerAvailability.lecturer_id.in_(lecturer_ids))
    if timeslot_ids:
        purge(LecturerAvailability, LecturerAvailability.time_slot_id.in_(timeslot_ids))
    if course_ids:
        purge(SharedCourse, SharedCourse.course_id.in_(course_ids))
    if class_ids:
        purge(SharedCourse, SharedCourse.class_id.in_(class_ids))

    # People: students and lecturers reference users, so delete them first, then
    # the users themselves (and their notifications) BEFORE the faculties and
    # departments those users point at.
    if student_ids:
        purge(Student, Student.id.in_(student_ids))
    if lecturer_ids:
        purge(Lecturer, Lecturer.id.in_(lecturer_ids))
    if user_ids:
        purge(Notification, Notification.user_id.in_(user_ids))
        purge(User, User.id.in_(user_ids))

    # Academic tree
    if course_ids:
        purge(Course, Course.id.in_(course_ids))
    if group_ids:
        purge(ClassGroup, ClassGroup.id.in_(group_ids))
    if class_ids:
        purge(Class, Class.id.in_(class_ids))
    if level_ids:
        purge(Level, Level.id.in_(level_ids))
    if dept_ids:
        purge(Department, Department.id.in_(dept_ids))
    if faculty_ids:
        purge(Faculty, Faculty.id.in_(faculty_ids))

    # Physical and temporal resources
    if timeslot_ids:
        purge(TimeSlot, TimeSlot.id.in_(timeslot_ids))
    if semester_ids:
        purge(Semester, Semester.id.in_(semester_ids))
    if room_ids:
        purge(Room, Room.id.in_(room_ids))
    if building_ids:
        purge(Building, Building.id.in_(building_ids))

    purge(University, University.id == university_id)


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
    sender=Depends(get_email_sender),
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
        hashed_password=get_password_hash(secrets.token_urlsafe(16)),
        role="university_admin",
        university_id=university.id,
        is_active=True,
        is_verified=False,
    )
    db.add(admin)
    db.flush()
    db.commit()
    db.refresh(university)
    db.refresh(admin)

    raw = send_activation(db, sender, admin)
    db.commit()
    link = activation_link(raw)

    return UniversityCreateResponse(
        id=university.id,
        name=university.name,
        slug=university.slug,
        overflow_threshold=university.overflow_threshold,
        admin_id=admin.id,
        admin_email=admin.email,
        admin_full_name=admin.full_name,
        admin_activation_link=link,
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
    _delete_university_cascade(db, university_id)
    db.commit()
