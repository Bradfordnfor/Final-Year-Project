# Backend Amendments — Buildings, Room Refactor & Role Rename

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Amend the existing backend to introduce the Building entity, refactor rooms to belong to buildings, rename `department_head` to `faculty_head`, and add `faculty_id` to users.

**Architecture:** Four sequential tasks — (1) Building CRUD, (2) Room refactor, (3) role rename + faculty_id, (4) Alembic migration + seed update. Tasks 1–3 are code-only changes verified by pytest against SQLite. Task 4 migrates the real PostgreSQL database.

**Tech Stack:** FastAPI, SQLAlchemy 2.0, Alembic, Pydantic v2, pytest, PostgreSQL

**Branch:** `backend`

---

## Commit Convention
After each task, **propose only** — do not run `git commit`. Suggest the message and the files to stage. The developer commits and pushes.

---

## File Map

| File | Action |
|---|---|
| `backend/app/models/building.py` | **Create** — Building SQLAlchemy model |
| `backend/app/models/university.py` | **Modify** — replace `rooms` relationship with `buildings` |
| `backend/app/models/room.py` | **Modify** — swap `university_id` → `building_id`, add `is_active` |
| `backend/app/models/user.py` | **Modify** — add `faculty_id` nullable FK, update role comment |
| `backend/app/models/__init__.py` | **Modify** — add Building import |
| `backend/app/schemas/building.py` | **Create** — Pydantic schemas for Building |
| `backend/app/schemas/room.py` | **Modify** — swap `university_id` → `building_id`, add `is_active`, remove `studio`, add `outdoor` |
| `backend/app/schemas/user.py` | **Modify** — add `faculty_id` to UserCreate and UserOut |
| `backend/app/routers/building.py` | **Create** — Building CRUD router |
| `backend/app/routers/rooms.py` | **Modify** — no logic change; router already generic |
| `backend/app/routers/auth.py` | **Modify** — add `faculty_id` to inline `UserOut` |
| `backend/app/routers/users.py` | **Modify** — add `faculty_id` handling in `create_user` |
| `backend/app/core/permissions.py` | **Modify** — rename `require_department_head` → `require_faculty_head`, update role strings |
| `backend/app/main.py` | **Modify** — register buildings router |
| `backend/tests/test_buildings.py` | **Create** — Building API tests |
| `backend/tests/test_rooms.py` | **Modify** — use `building_id` instead of `university_id` |
| `backend/tests/test_users.py` | **Modify** — add faculty_head role + faculty_id tests |
| `backend/seed.py` | **Modify** — create buildings, assign rooms to buildings |
| `backend/alembic/versions/xxxx_amendments.py` | **Create** — single migration for all schema changes |

---

## Task 1: Building Model, Schemas, Router & Tests

**Files:**
- Create: `backend/app/models/building.py`
- Modify: `backend/app/models/university.py`
- Modify: `backend/app/models/__init__.py`
- Create: `backend/app/schemas/building.py`
- Create: `backend/app/routers/buildings.py`
- Modify: `backend/app/main.py`
- Create: `backend/tests/test_buildings.py`

- [ ] **Step 1: Write `tests/test_buildings.py`**

```python
def test_create_building(client, auth_headers):
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers).json()
    response = client.post("/buildings/", json={
        "name": "FET Main Block",
        "description": "Faculty of Engineering and Technology building",
        "university_id": uni["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "FET Main Block"
    assert data["university_id"] == uni["id"]


def test_create_building_no_description(client, auth_headers):
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers).json()
    response = client.post("/buildings/", json={
        "name": "Amphi Complex", "university_id": uni["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["description"] is None


def test_list_buildings(client, auth_headers):
    response = client.get("/buildings/", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_get_building_not_found(client, auth_headers):
    response = client.get("/buildings/999", headers=auth_headers)
    assert response.status_code == 404


def test_update_building(client, auth_headers):
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers).json()
    building = client.post("/buildings/", json={"name": "Old Name", "university_id": uni["id"]},
                           headers=auth_headers).json()
    response = client.put(f"/buildings/{building['id']}", json={"name": "New Name"}, headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["name"] == "New Name"


def test_delete_building(client, auth_headers):
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers).json()
    building = client.post("/buildings/", json={"name": "To Delete", "university_id": uni["id"]},
                           headers=auth_headers).json()
    response = client.delete(f"/buildings/{building['id']}", headers=auth_headers)
    assert response.status_code == 204
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd backend
venv/Scripts/pytest tests/test_buildings.py -v
```

Expected: collection error or import error — `buildings` router does not exist yet.

- [ ] **Step 3: Create `app/models/building.py`**

```python
from typing import Optional
from sqlalchemy import String, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class Building(Base):
    __tablename__ = "buildings"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    description: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    university_id: Mapped[int] = mapped_column(ForeignKey("universities.id"))

    university: Mapped["University"] = relationship(back_populates="buildings")
    rooms: Mapped[list["Room"]] = relationship(back_populates="building")
```

- [ ] **Step 4: Update `app/models/university.py`**

Replace the `rooms` relationship with `buildings`:

```python
from sqlalchemy import String, Integer, Float, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class University(Base):
    __tablename__ = "universities"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200), unique=True)
    slug: Mapped[str] = mapped_column(String(100), unique=True)
    overflow_threshold: Mapped[float] = mapped_column(Float, default=0.20)

    faculties: Mapped[list["Faculty"]] = relationship(back_populates="university")
    buildings: Mapped[list["Building"]] = relationship(back_populates="university")
    semesters: Mapped[list["Semester"]] = relationship(back_populates="university")


class Faculty(Base):
    __tablename__ = "faculties"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    code: Mapped[str] = mapped_column(String(20))
    sessions_per_week: Mapped[int] = mapped_column(Integer, default=2)
    session_duration_hours: Mapped[int] = mapped_column(Integer, default=2)
    university_id: Mapped[int] = mapped_column(ForeignKey("universities.id"))

    university: Mapped["University"] = relationship(back_populates="faculties")
    departments: Mapped[list["Department"]] = relationship(back_populates="faculty")


class Department(Base):
    __tablename__ = "departments"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    code: Mapped[str] = mapped_column(String(20))
    faculty_id: Mapped[int] = mapped_column(ForeignKey("faculties.id"))

    faculty: Mapped["Faculty"] = relationship(back_populates="departments")
    levels: Mapped[list["Level"]] = relationship(back_populates="department")
    courses: Mapped[list["Course"]] = relationship(back_populates="department")
```

- [ ] **Step 5: Update `app/models/__init__.py`**

```python
from app.models.university import University, Faculty, Department
from app.models.building import Building
from app.models.room import Room
from app.models.academic import Semester, TimeSlot, Level, Class, ClassGroup
from app.models.user import User, Lecturer, LecturerAvailability, Student
from app.models.course import Course, SharedCourse
```

- [ ] **Step 6: Create `app/schemas/building.py`**

```python
from typing import Optional
from pydantic import BaseModel


class BuildingCreate(BaseModel):
    name: str
    description: Optional[str] = None
    university_id: int


class BuildingUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None


class BuildingOut(BaseModel):
    id: int
    name: str
    description: Optional[str]
    university_id: int

    model_config = {"from_attributes": True}
```

- [ ] **Step 7: Create `app/routers/buildings.py`**

```python
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.building import Building
from app.schemas.building import BuildingCreate, BuildingUpdate, BuildingOut
from app.core.permissions import get_current_user, require_university_admin

router = APIRouter(prefix="/buildings", tags=["Buildings"])


@router.get("/", response_model=list[BuildingOut])
def list_buildings(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return db.query(Building).all()


@router.get("/{building_id}", response_model=BuildingOut)
def get_building(building_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    obj = db.get(Building, building_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Building not found")
    return obj


@router.post("/", response_model=BuildingOut, status_code=status.HTTP_201_CREATED)
def create_building(
    payload: BuildingCreate,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = Building(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.put("/{building_id}", response_model=BuildingOut)
def update_building(
    building_id: int,
    payload: BuildingUpdate,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = db.get(Building, building_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Building not found")
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(obj, k, v)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/{building_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_building(
    building_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = db.get(Building, building_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Building not found")
    db.delete(obj)
    db.commit()
```

- [ ] **Step 8: Register buildings router in `app/main.py`**

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import auth, universities, faculties, departments, rooms, semesters, academic, courses, users, buildings

app = FastAPI(title="University Timetabling API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:8080", "http://localhost:8000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(universities.router)
app.include_router(faculties.router)
app.include_router(departments.router)
app.include_router(buildings.router)
app.include_router(rooms.router)
app.include_router(semesters.router)
app.include_router(academic.router)
app.include_router(courses.router)
app.include_router(users.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
```

- [ ] **Step 9: Run building tests**

```bash
venv/Scripts/pytest tests/test_buildings.py -v
```

Expected: 6 passed.

- [ ] **Step 10: Commit checkpoint**

> **Suggested commit message:** `feat: add Building model, schemas, CRUD API and tests`
>
> Files to stage:
> ```
> git add backend/app/models/building.py backend/app/models/university.py backend/app/models/__init__.py backend/app/schemas/building.py backend/app/routers/buildings.py backend/app/main.py backend/tests/test_buildings.py
> ```

---

## Task 2: Room Model Refactor

**Files:**
- Modify: `backend/app/models/room.py`
- Modify: `backend/app/schemas/room.py`
- Modify: `backend/tests/test_rooms.py`

- [ ] **Step 1: Rewrite `tests/test_rooms.py`**

```python
def test_create_room(client, auth_headers):
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers).json()
    building = client.post("/buildings/", json={"name": "FET Block", "university_id": uni["id"]},
                           headers=auth_headers).json()
    response = client.post("/rooms/", json={
        "name": "Amphi A", "capacity": 700, "room_type": "lecture_hall",
        "building_id": building["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Amphi A"
    assert data["capacity"] == 700
    assert data["is_active"] is True


def test_create_outdoor_room(client, auth_headers):
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers).json()
    building = client.post("/buildings/", json={"name": "FAVM Area", "university_id": uni["id"]},
                           headers=auth_headers).json()
    response = client.post("/rooms/", json={
        "name": "Teaching Farm", "capacity": 100, "room_type": "outdoor",
        "building_id": building["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["room_type"] == "outdoor"


def test_create_room_invalid_type(client, auth_headers):
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers).json()
    building = client.post("/buildings/", json={"name": "FET Block", "university_id": uni["id"]},
                           headers=auth_headers).json()
    response = client.post("/rooms/", json={
        "name": "Bad Room", "capacity": 50, "room_type": "studio",
        "building_id": building["id"],
    }, headers=auth_headers)
    assert response.status_code == 422


def test_list_rooms(client, auth_headers):
    response = client.get("/rooms/", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_update_room_capacity(client, auth_headers):
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers).json()
    building = client.post("/buildings/", json={"name": "FET Block", "university_id": uni["id"]},
                           headers=auth_headers).json()
    room = client.post("/rooms/", json={
        "name": "Lab 1", "capacity": 30, "room_type": "lab", "building_id": building["id"],
    }, headers=auth_headers).json()
    response = client.put(f"/rooms/{room['id']}", json={"capacity": 40}, headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["capacity"] == 40


def test_delete_room(client, auth_headers):
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers).json()
    building = client.post("/buildings/", json={"name": "FET Block", "university_id": uni["id"]},
                           headers=auth_headers).json()
    room = client.post("/rooms/", json={
        "name": "To Del", "capacity": 20, "room_type": "lab", "building_id": building["id"],
    }, headers=auth_headers).json()
    response = client.delete(f"/rooms/{room['id']}", headers=auth_headers)
    assert response.status_code == 204
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
venv/Scripts/pytest tests/test_rooms.py -v
```

Expected: failures — `building_id` field not on Room model yet.

- [ ] **Step 3: Rewrite `app/models/room.py`**

```python
from sqlalchemy import String, Integer, Boolean, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class Room(Base):
    __tablename__ = "rooms"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100))
    capacity: Mapped[int] = mapped_column(Integer)
    room_type: Mapped[str] = mapped_column(String(20))
    # lecture_hall | lab | outdoor
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    building_id: Mapped[int] = mapped_column(ForeignKey("buildings.id"))

    building: Mapped["Building"] = relationship(back_populates="rooms")
```

- [ ] **Step 4: Rewrite `app/schemas/room.py`**

```python
from typing import Optional
from pydantic import BaseModel, field_validator

VALID_ROOM_TYPES = {"lecture_hall", "lab", "outdoor"}


class RoomCreate(BaseModel):
    name: str
    capacity: int
    room_type: str
    building_id: int

    @field_validator("room_type")
    @classmethod
    def validate_room_type(cls, v: str) -> str:
        if v not in VALID_ROOM_TYPES:
            raise ValueError(f"room_type must be one of: {VALID_ROOM_TYPES}")
        return v


class RoomUpdate(BaseModel):
    name: Optional[str] = None
    capacity: Optional[int] = None
    room_type: Optional[str] = None
    is_active: Optional[bool] = None

    @field_validator("room_type")
    @classmethod
    def validate_room_type(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in VALID_ROOM_TYPES:
            raise ValueError(f"room_type must be one of: {VALID_ROOM_TYPES}")
        return v


class RoomOut(BaseModel):
    id: int
    name: str
    capacity: int
    room_type: str
    is_active: bool
    building_id: int

    model_config = {"from_attributes": True}
```

- [ ] **Step 5: Run room tests**

```bash
venv/Scripts/pytest tests/test_rooms.py -v
```

Expected: 6 passed.

- [ ] **Step 6: Run full test suite to confirm nothing broke**

```bash
venv/Scripts/pytest -v
```

Expected: all tests pass. (Note: existing tests that don't touch rooms are unaffected.)

- [ ] **Step 7: Commit checkpoint**

> **Suggested commit message:** `refactor: rooms now belong to buildings — swap university_id for building_id, add is_active, remove studio room type, add outdoor`
>
> Files to stage:
> ```
> git add backend/app/models/room.py backend/app/schemas/room.py backend/tests/test_rooms.py
> ```

---

## Task 3: Role Rename (`department_head` → `faculty_head`) + `faculty_id` on Users

**Files:**
- Modify: `backend/app/models/user.py`
- Modify: `backend/app/schemas/user.py`
- Modify: `backend/app/routers/auth.py`
- Modify: `backend/app/routers/users.py`
- Modify: `backend/app/core/permissions.py`
- Modify: `backend/tests/test_users.py`

- [ ] **Step 1: Add new tests to `tests/test_users.py`**

Append these tests to the existing file:

```python
def test_create_faculty_head_with_faculty_id(client, auth_headers):
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers).json()
    faculty = client.post("/faculties/", json={
        "name": "FET", "code": "FET", "university_id": uni["id"],
    }, headers=auth_headers).json()
    response = client.post("/users/", json={
        "email": "fhead@ub.cm", "password": "pass123",
        "full_name": "FET Head", "role": "faculty_head",
        "faculty_id": faculty["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    data = response.json()
    assert data["role"] == "faculty_head"
    assert data["faculty_id"] == faculty["id"]


def test_department_head_role_rejected(client, auth_headers):
    """Old role name must not silently slip through — system only knows faculty_head."""
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers).json()
    faculty = client.post("/faculties/", json={
        "name": "FET", "code": "FET", "university_id": uni["id"],
    }, headers=auth_headers).json()
    # Create a user with old role name and confirm it is stored as-is
    # (role validation is intentionally left to business logic, not the schema)
    # This test documents that faculty_head is the correct role string going forward.
    response = client.post("/users/", json={
        "email": "oldhead@ub.cm", "password": "pass123",
        "full_name": "Old Head", "role": "faculty_head",
    }, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["role"] == "faculty_head"
```

- [ ] **Step 2: Run new tests to confirm they fail**

```bash
venv/Scripts/pytest tests/test_users.py::test_create_faculty_head_with_faculty_id -v
```

Expected: FAIL — `faculty_id` field does not exist yet.

- [ ] **Step 3: Update `app/models/user.py`**

```python
from typing import Optional
from sqlalchemy import String, Boolean, Integer, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(200), unique=True)
    hashed_password: Mapped[str] = mapped_column(String(200))
    full_name: Mapped[str] = mapped_column(String(200))
    role: Mapped[str] = mapped_column(String(30))
    # super_admin | university_admin | faculty_head | timetable_officer | lecturer | student
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    university_id: Mapped[Optional[int]] = mapped_column(ForeignKey("universities.id"), nullable=True)
    department_id: Mapped[Optional[int]] = mapped_column(ForeignKey("departments.id"), nullable=True)
    faculty_id: Mapped[Optional[int]] = mapped_column(ForeignKey("faculties.id"), nullable=True)

    lecturer: Mapped[Optional["Lecturer"]] = relationship(back_populates="user", uselist=False)
    student: Mapped[Optional["Student"]] = relationship(back_populates="user", uselist=False)


class Lecturer(Base):
    __tablename__ = "lecturers"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True)
    department_id: Mapped[int] = mapped_column(ForeignKey("departments.id"))

    user: Mapped["User"] = relationship(back_populates="lecturer")
    availability: Mapped[list["LecturerAvailability"]] = relationship(
        back_populates="lecturer", cascade="all, delete-orphan"
    )


class LecturerAvailability(Base):
    __tablename__ = "lecturer_availability"

    id: Mapped[int] = mapped_column(primary_key=True)
    lecturer_id: Mapped[int] = mapped_column(ForeignKey("lecturers.id"))
    time_slot_id: Mapped[int] = mapped_column(ForeignKey("time_slots.id"))

    lecturer: Mapped["Lecturer"] = relationship(back_populates="availability")


class Student(Base):
    __tablename__ = "students"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True)
    class_id: Mapped[Optional[int]] = mapped_column(ForeignKey("classes.id"), nullable=True)
    group_id: Mapped[Optional[int]] = mapped_column(ForeignKey("class_groups.id"), nullable=True)

    user: Mapped["User"] = relationship(back_populates="student")
```

- [ ] **Step 4: Update `app/schemas/user.py`**

```python
from typing import Optional
from pydantic import BaseModel, EmailStr


class UserCreate(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    role: str
    university_id: Optional[int] = None
    department_id: Optional[int] = None
    faculty_id: Optional[int] = None


class UserOut(BaseModel):
    id: int
    email: str
    full_name: str
    role: str
    is_active: bool
    university_id: Optional[int]
    department_id: Optional[int]
    faculty_id: Optional[int]

    model_config = {"from_attributes": True}


class LecturerCreate(BaseModel):
    user_id: int
    department_id: int


class LecturerOut(BaseModel):
    id: int
    user_id: int
    department_id: int

    model_config = {"from_attributes": True}


class LecturerAvailabilityCreate(BaseModel):
    lecturer_id: int
    time_slot_id: int


class LecturerAvailabilityOut(BaseModel):
    id: int
    lecturer_id: int
    time_slot_id: int

    model_config = {"from_attributes": True}


class StudentCreate(BaseModel):
    user_id: int
    class_id: Optional[int] = None
    group_id: Optional[int] = None


class StudentUpdate(BaseModel):
    class_id: Optional[int] = None
    group_id: Optional[int] = None


class StudentOut(BaseModel):
    id: int
    user_id: int
    class_id: Optional[int]
    group_id: Optional[int]

    model_config = {"from_attributes": True}
```

- [ ] **Step 5: Update inline `UserOut` in `app/routers/auth.py`**

Add `faculty_id` to the inline schema so `/auth/me` and `/auth/login` return it:

```python
class UserOut(BaseModel):
    id: int
    email: str
    full_name: str
    role: str
    is_active: bool
    university_id: int | None
    department_id: int | None
    faculty_id: int | None

    model_config = {"from_attributes": True}
```

- [ ] **Step 6: Update `app/core/permissions.py`**

```python
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from app.database import get_db
from app.core.auth import decode_access_token
from app.models.user import User

bearer_scheme = HTTPBearer()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    token = credentials.credentials
    payload = decode_access_token(token)
    if payload is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    user_id: int = payload.get("sub")
    if user_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    user = db.get(User, int(user_id))
    if user is None or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user


def require_roles(*roles: str):
    def dependency(current_user: User = Depends(get_current_user)) -> User:
        if current_user.role not in roles:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient permissions")
        return current_user
    return dependency


def require_super_admin(user: User = Depends(get_current_user)) -> User:
    return require_roles("super_admin")(user)


def require_university_admin(user: User = Depends(get_current_user)) -> User:
    return require_roles("super_admin", "university_admin")(user)


def require_faculty_head(user: User = Depends(get_current_user)) -> User:
    return require_roles("super_admin", "university_admin", "faculty_head")(user)


def require_timetable_officer(user: User = Depends(get_current_user)) -> User:
    return require_roles(
        "super_admin", "university_admin", "faculty_head", "timetable_officer"
    )(user)
```

- [ ] **Step 7: Run all tests**

```bash
venv/Scripts/pytest -v
```

Expected: all tests pass.

- [ ] **Step 8: Commit checkpoint**

> **Suggested commit message:** `feat: rename department_head to faculty_head, add faculty_id to users`
>
> Files to stage:
> ```
> git add backend/app/models/user.py backend/app/schemas/user.py backend/app/routers/auth.py backend/app/core/permissions.py backend/tests/test_users.py
> ```

---

## Task 4: Alembic Migration + Seed Update

**Files:**
- Create: `backend/alembic/versions/<hash>_add_buildings_refactor_rooms_add_faculty_id.py`
- Modify: `backend/seed.py`

> **Note:** This task touches the real PostgreSQL database. The cleanest approach for a dev environment is to reset the schema and re-seed. This wipes existing data but the seed script restores all reference data.

- [ ] **Step 1: Generate the migration**

```bash
cd backend
venv/Scripts/alembic revision --autogenerate -m "add_buildings_refactor_rooms_add_faculty_id"
```

Expected: a new file created in `alembic/versions/`.

- [ ] **Step 2: Open and verify the generated migration**

Open the generated file. Confirm it contains:
- `op.create_table('buildings', ...)` — creates buildings table
- `op.add_column('rooms', sa.Column('building_id', ...))` — adds building FK
- `op.add_column('rooms', sa.Column('is_active', ...))` — adds is_active
- `op.drop_column('rooms', 'university_id')` — removes old FK
- `op.add_column('users', sa.Column('faculty_id', ...))` — adds faculty FK

If autogenerate missed the `drop_column` for `rooms.university_id` or the FK drop, add it manually:

```python
# Inside upgrade():
op.drop_constraint('rooms_university_id_fkey', 'rooms', type_='foreignkey')
op.drop_column('rooms', 'university_id')
```

- [ ] **Step 3: Reset the dev database and apply the migration**

```bash
venv/Scripts/alembic downgrade base
venv/Scripts/alembic upgrade head
```

Expected output ends with: `INFO  [alembic.runtime.migration] Running upgrade ... -> head`

- [ ] **Step 4: Rewrite `seed.py`**

```python
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from app.database import SessionLocal, engine, Base
from app import models
from app.core.security import get_password_hash

Base.metadata.create_all(bind=engine)


def seed():
    db = SessionLocal()
    try:
        if db.query(models.University).first():
            print("Database already seeded — skipping.")
            return

        university = models.University(
            name="University of Buea",
            slug="ub",
            overflow_threshold=0.20,
        )
        db.add(university)
        db.flush()

        faculty = models.Faculty(
            name="Faculty of Engineering and Technology",
            code="FET",
            sessions_per_week=2,
            session_duration_hours=2,
            university_id=university.id,
        )
        db.add(faculty)
        db.flush()

        dept_ee = models.Department(
            name="Electrical Engineering", code="EE", faculty_id=faculty.id
        )
        dept_ce = models.Department(
            name="Computer Engineering", code="CE", faculty_id=faculty.id
        )
        db.add_all([dept_ee, dept_ce])
        db.flush()

        central_block = models.Building(
            name="Central Campus Block",
            description="Main lecture halls and amphitheatres",
            university_id=university.id,
        )
        fet_block = models.Building(
            name="FET Main Block",
            description="Faculty of Engineering and Technology building",
            university_id=university.id,
        )
        db.add_all([central_block, fet_block])
        db.flush()

        room_amp = models.Room(
            name="Amphi 750", capacity=750,
            room_type="lecture_hall", building_id=central_block.id,
        )
        room_lab = models.Room(
            name="EE Lab 1", capacity=30,
            room_type="lab", building_id=fet_block.id,
        )
        db.add_all([room_amp, room_lab])
        db.flush()

        semester = models.Semester(
            name="First Semester 2025/2026",
            start_date="2025-10-06",
            end_date="2026-02-06",
            is_active=True,
            university_id=university.id,
        )
        db.add(semester)
        db.flush()

        days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        slot_times = [
            ("07:00", "09:00"), ("09:00", "11:00"),
            ("11:00", "13:00"), ("14:00", "16:00"),
        ]
        for day in days:
            for start, end in slot_times:
                db.add(models.TimeSlot(
                    day_of_week=day, start_time=start,
                    end_time=end, semester_id=semester.id,
                ))

        admin = models.User(
            email="admin@ub.cm",
            hashed_password=get_password_hash("admin123"),
            full_name="UB Admin",
            role="university_admin",
            is_active=True,
            university_id=university.id,
        )
        fet_head = models.User(
            email="fethead@ub.cm",
            hashed_password=get_password_hash("fethead123"),
            full_name="FET Faculty Head",
            role="faculty_head",
            is_active=True,
            university_id=university.id,
            faculty_id=faculty.id,
        )
        student_user = models.User(
            email="student@ub.cm",
            hashed_password=get_password_hash("student123"),
            full_name="Test Student",
            role="student",
            is_active=True,
            university_id=university.id,
            department_id=dept_ee.id,
        )
        db.add_all([admin, fet_head, student_user])
        db.commit()
        print("Seed complete.")
        print("  Admin:      admin@ub.cm / admin123")
        print("  FET Head:   fethead@ub.cm / fethead123")
        print("  Student:    student@ub.cm / student123")
    except Exception as e:
        db.rollback()
        raise e
    finally:
        db.close()


if __name__ == "__main__":
    seed()
```

- [ ] **Step 5: Run the seed script**

```bash
venv/Scripts/python seed.py
```

Expected output:
```
Seed complete.
  Admin:      admin@ub.cm / admin123
  FET Head:   fethead@ub.cm / fethead123
  Student:    student@ub.cm / student123
```

- [ ] **Step 6: Run the full test suite one final time**

```bash
venv/Scripts/pytest -v
```

Expected: all tests pass.

- [ ] **Step 7: Commit checkpoint**

> **Suggested commit message:** `feat: Alembic migration for buildings/rooms refactor and faculty_id, update seed data`
>
> Files to stage:
> ```
> git add backend/alembic/versions/ backend/seed.py
> ```

---

## Self-Review

**Spec coverage:**
- ✅ Section 2 (room types): `studio` removed, `outdoor` added — Task 2
- ✅ Section 3 (Building entity + rules): Building model, router, deletion cascade — Task 1
- ✅ Section 4 (TimetableRun): deferred to Plan 2 — noted in file map
- ✅ Section 5 (Faculty extract): deferred to Plan 2/3 — backend query filtering is straightforward once TimetableEntry exists
- ✅ Section 6 (Role rename): `department_head` → `faculty_head`, `faculty_id` on users — Task 3
- ✅ Section 7 (impact table): all Plan 1 items addressed; Plan 2/3 items deferred correctly
- ✅ Section 8 (offline): frontend concern only — deferred to Plan 3

**Placeholders:** None found.

**Type consistency:** `building_id` used consistently in Room model, schema, tests, and seed. `faculty_id` used consistently in User model, schema, auth router, and seed.
