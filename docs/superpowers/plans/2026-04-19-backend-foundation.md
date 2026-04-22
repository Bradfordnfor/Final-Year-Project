# University Timetabling System — Backend Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete FastAPI backend — PostgreSQL models, JWT auth with role-based access control, and CRUD APIs for all university entities (universities, faculties, departments, rooms, semesters, courses, users, lecturers, students).

**Architecture:** Single FastAPI application with SQLAlchemy 2.0 ORM, Alembic migrations, JWT authentication, and pytest test suite. Each router handles one entity group. Role-based access is enforced via FastAPI dependency injection.

**Tech Stack:** Python 3.11+, FastAPI 0.115, SQLAlchemy 2.0, Alembic 1.13, PostgreSQL 16, Pydantic v2, python-jose (JWT), passlib[bcrypt], pytest, httpx

> **Note:** This is Plan 1 of 3.
> - **Plan 2** covers the Timetable Generation Engine (OR-Tools solver, lab splits, group rotations, overcapacity handling)
> - **Plan 3** covers the Flutter Frontend (all role-based screens)

> **Git workflow:** All backend work lives on the `backend` branch. Create it once before Task 1:
> ```bash
> git checkout -b backend
> ```
> Commit steps in this plan are **proposals only** — I will tell you when I think it's a good time to commit and suggest the message. You run `git add` and `git commit` yourself. You also decide when to push.

---

---

## Prerequisites (do these before starting)

1. Install **Python 3.11+**: https://www.python.org/downloads/ — check "Add to PATH" during install
2. Install **PostgreSQL 16**: https://www.postgresql.org/download/ — note the password you set for user `postgres`
3. Install **Git**: https://git-scm.com/downloads
4. Open **Git Bash** (or any terminal) for all commands in this plan

---

## File Structure

```
backend/
├── app/
│   ├── __init__.py
│   ├── main.py                  # FastAPI app entry point, router registration
│   ├── config.py                # Environment config (DB URL, JWT secret)
│   ├── database.py              # SQLAlchemy engine, session factory, Base
│   ├── models/
│   │   ├── __init__.py
│   │   ├── university.py        # University, Faculty, Department
│   │   ├── academic.py          # Level, Class, ClassGroup, Semester, TimeSlot
│   │   ├── user.py              # User, Lecturer, Student, LecturerAvailability
│   │   ├── course.py            # Course, SharedCourse
│   │   └── room.py              # Room
│   ├── schemas/
│   │   ├── __init__.py
│   │   ├── university.py        # Pydantic schemas for university entities
│   │   ├── academic.py          # Pydantic schemas for academic entities
│   │   ├── user.py              # Pydantic schemas for users
│   │   ├── course.py            # Pydantic schemas for courses
│   │   └── room.py              # Pydantic schemas for rooms
│   ├── routers/
│   │   ├── __init__.py
│   │   ├── auth.py              # POST /auth/login, POST /auth/register
│   │   ├── universities.py      # CRUD /universities
│   │   ├── faculties.py         # CRUD /faculties
│   │   ├── departments.py       # CRUD /departments
│   │   ├── rooms.py             # CRUD /rooms
│   │   ├── semesters.py         # CRUD /semesters + /timeslots
│   │   ├── academic.py          # CRUD /levels + /classes + /groups
│   │   ├── courses.py           # CRUD /courses + /shared-courses
│   │   └── users.py             # CRUD /users + /lecturers + /students + /availability
│   └── core/
│       ├── __init__.py
│       ├── auth.py              # JWT token creation and verification
│       ├── security.py          # Password hashing with bcrypt
│       └── permissions.py       # Role-based FastAPI dependencies
├── tests/
│   ├── conftest.py              # SQLite test DB, fixtures, TestClient
│   ├── test_auth.py
│   ├── test_universities.py
│   ├── test_faculties.py
│   ├── test_departments.py
│   ├── test_rooms.py
│   ├── test_semesters.py
│   ├── test_academic.py
│   ├── test_courses.py
│   └── test_users.py
├── alembic/
│   ├── env.py                   # Alembic migration environment
│   └── versions/                # Auto-generated migration files go here
├── alembic.ini
├── requirements.txt
└── .env.example
```

---

## Task 1: Python Environment & Project Setup

**Files:**
- Create: `backend/requirements.txt`
- Create: `backend/.env.example`
- Create: `backend/app/__init__.py` (empty)
- Create: `backend/app/models/__init__.py` (empty)
- Create: `backend/app/schemas/__init__.py` (empty)
- Create: `backend/app/routers/__init__.py` (empty)
- Create: `backend/app/core/__init__.py` (empty)
- Create: `backend/tests/__init__.py` (empty)

- [ ] **Step 1: Create the backend directory and navigate into it**

```bash
mkdir backend && cd backend
```

- [ ] **Step 2: Create a Python virtual environment**

A virtual environment keeps your project's dependencies isolated from other Python projects on your machine.

```bash
python -m venv venv
```

- [ ] **Step 3: Activate the virtual environment**

```bash
source venv/Scripts/activate
```

Your terminal prompt should now show `(venv)` at the start. You must activate this every time you open a new terminal to work on the backend.

- [ ] **Step 4: Create `requirements.txt`**

```
fastapi==0.115.0
uvicorn[standard]==0.30.6
sqlalchemy==2.0.35
alembic==1.13.3
psycopg2-binary==2.9.9
pydantic==2.8.2
pydantic-settings==2.5.2
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-multipart==0.0.12
httpx==0.27.2
pytest==8.3.3
pytest-asyncio==0.24.0
```

- [ ] **Step 5: Install dependencies**

```bash
pip install -r requirements.txt
```

Expected: all packages install without errors. This takes 1-3 minutes.

- [ ] **Step 6: Create `.env.example`**

```
DATABASE_URL=postgresql://postgres:yourpassword@localhost:5432/timetabling_db
TEST_DATABASE_URL=sqlite:///./test.db
JWT_SECRET_KEY=change-this-to-a-long-random-string-in-production
JWT_ALGORITHM=HS256
JWT_EXPIRE_MINUTES=1440
```

- [ ] **Step 7: Create your actual `.env` file (not committed to git)**

```bash
cp .env.example .env
```

Edit `.env` and replace `yourpassword` with your PostgreSQL password.

- [ ] **Step 8: Create the PostgreSQL database**

```bash
psql -U postgres -c "CREATE DATABASE timetabling_db;"
```

Expected output: `CREATE DATABASE`

- [ ] **Step 9: Create all empty `__init__.py` files**

```bash
mkdir -p app/models app/schemas app/routers app/core tests alembic/versions
touch app/__init__.py app/models/__init__.py app/schemas/__init__.py
touch app/routers/__init__.py app/core/__init__.py tests/__init__.py
```

- [ ] **Step 10: Set up .gitignore and commit**

Your GitHub repo is already created and cloned. The project directory is already a git repo — do NOT run `git init`. From the project root:

```bash
cd ..
echo "backend/venv/" >> .gitignore
echo "backend/.env" >> .gitignore
echo "backend/__pycache__/" >> .gitignore
echo "backend/**/*.pyc" >> .gitignore
echo "backend/test.db" >> .gitignore
git add .
```

> **Suggested commit message:** "feat: initialize backend project structure"

---

## Task 2: App Entry Point & Database Connection

**Files:**
- Create: `backend/app/config.py`
- Create: `backend/app/database.py`
- Create: `backend/app/main.py`

- [ ] **Step 1: Create `app/config.py`**

This file reads environment variables from your `.env` file. Pydantic-settings validates them automatically.

```python
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str
    test_database_url: str = "sqlite:///./test.db"
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 1440

    class Config:
        env_file = ".env"


settings = Settings()
```

- [ ] **Step 2: Create `app/database.py`**

```python
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase
from app.config import settings


engine = create_engine(settings.database_url)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

- [ ] **Step 3: Create `app/main.py`**

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="University Timetabling API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:8080", "http://localhost:8000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health_check():
    return {"status": "ok"}
```

- [ ] **Step 4: Start the server to confirm it works**

```bash
cd backend
source venv/Scripts/activate
uvicorn app.main:app --reload
```

Expected output:
```
INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
INFO:     Started reloader process
```

Open `http://127.0.0.1:8000/health` in your browser. You should see: `{"status":"ok"}`

Open `http://127.0.0.1:8000/docs` to see the interactive API documentation (this auto-generates from your code).

Press `CTRL+C` to stop the server.

- [ ] **Step 5: Commit checkpoint**

> **Suggested commit message:** "feat: add FastAPI app skeleton with database connection"

```bash
git add backend/app/config.py backend/app/database.py backend/app/main.py
```

---

## Task 3: SQLAlchemy Database Models

**Files:**
- Create: `backend/app/models/university.py`
- Create: `backend/app/models/room.py`
- Create: `backend/app/models/academic.py`
- Create: `backend/app/models/user.py`
- Create: `backend/app/models/course.py`
- Modify: `backend/app/models/__init__.py`

> All models are defined here before migrations. SQLAlchemy relationships require all models to be imported together — that is why `__init__.py` imports them all.

- [ ] **Step 1: Create `app/models/university.py`**

```python
from datetime import datetime
from sqlalchemy import String, Integer, Float, ForeignKey, DateTime
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class University(Base):
    __tablename__ = "universities"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(255))
    slug: Mapped[str] = mapped_column(String(100), unique=True)
    overflow_threshold: Mapped[float] = mapped_column(Float, default=0.20)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    faculties: Mapped[list["Faculty"]] = relationship(back_populates="university", cascade="all, delete-orphan")
    rooms: Mapped[list["Room"]] = relationship(back_populates="university", cascade="all, delete-orphan")
    semesters: Mapped[list["Semester"]] = relationship(back_populates="university", cascade="all, delete-orphan")
    users: Mapped[list["User"]] = relationship(back_populates="university")


class Faculty(Base):
    __tablename__ = "faculties"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(255))
    code: Mapped[str] = mapped_column(String(20))
    sessions_per_week: Mapped[int] = mapped_column(Integer, default=2)
    session_duration_hours: Mapped[int] = mapped_column(Integer, default=2)
    university_id: Mapped[int] = mapped_column(ForeignKey("universities.id"))

    university: Mapped["University"] = relationship(back_populates="faculties")
    departments: Mapped[list["Department"]] = relationship(back_populates="faculty", cascade="all, delete-orphan")


class Department(Base):
    __tablename__ = "departments"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(255))
    code: Mapped[str] = mapped_column(String(20))
    faculty_id: Mapped[int] = mapped_column(ForeignKey("faculties.id"))

    faculty: Mapped["Faculty"] = relationship(back_populates="departments")
    levels: Mapped[list["Level"]] = relationship(back_populates="department", cascade="all, delete-orphan")
    courses: Mapped[list["Course"]] = relationship(back_populates="department")
```

- [ ] **Step 2: Create `app/models/room.py`**

```python
from sqlalchemy import String, Integer, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class Room(Base):
    __tablename__ = "rooms"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100))
    capacity: Mapped[int] = mapped_column(Integer)
    room_type: Mapped[str] = mapped_column(String(20))  # lecture_hall | lab | studio
    university_id: Mapped[int] = mapped_column(ForeignKey("universities.id"))

    university: Mapped["University"] = relationship(back_populates="rooms")
```

- [ ] **Step 3: Create `app/models/academic.py`**

```python
from datetime import datetime, date, time
from typing import Optional
from sqlalchemy import String, Integer, Boolean, Date, Time, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class Level(Base):
    __tablename__ = "levels"

    id: Mapped[int] = mapped_column(primary_key=True)
    number: Mapped[int] = mapped_column(Integer)  # 100, 200, 300, 400, 500
    department_id: Mapped[int] = mapped_column(ForeignKey("departments.id"))

    department: Mapped["Department"] = relationship(back_populates="levels")
    classes: Mapped[list["Class"]] = relationship(back_populates="level", cascade="all, delete-orphan")


class Class(Base):
    __tablename__ = "classes"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(50))  # e.g. "EE300"
    population: Mapped[int] = mapped_column(Integer)
    level_id: Mapped[int] = mapped_column(ForeignKey("levels.id"))

    level: Mapped["Level"] = relationship(back_populates="classes")
    students: Mapped[list["Student"]] = relationship(back_populates="student_class")
    groups: Mapped[list["ClassGroup"]] = relationship(back_populates="student_class", cascade="all, delete-orphan")
    shared_courses: Mapped[list["SharedCourse"]] = relationship(back_populates="student_class")


class ClassGroup(Base):
    __tablename__ = "class_groups"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(10))  # "A", "B", "C"
    size: Mapped[int] = mapped_column(Integer)
    class_id: Mapped[int] = mapped_column(ForeignKey("classes.id"))
    course_id: Mapped[int] = mapped_column(ForeignKey("courses.id"))

    student_class: Mapped["Class"] = relationship(back_populates="groups")
    course: Mapped["Course"] = relationship(back_populates="groups")
    students: Mapped[list["Student"]] = relationship(back_populates="group")


class Semester(Base):
    __tablename__ = "semesters"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100))  # e.g. "First Semester 2025/2026"
    start_date: Mapped[date] = mapped_column(Date)
    end_date: Mapped[date] = mapped_column(Date)
    is_active: Mapped[bool] = mapped_column(Boolean, default=False)
    university_id: Mapped[int] = mapped_column(ForeignKey("universities.id"))

    university: Mapped["University"] = relationship(back_populates="semesters")
    time_slots: Mapped[list["TimeSlot"]] = relationship(back_populates="semester", cascade="all, delete-orphan")


class TimeSlot(Base):
    __tablename__ = "time_slots"

    id: Mapped[int] = mapped_column(primary_key=True)
    day_of_week: Mapped[str] = mapped_column(String(10))  # Monday, Tuesday, etc.
    start_time: Mapped[time] = mapped_column(Time)
    end_time: Mapped[time] = mapped_column(Time)
    semester_id: Mapped[int] = mapped_column(ForeignKey("semesters.id"))

    semester: Mapped["Semester"] = relationship(back_populates="time_slots")
```

- [ ] **Step 4: Create `app/models/user.py`**

```python
from datetime import datetime, time
from typing import Optional
from sqlalchemy import String, Integer, Boolean, DateTime, Time, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    full_name: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(30))
    # super_admin | university_admin | department_head | timetable_officer | lecturer | student
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    university_id: Mapped[Optional[int]] = mapped_column(ForeignKey("universities.id"), nullable=True)
    department_id: Mapped[Optional[int]] = mapped_column(ForeignKey("departments.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    university: Mapped[Optional["University"]] = relationship(back_populates="users")
    lecturer_profile: Mapped[Optional["Lecturer"]] = relationship(back_populates="user", uselist=False)
    student_profile: Mapped[Optional["Student"]] = relationship(back_populates="user", uselist=False)


class Lecturer(Base):
    __tablename__ = "lecturers"

    id: Mapped[int] = mapped_column(primary_key=True)
    staff_id: Mapped[str] = mapped_column(String(50), unique=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True)

    user: Mapped["User"] = relationship(back_populates="lecturer_profile")
    courses: Mapped[list["Course"]] = relationship(back_populates="lecturer")
    availability: Mapped[list["LecturerAvailability"]] = relationship(
        back_populates="lecturer", cascade="all, delete-orphan"
    )


class Student(Base):
    __tablename__ = "students"

    id: Mapped[int] = mapped_column(primary_key=True)
    matric_number: Mapped[str] = mapped_column(String(50), unique=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True)
    class_id: Mapped[int] = mapped_column(ForeignKey("classes.id"))
    group_id: Mapped[Optional[int]] = mapped_column(ForeignKey("class_groups.id"), nullable=True)

    user: Mapped["User"] = relationship(back_populates="student_profile")
    student_class: Mapped["Class"] = relationship(back_populates="students")
    group: Mapped[Optional["ClassGroup"]] = relationship(back_populates="students")


class LecturerAvailability(Base):
    __tablename__ = "lecturer_availability"

    id: Mapped[int] = mapped_column(primary_key=True)
    day_of_week: Mapped[str] = mapped_column(String(10))
    start_time: Mapped[time] = mapped_column(Time)
    end_time: Mapped[time] = mapped_column(Time)
    is_available: Mapped[bool] = mapped_column(Boolean, default=False)
    lecturer_id: Mapped[int] = mapped_column(ForeignKey("lecturers.id"))
    semester_id: Mapped[int] = mapped_column(ForeignKey("semesters.id"))

    lecturer: Mapped["Lecturer"] = relationship(back_populates="availability")
    semester: Mapped["Semester"] = relationship()
```

- [ ] **Step 5: Create `app/models/course.py`**

```python
from typing import Optional
from sqlalchemy import String, Integer, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class Course(Base):
    __tablename__ = "courses"

    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(String(20))  # e.g. "ENG 116"
    name: Mapped[str] = mapped_column(String(255))
    room_type_required: Mapped[str] = mapped_column(String(20), default="lecture_hall")
    # lecture_hall | lab | studio
    department_id: Mapped[int] = mapped_column(ForeignKey("departments.id"))
    lecturer_id: Mapped[Optional[int]] = mapped_column(ForeignKey("lecturers.id"), nullable=True)

    department: Mapped["Department"] = relationship(back_populates="courses")
    lecturer: Mapped[Optional["Lecturer"]] = relationship(back_populates="courses")
    groups: Mapped[list["ClassGroup"]] = relationship(back_populates="course")
    shared_with: Mapped[list["SharedCourse"]] = relationship(
        back_populates="course", cascade="all, delete-orphan"
    )


class SharedCourse(Base):
    __tablename__ = "shared_courses"

    id: Mapped[int] = mapped_column(primary_key=True)
    course_id: Mapped[int] = mapped_column(ForeignKey("courses.id"))
    class_id: Mapped[int] = mapped_column(ForeignKey("classes.id"))

    course: Mapped["Course"] = relationship(back_populates="shared_with")
    student_class: Mapped["Class"] = relationship(back_populates="shared_courses")
```

- [ ] **Step 6: Update `app/models/__init__.py` to import all models**

Importing all models in one place ensures SQLAlchemy can resolve all relationships correctly.

```python
from app.models.university import University, Faculty, Department
from app.models.room import Room
from app.models.academic import Level, Class, ClassGroup, Semester, TimeSlot
from app.models.user import User, Lecturer, Student, LecturerAvailability
from app.models.course import Course, SharedCourse
```

- [ ] **Step 7: Commit checkpoint**

> **Suggested commit message:** "feat: add all SQLAlchemy database models"

```bash
git add backend/app/models/
```

---

## Task 4: Alembic Migrations

**Files:**
- Create: `backend/alembic.ini`
- Create: `backend/alembic/env.py`

- [ ] **Step 1: Initialize Alembic**

```bash
cd backend
source venv/Scripts/activate
alembic init alembic
```

Expected: creates `alembic/` directory and `alembic.ini` file.

- [ ] **Step 2: Update `alembic.ini` to use your database URL**

Open `alembic.ini` and find the line:
```
sqlalchemy.url = driver://user:pass@localhost/dbname
```
Replace it with:
```
sqlalchemy.url = postgresql://postgres:yourpassword@localhost:5432/timetabling_db
```
Replace `yourpassword` with your actual PostgreSQL password.

- [ ] **Step 3: Update `alembic/env.py` to use your models' metadata**

Replace the entire content of `alembic/env.py` with:

```python
from logging.config import fileConfig
from sqlalchemy import engine_from_config, pool
from alembic import context
from app.database import Base
import app.models  # noqa: F401 — imports all models so Alembic can detect them

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(url=url, target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
```

- [ ] **Step 4: Generate the initial migration**

```bash
alembic revision --autogenerate -m "initial schema"
```

Expected: creates a file like `alembic/versions/xxxx_initial_schema.py`

- [ ] **Step 5: Apply the migration to create all tables**

```bash
alembic upgrade head
```

Expected output ends with: `INFO  [alembic.runtime.migration] Running upgrade -> xxxx, initial schema`

- [ ] **Step 6: Verify tables were created**

```bash
psql -U postgres -d timetabling_db -c "\dt"
```

Expected: lists all tables (universities, faculties, departments, rooms, levels, classes, class_groups, semesters, time_slots, users, lecturers, students, lecturer_availability, courses, shared_courses)

- [ ] **Step 7: Commit checkpoint**

> **Suggested commit message:** "feat: add Alembic migrations and create initial schema"

```bash
git add alembic/ alembic.ini
```

---

## Task 5: Test Infrastructure

**Files:**
- Create: `backend/tests/conftest.py`
- Create: `backend/tests/test_health.py`

- [ ] **Step 1: Create `tests/conftest.py`**

This sets up a fresh SQLite database for each test run, creates all tables, and provides a reusable `client` fixture.

```python
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.main import app
from app.database import Base, get_db
from app.config import settings

TEST_DATABASE_URL = "sqlite:///./test.db"
engine = create_engine(TEST_DATABASE_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


@pytest.fixture(scope="session", autouse=True)
def setup_database():
    import app.models  # noqa: F401 — ensures all models are registered
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)


@pytest.fixture
def db():
    connection = engine.connect()
    transaction = connection.begin()
    session = TestingSessionLocal(bind=connection)
    yield session
    session.close()
    transaction.rollback()
    connection.close()


@pytest.fixture
def client(db):
    def override():
        yield db

    app.dependency_overrides[get_db] = override
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
```

- [ ] **Step 2: Create `tests/test_health.py`**

```python
def test_health_check(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
```

- [ ] **Step 3: Run the test to confirm the infrastructure works**

```bash
cd backend
pytest tests/test_health.py -v
```

Expected:
```
PASSED tests/test_health.py::test_health_check
1 passed in X.XXs
```

- [ ] **Step 4: Commit checkpoint**

> **Suggested commit message:** "feat: add pytest test infrastructure with SQLite test database"

```bash
git add backend/tests/conftest.py backend/tests/test_health.py
```

---

## Task 6: JWT Authentication & Password Security

**Files:**
- Create: `backend/app/core/security.py`
- Create: `backend/app/core/auth.py`
- Create: `backend/app/schemas/user.py` (partial — auth schemas only)
- Create: `backend/app/routers/auth.py`
- Create: `backend/tests/test_auth.py`
- Modify: `backend/app/main.py`

- [ ] **Step 1: Create `app/core/security.py`**

```python
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)
```

- [ ] **Step 2: Create `app/core/auth.py`**

```python
from datetime import datetime, timedelta
from typing import Optional
from jose import JWTError, jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from app.config import settings
from app.database import get_db
from app.models.user import User

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=settings.jwt_expire_minutes)
    to_encode["exp"] = expire
    return jwt.encode(to_encode, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired token",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
        user_id: Optional[int] = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    user = db.query(User).filter(User.id == int(user_id)).first()
    if user is None or not user.is_active:
        raise credentials_exception
    return user
```

- [ ] **Step 3: Create `app/core/permissions.py`**

```python
from fastapi import Depends, HTTPException, status
from app.core.auth import get_current_user
from app.models.user import User

ROLE_HIERARCHY = {
    "super_admin": 6,
    "university_admin": 5,
    "department_head": 4,
    "timetable_officer": 3,
    "lecturer": 2,
    "student": 1,
}


def require_role(*allowed_roles: str):
    def dependency(current_user: User = Depends(get_current_user)) -> User:
        if current_user.role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Access denied. Required role: {' or '.join(allowed_roles)}",
            )
        return current_user

    return dependency


def require_min_role(min_role: str):
    def dependency(current_user: User = Depends(get_current_user)) -> User:
        if ROLE_HIERARCHY.get(current_user.role, 0) < ROLE_HIERARCHY.get(min_role, 0):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Access denied. Minimum required role: {min_role}",
            )
        return current_user

    return dependency
```

- [ ] **Step 4: Create auth schemas in `app/schemas/user.py`**

```python
from pydantic import BaseModel, EmailStr
from typing import Optional


class UserCreate(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    role: str
    university_id: Optional[int] = None
    department_id: Optional[int] = None


class UserResponse(BaseModel):
    id: int
    email: str
    full_name: str
    role: str
    is_active: bool
    university_id: Optional[int]
    department_id: Optional[int]

    model_config = {"from_attributes": True}


class LoginRequest(BaseModel):
    email: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse
```

- [ ] **Step 5: Create `app/routers/auth.py`**

```python
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.user import User
from app.schemas.user import UserCreate, UserResponse, LoginRequest, TokenResponse
from app.core.security import hash_password, verify_password
from app.core.auth import create_access_token, get_current_user

router = APIRouter(prefix="/auth", tags=["Authentication"])

VALID_ROLES = {
    "super_admin", "university_admin", "department_head",
    "timetable_officer", "lecturer", "student"
}


@router.post("/register", response_model=UserResponse, status_code=201)
def register(data: UserCreate, db: Session = Depends(get_db)):
    if data.role not in VALID_ROLES:
        raise HTTPException(status_code=400, detail=f"Invalid role. Choose from: {VALID_ROLES}")
    if db.query(User).filter(User.email == data.email).first():
        raise HTTPException(status_code=400, detail="Email already registered")
    user = User(
        email=data.email,
        hashed_password=hash_password(data.password),
        full_name=data.full_name,
        role=data.role,
        university_id=data.university_id,
        department_id=data.department_id,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@router.post("/login", response_model=TokenResponse)
def login(data: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == data.email).first()
    if not user or not verify_password(data.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account is deactivated")
    token = create_access_token({"sub": str(user.id), "role": user.role})
    return TokenResponse(access_token=token, user=user)


@router.get("/me", response_model=UserResponse)
def get_me(current_user: User = Depends(get_current_user)):
    return current_user
```

- [ ] **Step 6: Register the auth router in `app/main.py`**

```python
from fastapi import FastAPI
from app.routers import auth

app = FastAPI(title="University Timetabling API", version="1.0.0")

app.include_router(auth.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
```

- [ ] **Step 7: Write `tests/test_auth.py`**

```python
import pytest


def test_register_user(client):
    response = client.post("/auth/register", json={
        "email": "admin@ub.cm",
        "password": "secret123",
        "full_name": "Super Admin",
        "role": "super_admin",
    })
    assert response.status_code == 201
    data = response.json()
    assert data["email"] == "admin@ub.cm"
    assert data["role"] == "super_admin"
    assert "password" not in data


def test_register_duplicate_email(client):
    client.post("/auth/register", json={
        "email": "dup@ub.cm", "password": "pass", "full_name": "A", "role": "student"
    })
    response = client.post("/auth/register", json={
        "email": "dup@ub.cm", "password": "pass", "full_name": "B", "role": "student"
    })
    assert response.status_code == 400
    assert "already registered" in response.json()["detail"]


def test_register_invalid_role(client):
    response = client.post("/auth/register", json={
        "email": "x@ub.cm", "password": "pass", "full_name": "X", "role": "god"
    })
    assert response.status_code == 400


def test_login_success(client):
    client.post("/auth/register", json={
        "email": "login@ub.cm", "password": "secret123", "full_name": "Login User", "role": "lecturer"
    })
    response = client.post("/auth/login", json={"email": "login@ub.cm", "password": "secret123"})
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"
    assert data["user"]["email"] == "login@ub.cm"


def test_login_wrong_password(client):
    client.post("/auth/register", json={
        "email": "wrong@ub.cm", "password": "correct", "full_name": "W", "role": "student"
    })
    response = client.post("/auth/login", json={"email": "wrong@ub.cm", "password": "wrong"})
    assert response.status_code == 401


def test_get_me_with_valid_token(client):
    client.post("/auth/register", json={
        "email": "me@ub.cm", "password": "pass123", "full_name": "Me", "role": "lecturer"
    })
    login_resp = client.post("/auth/login", json={"email": "me@ub.cm", "password": "pass123"})
    token = login_resp.json()["access_token"]
    response = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.json()["email"] == "me@ub.cm"


def test_get_me_without_token(client):
    response = client.get("/auth/me")
    assert response.status_code == 401
```

- [ ] **Step 8: Run the tests**

```bash
pytest tests/test_auth.py -v
```

Expected: 7 tests pass.

- [ ] **Step 9: Commit checkpoint**

> **Suggested commit message:** "feat: add JWT authentication with role-based access control"

```bash
git add backend/app/core/ backend/app/schemas/user.py backend/app/routers/auth.py backend/app/main.py backend/tests/test_auth.py
```

---

## Task 7: University CRUD API

**Files:**
- Create: `backend/app/schemas/university.py`
- Create: `backend/app/routers/universities.py`
- Create: `backend/tests/test_universities.py`
- Modify: `backend/app/main.py`

- [ ] **Step 1: Write the failing tests first — `tests/test_universities.py`**

```python
import pytest


def get_admin_token(client):
    client.post("/auth/register", json={
        "email": "superadmin@ub.cm", "password": "admin123",
        "full_name": "Super Admin", "role": "super_admin"
    })
    resp = client.post("/auth/login", json={"email": "superadmin@ub.cm", "password": "admin123"})
    return resp.json()["access_token"]


def get_student_token(client):
    client.post("/auth/register", json={
        "email": "student@ub.cm", "password": "pass123",
        "full_name": "Student", "role": "student"
    })
    resp = client.post("/auth/login", json={"email": "student@ub.cm", "password": "pass123"})
    return resp.json()["access_token"]


def test_create_university(client):
    token = get_admin_token(client)
    response = client.post("/universities/", json={
        "name": "University of Buea", "slug": "ub", "overflow_threshold": 0.20
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "University of Buea"
    assert data["slug"] == "ub"


def test_create_university_forbidden_for_student(client):
    token = get_student_token(client)
    response = client.post("/universities/", json={
        "name": "Fake Uni", "slug": "fake"
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 403


def test_list_universities(client):
    token = get_admin_token(client)
    client.post("/universities/", json={"name": "Uni A", "slug": "uni-a"},
                headers={"Authorization": f"Bearer {token}"})
    response = client.get("/universities/", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_get_university_by_id(client):
    token = get_admin_token(client)
    created = client.post("/universities/", json={"name": "Uni B", "slug": "uni-b"},
                          headers={"Authorization": f"Bearer {token}"}).json()
    response = client.get(f"/universities/{created['id']}", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.json()["slug"] == "uni-b"


def test_get_university_not_found(client):
    token = get_admin_token(client)
    response = client.get("/universities/99999", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 404


def test_update_university(client):
    token = get_admin_token(client)
    created = client.post("/universities/", json={"name": "Old Name", "slug": "old-slug"},
                          headers={"Authorization": f"Bearer {token}"}).json()
    response = client.put(f"/universities/{created['id']}", json={"name": "New Name"},
                          headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.json()["name"] == "New Name"


def test_delete_university(client):
    token = get_admin_token(client)
    created = client.post("/universities/", json={"name": "To Delete", "slug": "to-delete"},
                          headers={"Authorization": f"Bearer {token}"}).json()
    response = client.delete(f"/universities/{created['id']}", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 204
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
pytest tests/test_universities.py -v
```

Expected: errors like `404 Not Found` or `connection refused` — the endpoints don't exist yet.

- [ ] **Step 3: Create `app/schemas/university.py`**

```python
from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class UniversityCreate(BaseModel):
    name: str
    slug: str
    overflow_threshold: float = 0.20


class UniversityUpdate(BaseModel):
    name: Optional[str] = None
    slug: Optional[str] = None
    overflow_threshold: Optional[float] = None


class UniversityResponse(BaseModel):
    id: int
    name: str
    slug: str
    overflow_threshold: float
    created_at: datetime

    model_config = {"from_attributes": True}


class FacultyCreate(BaseModel):
    name: str
    code: str
    sessions_per_week: int = 2
    session_duration_hours: int = 2
    university_id: int


class FacultyUpdate(BaseModel):
    name: Optional[str] = None
    code: Optional[str] = None
    sessions_per_week: Optional[int] = None
    session_duration_hours: Optional[int] = None


class FacultyResponse(BaseModel):
    id: int
    name: str
    code: str
    sessions_per_week: int
    session_duration_hours: int
    university_id: int

    model_config = {"from_attributes": True}


class DepartmentCreate(BaseModel):
    name: str
    code: str
    faculty_id: int


class DepartmentUpdate(BaseModel):
    name: Optional[str] = None
    code: Optional[str] = None


class DepartmentResponse(BaseModel):
    id: int
    name: str
    code: str
    faculty_id: int

    model_config = {"from_attributes": True}
```

- [ ] **Step 4: Create `app/routers/universities.py`**

```python
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.university import University
from app.schemas.university import UniversityCreate, UniversityUpdate, UniversityResponse
from app.core.auth import get_current_user
from app.core.permissions import require_role
from app.models.user import User

router = APIRouter(prefix="/universities", tags=["Universities"])


@router.post("/", response_model=UniversityResponse, status_code=201)
def create_university(
    data: UniversityCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_role("super_admin")),
):
    if db.query(University).filter(University.slug == data.slug).first():
        raise HTTPException(status_code=400, detail="Slug already in use")
    university = University(**data.model_dump())
    db.add(university)
    db.commit()
    db.refresh(university)
    return university


@router.get("/", response_model=list[UniversityResponse])
def list_universities(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    return db.query(University).all()


@router.get("/{university_id}", response_model=UniversityResponse)
def get_university(
    university_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    university = db.query(University).filter(University.id == university_id).first()
    if not university:
        raise HTTPException(status_code=404, detail="University not found")
    return university


@router.put("/{university_id}", response_model=UniversityResponse)
def update_university(
    university_id: int,
    data: UniversityUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_role("super_admin")),
):
    university = db.query(University).filter(University.id == university_id).first()
    if not university:
        raise HTTPException(status_code=404, detail="University not found")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(university, key, value)
    db.commit()
    db.refresh(university)
    return university


@router.delete("/{university_id}", status_code=204)
def delete_university(
    university_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_role("super_admin")),
):
    university = db.query(University).filter(University.id == university_id).first()
    if not university:
        raise HTTPException(status_code=404, detail="University not found")
    db.delete(university)
    db.commit()
```

- [ ] **Step 5: Register the router in `app/main.py`**

```python
from fastapi import FastAPI
from app.routers import auth, universities

app = FastAPI(title="University Timetabling API", version="1.0.0")

app.include_router(auth.router)
app.include_router(universities.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
```

- [ ] **Step 6: Run the tests**

```bash
pytest tests/test_universities.py -v
```

Expected: all 7 tests pass.

- [ ] **Step 7: Commit checkpoint**

> **Suggested commit message:** "feat: add University CRUD API with role-based access"

```bash
git add backend/app/schemas/university.py backend/app/routers/universities.py backend/app/main.py backend/tests/test_universities.py
```

---

## Task 8: Faculty & Department CRUD APIs

**Files:**
- Create: `backend/app/routers/faculties.py`
- Create: `backend/app/routers/departments.py`
- Create: `backend/tests/test_faculties.py`
- Create: `backend/tests/test_departments.py`
- Modify: `backend/app/main.py`

- [ ] **Step 1: Write `tests/test_faculties.py`**

```python
def get_admin_token(client):
    client.post("/auth/register", json={
        "email": "fadmin@ub.cm", "password": "admin123",
        "full_name": "Admin", "role": "super_admin"
    })
    resp = client.post("/auth/login", json={"email": "fadmin@ub.cm", "password": "admin123"})
    return resp.json()["access_token"]


def create_university(client, token):
    return client.post("/universities/", json={"name": "UB", "slug": "ub-fac"},
                       headers={"Authorization": f"Bearer {token}"}).json()


def test_create_faculty(client):
    token = get_admin_token(client)
    uni = create_university(client, token)
    response = client.post("/faculties/", json={
        "name": "Faculty of Engineering", "code": "FET",
        "sessions_per_week": 2, "session_duration_hours": 2, "university_id": uni["id"]
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 201
    assert response.json()["code"] == "FET"


def test_list_faculties(client):
    token = get_admin_token(client)
    uni = create_university(client, token)
    client.post("/faculties/", json={"name": "Sci", "code": "SCI", "university_id": uni["id"]},
                headers={"Authorization": f"Bearer {token}"})
    response = client.get("/faculties/", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_update_faculty(client):
    token = get_admin_token(client)
    uni = create_university(client, token)
    faculty = client.post("/faculties/", json={
        "name": "Old", "code": "OLD", "university_id": uni["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    response = client.put(f"/faculties/{faculty['id']}", json={"sessions_per_week": 3},
                          headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.json()["sessions_per_week"] == 3


def test_delete_faculty(client):
    token = get_admin_token(client)
    uni = create_university(client, token)
    faculty = client.post("/faculties/", json={
        "name": "Del", "code": "DEL", "university_id": uni["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    response = client.delete(f"/faculties/{faculty['id']}", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 204
```

- [ ] **Step 2: Write `tests/test_departments.py`**

```python
def get_admin_token(client):
    client.post("/auth/register", json={
        "email": "dadmin@ub.cm", "password": "admin123",
        "full_name": "Admin", "role": "super_admin"
    })
    resp = client.post("/auth/login", json={"email": "dadmin@ub.cm", "password": "admin123"})
    return resp.json()["access_token"]


def create_faculty(client, token):
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub-dept"},
                      headers={"Authorization": f"Bearer {token}"}).json()
    return client.post("/faculties/", json={
        "name": "FET", "code": "FET", "university_id": uni["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()


def test_create_department(client):
    token = get_admin_token(client)
    faculty = create_faculty(client, token)
    response = client.post("/departments/", json={
        "name": "Electrical Engineering", "code": "EE", "faculty_id": faculty["id"]
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 201
    assert response.json()["code"] == "EE"


def test_list_departments(client):
    token = get_admin_token(client)
    faculty = create_faculty(client, token)
    client.post("/departments/", json={"name": "CE", "code": "CE", "faculty_id": faculty["id"]},
                headers={"Authorization": f"Bearer {token}"})
    response = client.get("/departments/", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_update_department(client):
    token = get_admin_token(client)
    faculty = create_faculty(client, token)
    dept = client.post("/departments/", json={
        "name": "Old Dept", "code": "OLD", "faculty_id": faculty["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    response = client.put(f"/departments/{dept['id']}", json={"name": "New Dept"},
                          headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.json()["name"] == "New Dept"


def test_delete_department(client):
    token = get_admin_token(client)
    faculty = create_faculty(client, token)
    dept = client.post("/departments/", json={
        "name": "Del", "code": "D", "faculty_id": faculty["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    response = client.delete(f"/departments/{dept['id']}", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 204
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
pytest tests/test_faculties.py tests/test_departments.py -v
```

Expected: failures — endpoints don't exist yet.

- [ ] **Step 4: Create `app/routers/faculties.py`**

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.university import Faculty
from app.schemas.university import FacultyCreate, FacultyUpdate, FacultyResponse
from app.core.auth import get_current_user
from app.core.permissions import require_min_role
from app.models.user import User

router = APIRouter(prefix="/faculties", tags=["Faculties"])


@router.post("/", response_model=FacultyResponse, status_code=201)
def create_faculty(
    data: FacultyCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("university_admin")),
):
    faculty = Faculty(**data.model_dump())
    db.add(faculty)
    db.commit()
    db.refresh(faculty)
    return faculty


@router.get("/", response_model=list[FacultyResponse])
def list_faculties(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    return db.query(Faculty).all()


@router.get("/{faculty_id}", response_model=FacultyResponse)
def get_faculty(faculty_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    faculty = db.query(Faculty).filter(Faculty.id == faculty_id).first()
    if not faculty:
        raise HTTPException(status_code=404, detail="Faculty not found")
    return faculty


@router.put("/{faculty_id}", response_model=FacultyResponse)
def update_faculty(
    faculty_id: int,
    data: FacultyUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("department_head")),
):
    faculty = db.query(Faculty).filter(Faculty.id == faculty_id).first()
    if not faculty:
        raise HTTPException(status_code=404, detail="Faculty not found")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(faculty, key, value)
    db.commit()
    db.refresh(faculty)
    return faculty


@router.delete("/{faculty_id}", status_code=204)
def delete_faculty(
    faculty_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("university_admin")),
):
    faculty = db.query(Faculty).filter(Faculty.id == faculty_id).first()
    if not faculty:
        raise HTTPException(status_code=404, detail="Faculty not found")
    db.delete(faculty)
    db.commit()
```

- [ ] **Step 5: Create `app/routers/departments.py`**

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.university import Department
from app.schemas.university import DepartmentCreate, DepartmentUpdate, DepartmentResponse
from app.core.auth import get_current_user
from app.core.permissions import require_min_role
from app.models.user import User

router = APIRouter(prefix="/departments", tags=["Departments"])


@router.post("/", response_model=DepartmentResponse, status_code=201)
def create_department(
    data: DepartmentCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("university_admin")),
):
    department = Department(**data.model_dump())
    db.add(department)
    db.commit()
    db.refresh(department)
    return department


@router.get("/", response_model=list[DepartmentResponse])
def list_departments(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    return db.query(Department).all()


@router.get("/{department_id}", response_model=DepartmentResponse)
def get_department(department_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    department = db.query(Department).filter(Department.id == department_id).first()
    if not department:
        raise HTTPException(status_code=404, detail="Department not found")
    return department


@router.put("/{department_id}", response_model=DepartmentResponse)
def update_department(
    department_id: int,
    data: DepartmentUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("department_head")),
):
    department = db.query(Department).filter(Department.id == department_id).first()
    if not department:
        raise HTTPException(status_code=404, detail="Department not found")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(department, key, value)
    db.commit()
    db.refresh(department)
    return department


@router.delete("/{department_id}", status_code=204)
def delete_department(
    department_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("university_admin")),
):
    department = db.query(Department).filter(Department.id == department_id).first()
    if not department:
        raise HTTPException(status_code=404, detail="Department not found")
    db.delete(department)
    db.commit()
```

- [ ] **Step 6: Register routers in `app/main.py`**

```python
from fastapi import FastAPI
from app.routers import auth, universities, faculties, departments

app = FastAPI(title="University Timetabling API", version="1.0.0")

app.include_router(auth.router)
app.include_router(universities.router)
app.include_router(faculties.router)
app.include_router(departments.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
```

- [ ] **Step 7: Run all tests**

```bash
pytest tests/test_faculties.py tests/test_departments.py -v
```

Expected: all tests pass.

- [ ] **Step 8: Commit checkpoint**

> **Suggested commit message:** "feat: add Faculty and Department CRUD APIs"

```bash
git add backend/app/routers/faculties.py backend/app/routers/departments.py backend/app/main.py backend/tests/test_faculties.py backend/tests/test_departments.py
```

---

## Task 9: Room CRUD API

**Files:**
- Create: `backend/app/schemas/room.py`
- Create: `backend/app/routers/rooms.py`
- Create: `backend/tests/test_rooms.py`
- Modify: `backend/app/main.py`

- [ ] **Step 1: Write `tests/test_rooms.py`**

```python
VALID_ROOM_TYPES = ["lecture_hall", "lab", "studio"]


def get_admin_token(client):
    client.post("/auth/register", json={
        "email": "roomadmin@ub.cm", "password": "admin123",
        "full_name": "Admin", "role": "super_admin"
    })
    resp = client.post("/auth/login", json={"email": "roomadmin@ub.cm", "password": "admin123"})
    return resp.json()["access_token"]


def create_university(client, token):
    return client.post("/universities/", json={"name": "UB Rooms", "slug": "ub-rooms"},
                       headers={"Authorization": f"Bearer {token}"}).json()


def test_create_room(client):
    token = get_admin_token(client)
    uni = create_university(client, token)
    response = client.post("/rooms/", json={
        "name": "Amphi A", "capacity": 700, "room_type": "lecture_hall", "university_id": uni["id"]
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Amphi A"
    assert data["capacity"] == 700


def test_create_room_invalid_type(client):
    token = get_admin_token(client)
    uni = create_university(client, token)
    response = client.post("/rooms/", json={
        "name": "Bad Room", "capacity": 50, "room_type": "gym", "university_id": uni["id"]
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 400


def test_list_rooms(client):
    token = get_admin_token(client)
    response = client.get("/rooms/", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_update_room_capacity(client):
    token = get_admin_token(client)
    uni = create_university(client, token)
    room = client.post("/rooms/", json={
        "name": "Lab 1", "capacity": 30, "room_type": "lab", "university_id": uni["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    response = client.put(f"/rooms/{room['id']}", json={"capacity": 40},
                          headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.json()["capacity"] == 40


def test_delete_room(client):
    token = get_admin_token(client)
    uni = create_university(client, token)
    room = client.post("/rooms/", json={
        "name": "To Del", "capacity": 20, "room_type": "studio", "university_id": uni["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    response = client.delete(f"/rooms/{room['id']}", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 204
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
pytest tests/test_rooms.py -v
```

Expected: failures.

- [ ] **Step 3: Create `app/schemas/room.py`**

```python
from typing import Optional
from pydantic import BaseModel, field_validator

VALID_ROOM_TYPES = {"lecture_hall", "lab", "studio"}


class RoomCreate(BaseModel):
    name: str
    capacity: int
    room_type: str
    university_id: int

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

    @field_validator("room_type")
    @classmethod
    def validate_room_type(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in VALID_ROOM_TYPES:
            raise ValueError(f"room_type must be one of: {VALID_ROOM_TYPES}")
        return v


class RoomResponse(BaseModel):
    id: int
    name: str
    capacity: int
    room_type: str
    university_id: int

    model_config = {"from_attributes": True}
```

- [ ] **Step 4: Create `app/routers/rooms.py`**

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.room import Room
from app.schemas.room import RoomCreate, RoomUpdate, RoomResponse
from app.core.auth import get_current_user
from app.core.permissions import require_min_role
from app.models.user import User

router = APIRouter(prefix="/rooms", tags=["Rooms"])


@router.post("/", response_model=RoomResponse, status_code=201)
def create_room(
    data: RoomCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("university_admin")),
):
    room = Room(**data.model_dump())
    db.add(room)
    db.commit()
    db.refresh(room)
    return room


@router.get("/", response_model=list[RoomResponse])
def list_rooms(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    return db.query(Room).all()


@router.get("/{room_id}", response_model=RoomResponse)
def get_room(room_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    room = db.query(Room).filter(Room.id == room_id).first()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    return room


@router.put("/{room_id}", response_model=RoomResponse)
def update_room(
    room_id: int,
    data: RoomUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("university_admin")),
):
    room = db.query(Room).filter(Room.id == room_id).first()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(room, key, value)
    db.commit()
    db.refresh(room)
    return room


@router.delete("/{room_id}", status_code=204)
def delete_room(
    room_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("university_admin")),
):
    room = db.query(Room).filter(Room.id == room_id).first()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    db.delete(room)
    db.commit()
```

- [ ] **Step 5: Register router in `app/main.py`**

```python
from fastapi import FastAPI
from app.routers import auth, universities, faculties, departments, rooms

app = FastAPI(title="University Timetabling API", version="1.0.0")

app.include_router(auth.router)
app.include_router(universities.router)
app.include_router(faculties.router)
app.include_router(departments.router)
app.include_router(rooms.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
```

- [ ] **Step 6: Run tests**

```bash
pytest tests/test_rooms.py -v
```

Expected: all tests pass.

- [ ] **Step 7: Commit checkpoint**

> **Suggested commit message:** "feat: add Room CRUD API with room type validation"

```bash
git add backend/app/schemas/room.py backend/app/routers/rooms.py backend/app/main.py backend/tests/test_rooms.py
```

---

## Task 10: Semester, TimeSlot & Academic Structure APIs

**Files:**
- Create: `backend/app/schemas/academic.py`
- Create: `backend/app/routers/semesters.py`
- Create: `backend/app/routers/academic.py`
- Create: `backend/tests/test_semesters.py`
- Create: `backend/tests/test_academic.py`
- Modify: `backend/app/main.py`

- [ ] **Step 1: Write `tests/test_semesters.py`**

```python
def get_admin_token(client):
    client.post("/auth/register", json={
        "email": "semadmin@ub.cm", "password": "admin123",
        "full_name": "Admin", "role": "super_admin"
    })
    resp = client.post("/auth/login", json={"email": "semadmin@ub.cm", "password": "admin123"})
    return resp.json()["access_token"]


def create_university(client, token):
    return client.post("/universities/", json={"name": "UB Sem", "slug": "ub-sem"},
                       headers={"Authorization": f"Bearer {token}"}).json()


def test_create_semester(client):
    token = get_admin_token(client)
    uni = create_university(client, token)
    response = client.post("/semesters/", json={
        "name": "First Semester 2025/2026",
        "start_date": "2025-09-01",
        "end_date": "2026-01-31",
        "university_id": uni["id"]
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 201
    assert response.json()["name"] == "First Semester 2025/2026"


def test_add_timeslot_to_semester(client):
    token = get_admin_token(client)
    uni = create_university(client, token)
    semester = client.post("/semesters/", json={
        "name": "S1", "start_date": "2025-09-01", "end_date": "2026-01-31", "university_id": uni["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    response = client.post("/semesters/timeslots/", json={
        "day_of_week": "Monday", "start_time": "07:00", "end_time": "09:00",
        "semester_id": semester["id"]
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 201
    assert response.json()["day_of_week"] == "Monday"


def test_list_timeslots_by_semester(client):
    token = get_admin_token(client)
    uni = create_university(client, token)
    semester = client.post("/semesters/", json={
        "name": "S2", "start_date": "2025-09-01", "end_date": "2026-01-31", "university_id": uni["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    client.post("/semesters/timeslots/", json={
        "day_of_week": "Tuesday", "start_time": "09:00", "end_time": "11:00",
        "semester_id": semester["id"]
    }, headers={"Authorization": f"Bearer {token}"})
    response = client.get(f"/semesters/{semester['id']}/timeslots",
                          headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert len(response.json()) >= 1
```

- [ ] **Step 2: Write `tests/test_academic.py`**

```python
def get_admin_token(client):
    client.post("/auth/register", json={
        "email": "acadmin@ub.cm", "password": "admin123",
        "full_name": "Admin", "role": "super_admin"
    })
    resp = client.post("/auth/login", json={"email": "acadmin@ub.cm", "password": "admin123"})
    return resp.json()["access_token"]


def setup_department(client, token):
    uni = client.post("/universities/", json={"name": "UB Ac", "slug": "ub-ac"},
                      headers={"Authorization": f"Bearer {token}"}).json()
    faculty = client.post("/faculties/", json={"name": "FET", "code": "FET", "university_id": uni["id"]},
                          headers={"Authorization": f"Bearer {token}"}).json()
    return client.post("/departments/", json={"name": "EE", "code": "EE", "faculty_id": faculty["id"]},
                       headers={"Authorization": f"Bearer {token}"}).json()


def test_create_level(client):
    token = get_admin_token(client)
    dept = setup_department(client, token)
    response = client.post("/levels/", json={"number": 300, "department_id": dept["id"]},
                           headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 201
    assert response.json()["number"] == 300


def test_create_class(client):
    token = get_admin_token(client)
    dept = setup_department(client, token)
    level = client.post("/levels/", json={"number": 300, "department_id": dept["id"]},
                        headers={"Authorization": f"Bearer {token}"}).json()
    response = client.post("/classes/", json={
        "name": "EE300", "population": 120, "level_id": level["id"]
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 201
    assert response.json()["name"] == "EE300"
    assert response.json()["population"] == 120


def test_list_classes(client):
    token = get_admin_token(client)
    response = client.get("/classes/", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert isinstance(response.json(), list)
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
pytest tests/test_semesters.py tests/test_academic.py -v
```

Expected: failures.

- [ ] **Step 4: Create `app/schemas/academic.py`**

```python
from datetime import date, time
from typing import Optional
from pydantic import BaseModel


class SemesterCreate(BaseModel):
    name: str
    start_date: date
    end_date: date
    university_id: int


class SemesterUpdate(BaseModel):
    name: Optional[str] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    is_active: Optional[bool] = None


class SemesterResponse(BaseModel):
    id: int
    name: str
    start_date: date
    end_date: date
    is_active: bool
    university_id: int

    model_config = {"from_attributes": True}


class TimeSlotCreate(BaseModel):
    day_of_week: str
    start_time: time
    end_time: time
    semester_id: int


class TimeSlotResponse(BaseModel):
    id: int
    day_of_week: str
    start_time: time
    end_time: time
    semester_id: int

    model_config = {"from_attributes": True}


class LevelCreate(BaseModel):
    number: int
    department_id: int


class LevelResponse(BaseModel):
    id: int
    number: int
    department_id: int

    model_config = {"from_attributes": True}


class ClassCreate(BaseModel):
    name: str
    population: int
    level_id: int


class ClassUpdate(BaseModel):
    name: Optional[str] = None
    population: Optional[int] = None


class ClassResponse(BaseModel):
    id: int
    name: str
    population: int
    level_id: int

    model_config = {"from_attributes": True}


class ClassGroupCreate(BaseModel):
    name: str
    size: int
    class_id: int
    course_id: int


class ClassGroupUpdate(BaseModel):
    name: Optional[str] = None
    size: Optional[int] = None


class ClassGroupResponse(BaseModel):
    id: int
    name: str
    size: int
    class_id: int
    course_id: int

    model_config = {"from_attributes": True}
```

- [ ] **Step 5: Create `app/routers/semesters.py`**

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.academic import Semester, TimeSlot
from app.schemas.academic import (
    SemesterCreate, SemesterUpdate, SemesterResponse,
    TimeSlotCreate, TimeSlotResponse,
)
from app.core.auth import get_current_user
from app.core.permissions import require_min_role
from app.models.user import User

router = APIRouter(tags=["Semesters"])


@router.post("/semesters/", response_model=SemesterResponse, status_code=201)
def create_semester(
    data: SemesterCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("university_admin")),
):
    semester = Semester(**data.model_dump())
    db.add(semester)
    db.commit()
    db.refresh(semester)
    return semester


@router.get("/semesters/", response_model=list[SemesterResponse])
def list_semesters(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    return db.query(Semester).all()


@router.get("/semesters/{semester_id}", response_model=SemesterResponse)
def get_semester(semester_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    semester = db.query(Semester).filter(Semester.id == semester_id).first()
    if not semester:
        raise HTTPException(status_code=404, detail="Semester not found")
    return semester


@router.put("/semesters/{semester_id}", response_model=SemesterResponse)
def update_semester(
    semester_id: int,
    data: SemesterUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("university_admin")),
):
    semester = db.query(Semester).filter(Semester.id == semester_id).first()
    if not semester:
        raise HTTPException(status_code=404, detail="Semester not found")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(semester, key, value)
    db.commit()
    db.refresh(semester)
    return semester


@router.delete("/semesters/{semester_id}", status_code=204)
def delete_semester(
    semester_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("university_admin")),
):
    semester = db.query(Semester).filter(Semester.id == semester_id).first()
    if not semester:
        raise HTTPException(status_code=404, detail="Semester not found")
    db.delete(semester)
    db.commit()


@router.post("/semesters/timeslots/", response_model=TimeSlotResponse, status_code=201)
def create_timeslot(
    data: TimeSlotCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("university_admin")),
):
    timeslot = TimeSlot(**data.model_dump())
    db.add(timeslot)
    db.commit()
    db.refresh(timeslot)
    return timeslot


@router.get("/semesters/{semester_id}/timeslots", response_model=list[TimeSlotResponse])
def list_timeslots(
    semester_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    return db.query(TimeSlot).filter(TimeSlot.semester_id == semester_id).all()


@router.delete("/semesters/timeslots/{timeslot_id}", status_code=204)
def delete_timeslot(
    timeslot_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("university_admin")),
):
    timeslot = db.query(TimeSlot).filter(TimeSlot.id == timeslot_id).first()
    if not timeslot:
        raise HTTPException(status_code=404, detail="TimeSlot not found")
    db.delete(timeslot)
    db.commit()
```

- [ ] **Step 6: Create `app/routers/academic.py`**

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.academic import Level, Class, ClassGroup
from app.schemas.academic import (
    LevelCreate, LevelResponse,
    ClassCreate, ClassUpdate, ClassResponse,
    ClassGroupCreate, ClassGroupUpdate, ClassGroupResponse,
)
from app.core.auth import get_current_user
from app.core.permissions import require_min_role
from app.models.user import User

router = APIRouter(tags=["Academic Structure"])


@router.post("/levels/", response_model=LevelResponse, status_code=201)
def create_level(
    data: LevelCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    level = Level(**data.model_dump())
    db.add(level)
    db.commit()
    db.refresh(level)
    return level


@router.get("/levels/", response_model=list[LevelResponse])
def list_levels(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    return db.query(Level).all()


@router.delete("/levels/{level_id}", status_code=204)
def delete_level(
    level_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("university_admin")),
):
    level = db.query(Level).filter(Level.id == level_id).first()
    if not level:
        raise HTTPException(status_code=404, detail="Level not found")
    db.delete(level)
    db.commit()


@router.post("/classes/", response_model=ClassResponse, status_code=201)
def create_class(
    data: ClassCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    student_class = Class(**data.model_dump())
    db.add(student_class)
    db.commit()
    db.refresh(student_class)
    return student_class


@router.get("/classes/", response_model=list[ClassResponse])
def list_classes(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    return db.query(Class).all()


@router.get("/classes/{class_id}", response_model=ClassResponse)
def get_class(class_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    student_class = db.query(Class).filter(Class.id == class_id).first()
    if not student_class:
        raise HTTPException(status_code=404, detail="Class not found")
    return student_class


@router.put("/classes/{class_id}", response_model=ClassResponse)
def update_class(
    class_id: int,
    data: ClassUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    student_class = db.query(Class).filter(Class.id == class_id).first()
    if not student_class:
        raise HTTPException(status_code=404, detail="Class not found")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(student_class, key, value)
    db.commit()
    db.refresh(student_class)
    return student_class


@router.delete("/classes/{class_id}", status_code=204)
def delete_class(
    class_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    student_class = db.query(Class).filter(Class.id == class_id).first()
    if not student_class:
        raise HTTPException(status_code=404, detail="Class not found")
    db.delete(student_class)
    db.commit()


@router.post("/groups/", response_model=ClassGroupResponse, status_code=201)
def create_group(
    data: ClassGroupCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    group = ClassGroup(**data.model_dump())
    db.add(group)
    db.commit()
    db.refresh(group)
    return group


@router.get("/groups/", response_model=list[ClassGroupResponse])
def list_groups(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    return db.query(ClassGroup).all()


@router.put("/groups/{group_id}", response_model=ClassGroupResponse)
def update_group(
    group_id: int,
    data: ClassGroupUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    group = db.query(ClassGroup).filter(ClassGroup.id == group_id).first()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(group, key, value)
    db.commit()
    db.refresh(group)
    return group


@router.delete("/groups/{group_id}", status_code=204)
def delete_group(
    group_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    group = db.query(ClassGroup).filter(ClassGroup.id == group_id).first()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")
    db.delete(group)
    db.commit()
```

- [ ] **Step 7: Register routers in `app/main.py`**

```python
from fastapi import FastAPI
from app.routers import auth, universities, faculties, departments, rooms, semesters, academic

app = FastAPI(title="University Timetabling API", version="1.0.0")

app.include_router(auth.router)
app.include_router(universities.router)
app.include_router(faculties.router)
app.include_router(departments.router)
app.include_router(rooms.router)
app.include_router(semesters.router)
app.include_router(academic.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
```

- [ ] **Step 8: Run all tests**

```bash
pytest tests/test_semesters.py tests/test_academic.py -v
```

Expected: all tests pass.

- [ ] **Step 9: Commit checkpoint**

> **Suggested commit message:** "feat: add Semester, TimeSlot, Level, Class, and ClassGroup APIs"

```bash
git add backend/app/schemas/academic.py backend/app/routers/semesters.py backend/app/routers/academic.py backend/app/main.py backend/tests/test_semesters.py backend/tests/test_academic.py
```

---

## Task 11: Course & SharedCourse APIs

**Files:**
- Create: `backend/app/schemas/course.py`
- Create: `backend/app/routers/courses.py`
- Create: `backend/tests/test_courses.py`
- Modify: `backend/app/main.py`

- [ ] **Step 1: Write `tests/test_courses.py`**

```python
def get_admin_token(client):
    client.post("/auth/register", json={
        "email": "courseadmin@ub.cm", "password": "admin123",
        "full_name": "Admin", "role": "super_admin"
    })
    resp = client.post("/auth/login", json={"email": "courseadmin@ub.cm", "password": "admin123"})
    return resp.json()["access_token"]


def setup_department(client, token):
    uni = client.post("/universities/", json={"name": "UB Course", "slug": "ub-course"},
                      headers={"Authorization": f"Bearer {token}"}).json()
    faculty = client.post("/faculties/", json={"name": "FET", "code": "FET-C", "university_id": uni["id"]},
                          headers={"Authorization": f"Bearer {token}"}).json()
    return client.post("/departments/", json={"name": "EE", "code": "EE-C", "faculty_id": faculty["id"]},
                       headers={"Authorization": f"Bearer {token}"}).json()


def setup_class(client, token, dept):
    level = client.post("/levels/", json={"number": 300, "department_id": dept["id"]},
                        headers={"Authorization": f"Bearer {token}"}).json()
    return client.post("/classes/", json={"name": "EE300", "population": 120, "level_id": level["id"]},
                       headers={"Authorization": f"Bearer {token}"}).json()


def test_create_course(client):
    token = get_admin_token(client)
    dept = setup_department(client, token)
    response = client.post("/courses/", json={
        "code": "ENG 116", "name": "Technical Communication",
        "room_type_required": "lecture_hall", "department_id": dept["id"]
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 201
    assert response.json()["code"] == "ENG 116"


def test_create_course_requires_lab(client):
    token = get_admin_token(client)
    dept = setup_department(client, token)
    response = client.post("/courses/", json={
        "code": "EE LAB 201", "name": "Circuits Lab",
        "room_type_required": "lab", "department_id": dept["id"]
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 201
    assert response.json()["room_type_required"] == "lab"


def test_list_courses(client):
    token = get_admin_token(client)
    response = client.get("/courses/", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_add_shared_course(client):
    token = get_admin_token(client)
    dept = setup_department(client, token)
    course = client.post("/courses/", json={
        "code": "MTH 201", "name": "Mathematics", "department_id": dept["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    cls = setup_class(client, token, dept)
    response = client.post("/courses/shared/", json={
        "course_id": course["id"], "class_id": cls["id"]
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 201
    assert response.json()["course_id"] == course["id"]


def test_update_course(client):
    token = get_admin_token(client)
    dept = setup_department(client, token)
    course = client.post("/courses/", json={
        "code": "OLD 101", "name": "Old Course", "department_id": dept["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    response = client.put(f"/courses/{course['id']}", json={"name": "New Name"},
                          headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.json()["name"] == "New Name"


def test_delete_course(client):
    token = get_admin_token(client)
    dept = setup_department(client, token)
    course = client.post("/courses/", json={
        "code": "DEL 101", "name": "Del", "department_id": dept["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    response = client.delete(f"/courses/{course['id']}", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 204


def test_create_class_group(client):
    token = get_admin_token(client)
    dept = setup_department(client, token)
    level = client.post("/levels/", json={"number": 200, "department_id": dept["id"]},
                        headers={"Authorization": f"Bearer {token}"}).json()
    cls = client.post("/classes/", json={"name": "EE200-G", "population": 80, "level_id": level["id"]},
                      headers={"Authorization": f"Bearer {token}"}).json()
    course = client.post("/courses/", json={
        "code": "EE LAB 201", "name": "Circuits Lab", "room_type_required": "lab",
        "department_id": dept["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    response = client.post("/groups/", json={
        "name": "A", "size": 40, "class_id": cls["id"], "course_id": course["id"]
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 201
    assert response.json()["name"] == "A"
    assert response.json()["size"] == 40
```

- [ ] **Step 2: Run to confirm failures**

```bash
pytest tests/test_courses.py -v
```

Expected: failures.

- [ ] **Step 3: Create `app/schemas/course.py`**

```python
from typing import Optional
from pydantic import BaseModel

VALID_ROOM_TYPES = {"lecture_hall", "lab", "studio"}


class CourseCreate(BaseModel):
    code: str
    name: str
    room_type_required: str = "lecture_hall"
    department_id: int
    lecturer_id: Optional[int] = None


class CourseUpdate(BaseModel):
    code: Optional[str] = None
    name: Optional[str] = None
    room_type_required: Optional[str] = None
    lecturer_id: Optional[int] = None


class CourseResponse(BaseModel):
    id: int
    code: str
    name: str
    room_type_required: str
    department_id: int
    lecturer_id: Optional[int]

    model_config = {"from_attributes": True}


class SharedCourseCreate(BaseModel):
    course_id: int
    class_id: int


class SharedCourseResponse(BaseModel):
    id: int
    course_id: int
    class_id: int

    model_config = {"from_attributes": True}
```

- [ ] **Step 4: Create `app/routers/courses.py`**

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.course import Course, SharedCourse
from app.schemas.course import (
    CourseCreate, CourseUpdate, CourseResponse,
    SharedCourseCreate, SharedCourseResponse,
)
from app.core.auth import get_current_user
from app.core.permissions import require_min_role
from app.models.user import User

router = APIRouter(tags=["Courses"])


@router.post("/courses/", response_model=CourseResponse, status_code=201)
def create_course(
    data: CourseCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    course = Course(**data.model_dump())
    db.add(course)
    db.commit()
    db.refresh(course)
    return course


@router.get("/courses/", response_model=list[CourseResponse])
def list_courses(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    return db.query(Course).all()


@router.get("/courses/{course_id}", response_model=CourseResponse)
def get_course(course_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    course = db.query(Course).filter(Course.id == course_id).first()
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    return course


@router.put("/courses/{course_id}", response_model=CourseResponse)
def update_course(
    course_id: int,
    data: CourseUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    course = db.query(Course).filter(Course.id == course_id).first()
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(course, key, value)
    db.commit()
    db.refresh(course)
    return course


@router.delete("/courses/{course_id}", status_code=204)
def delete_course(
    course_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    course = db.query(Course).filter(Course.id == course_id).first()
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    db.delete(course)
    db.commit()


@router.post("/courses/shared/", response_model=SharedCourseResponse, status_code=201)
def add_shared_course(
    data: SharedCourseCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    existing = db.query(SharedCourse).filter(
        SharedCourse.course_id == data.course_id,
        SharedCourse.class_id == data.class_id,
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="This course is already shared with that class")
    shared = SharedCourse(**data.model_dump())
    db.add(shared)
    db.commit()
    db.refresh(shared)
    return shared


@router.get("/courses/{course_id}/shared", response_model=list[SharedCourseResponse])
def list_shared_classes(
    course_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    return db.query(SharedCourse).filter(SharedCourse.course_id == course_id).all()


@router.delete("/courses/shared/{shared_id}", status_code=204)
def remove_shared_course(
    shared_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    shared = db.query(SharedCourse).filter(SharedCourse.id == shared_id).first()
    if not shared:
        raise HTTPException(status_code=404, detail="Shared course relationship not found")
    db.delete(shared)
    db.commit()
```

- [ ] **Step 5: Register router in `app/main.py`**

```python
from fastapi import FastAPI
from app.routers import auth, universities, faculties, departments, rooms, semesters, academic, courses

app = FastAPI(title="University Timetabling API", version="1.0.0")

app.include_router(auth.router)
app.include_router(universities.router)
app.include_router(faculties.router)
app.include_router(departments.router)
app.include_router(rooms.router)
app.include_router(semesters.router)
app.include_router(academic.router)
app.include_router(courses.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
```

- [ ] **Step 6: Run tests**

```bash
pytest tests/test_courses.py -v
```

Expected: all tests pass.

- [ ] **Step 7: Commit checkpoint**

> **Suggested commit message:** "feat: add Course and SharedCourse APIs"

```bash
git add backend/app/schemas/course.py backend/app/routers/courses.py backend/app/main.py backend/tests/test_courses.py
```

---

## Task 12: User Management, Lecturer & Student APIs

**Files:**
- Modify: `backend/app/schemas/user.py` (add lecturer/student schemas)
- Create: `backend/app/routers/users.py`
- Create: `backend/tests/test_users.py`
- Modify: `backend/app/main.py`

- [ ] **Step 1: Write `tests/test_users.py`**

```python
def get_admin_token(client):
    client.post("/auth/register", json={
        "email": "useradmin@ub.cm", "password": "admin123",
        "full_name": "Admin", "role": "super_admin"
    })
    resp = client.post("/auth/login", json={"email": "useradmin@ub.cm", "password": "admin123"})
    return resp.json()["access_token"]


def create_lecturer_user(client, token):
    resp = client.post("/auth/register", json={
        "email": "lecturer@ub.cm", "password": "pass123",
        "full_name": "Dr. Smith", "role": "lecturer"
    })
    return resp.json()


def test_create_lecturer_profile(client):
    token = get_admin_token(client)
    user = create_lecturer_user(client, token)
    response = client.post("/lecturers/", json={
        "staff_id": "STF001", "user_id": user["id"]
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 201
    assert response.json()["staff_id"] == "STF001"


def test_list_lecturers(client):
    token = get_admin_token(client)
    response = client.get("/lecturers/", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_create_student_profile(client):
    token = get_admin_token(client)
    uni = client.post("/universities/", json={"name": "UB Users", "slug": "ub-users"},
                      headers={"Authorization": f"Bearer {token}"}).json()
    faculty = client.post("/faculties/", json={"name": "FET", "code": "FET-U", "university_id": uni["id"]},
                          headers={"Authorization": f"Bearer {token}"}).json()
    dept = client.post("/departments/", json={"name": "EE", "code": "EE-U", "faculty_id": faculty["id"]},
                       headers={"Authorization": f"Bearer {token}"}).json()
    level = client.post("/levels/", json={"number": 300, "department_id": dept["id"]},
                        headers={"Authorization": f"Bearer {token}"}).json()
    cls = client.post("/classes/", json={"name": "EE300-U", "population": 100, "level_id": level["id"]},
                      headers={"Authorization": f"Bearer {token}"}).json()
    student_user = client.post("/auth/register", json={
        "email": "student2@ub.cm", "password": "pass", "full_name": "Jane", "role": "student"
    }).json()
    response = client.post("/students/", json={
        "matric_number": "FE21A001", "user_id": student_user["id"], "class_id": cls["id"]
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 201
    assert response.json()["matric_number"] == "FE21A001"


def test_add_lecturer_availability(client):
    token = get_admin_token(client)
    user = create_lecturer_user(client, token)
    lecturer = client.post("/lecturers/", json={
        "staff_id": "STF002", "user_id": user["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    uni = client.post("/universities/", json={"name": "UB Avail", "slug": "ub-avail"},
                      headers={"Authorization": f"Bearer {token}"}).json()
    semester = client.post("/semesters/", json={
        "name": "S1", "start_date": "2025-09-01", "end_date": "2026-01-31", "university_id": uni["id"]
    }, headers={"Authorization": f"Bearer {token}"}).json()
    response = client.post("/lecturers/availability/", json={
        "day_of_week": "Friday",
        "start_time": "07:00",
        "end_time": "18:00",
        "is_available": False,
        "lecturer_id": lecturer["id"],
        "semester_id": semester["id"]
    }, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 201
    assert response.json()["day_of_week"] == "Friday"
    assert response.json()["is_available"] is False
```

- [ ] **Step 2: Run to confirm failures**

```bash
pytest tests/test_users.py -v
```

Expected: failures.

- [ ] **Step 3: Add lecturer/student schemas to `app/schemas/user.py`**

```python
from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import time


class UserCreate(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    role: str
    university_id: Optional[int] = None
    department_id: Optional[int] = None


class UserResponse(BaseModel):
    id: int
    email: str
    full_name: str
    role: str
    is_active: bool
    university_id: Optional[int]
    department_id: Optional[int]

    model_config = {"from_attributes": True}


class LoginRequest(BaseModel):
    email: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse


class LecturerCreate(BaseModel):
    staff_id: str
    user_id: int


class LecturerResponse(BaseModel):
    id: int
    staff_id: str
    user_id: int

    model_config = {"from_attributes": True}


class StudentCreate(BaseModel):
    matric_number: str
    user_id: int
    class_id: int
    group_id: Optional[int] = None


class StudentUpdate(BaseModel):
    group_id: Optional[int] = None


class StudentResponse(BaseModel):
    id: int
    matric_number: str
    user_id: int
    class_id: int
    group_id: Optional[int]

    model_config = {"from_attributes": True}


class LecturerAvailabilityCreate(BaseModel):
    day_of_week: str
    start_time: time
    end_time: time
    is_available: bool
    lecturer_id: int
    semester_id: int


class LecturerAvailabilityResponse(BaseModel):
    id: int
    day_of_week: str
    start_time: time
    end_time: time
    is_available: bool
    lecturer_id: int
    semester_id: int

    model_config = {"from_attributes": True}
```

- [ ] **Step 4: Create `app/routers/users.py`**

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.user import Lecturer, Student, LecturerAvailability
from app.schemas.user import (
    LecturerCreate, LecturerResponse,
    StudentCreate, StudentUpdate, StudentResponse,
    LecturerAvailabilityCreate, LecturerAvailabilityResponse,
)
from app.core.auth import get_current_user
from app.core.permissions import require_min_role
from app.models.user import User

router = APIRouter(tags=["Users"])


@router.post("/lecturers/", response_model=LecturerResponse, status_code=201)
def create_lecturer(
    data: LecturerCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    if db.query(Lecturer).filter(Lecturer.staff_id == data.staff_id).first():
        raise HTTPException(status_code=400, detail="Staff ID already exists")
    lecturer = Lecturer(**data.model_dump())
    db.add(lecturer)
    db.commit()
    db.refresh(lecturer)
    return lecturer


@router.get("/lecturers/", response_model=list[LecturerResponse])
def list_lecturers(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    return db.query(Lecturer).all()


@router.get("/lecturers/{lecturer_id}", response_model=LecturerResponse)
def get_lecturer(lecturer_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    lecturer = db.query(Lecturer).filter(Lecturer.id == lecturer_id).first()
    if not lecturer:
        raise HTTPException(status_code=404, detail="Lecturer not found")
    return lecturer


@router.post("/students/", response_model=StudentResponse, status_code=201)
def create_student(
    data: StudentCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    if db.query(Student).filter(Student.matric_number == data.matric_number).first():
        raise HTTPException(status_code=400, detail="Matric number already exists")
    student = Student(**data.model_dump())
    db.add(student)
    db.commit()
    db.refresh(student)
    return student


@router.get("/students/", response_model=list[StudentResponse])
def list_students(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    return db.query(Student).all()


@router.put("/students/{student_id}", response_model=StudentResponse)
def update_student(
    student_id: int,
    data: StudentUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("timetable_officer")),
):
    student = db.query(Student).filter(Student.id == student_id).first()
    if not student:
        raise HTTPException(status_code=404, detail="Student not found")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(student, key, value)
    db.commit()
    db.refresh(student)
    return student


@router.post("/lecturers/availability/", response_model=LecturerAvailabilityResponse, status_code=201)
def add_availability(
    data: LecturerAvailabilityCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("lecturer")),
):
    availability = LecturerAvailability(**data.model_dump())
    db.add(availability)
    db.commit()
    db.refresh(availability)
    return availability


@router.get("/lecturers/{lecturer_id}/availability", response_model=list[LecturerAvailabilityResponse])
def get_lecturer_availability(
    lecturer_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    return db.query(LecturerAvailability).filter(LecturerAvailability.lecturer_id == lecturer_id).all()


@router.delete("/lecturers/availability/{availability_id}", status_code=204)
def delete_availability(
    availability_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_min_role("lecturer")),
):
    availability = db.query(LecturerAvailability).filter(LecturerAvailability.id == availability_id).first()
    if not availability:
        raise HTTPException(status_code=404, detail="Availability record not found")
    db.delete(availability)
    db.commit()
```

- [ ] **Step 5: Register router in `app/main.py`**

```python
from fastapi import FastAPI
from app.routers import auth, universities, faculties, departments, rooms, semesters, academic, courses, users

app = FastAPI(title="University Timetabling API", version="1.0.0")

app.include_router(auth.router)
app.include_router(universities.router)
app.include_router(faculties.router)
app.include_router(departments.router)
app.include_router(rooms.router)
app.include_router(semesters.router)
app.include_router(academic.router)
app.include_router(courses.router)
app.include_router(users.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
```

- [ ] **Step 6: Run all tests**

```bash
pytest tests/test_users.py -v
```

Expected: all tests pass.

- [ ] **Step 7: Run the full test suite to confirm nothing is broken**

```bash
pytest -v
```

Expected: all tests across all test files pass.

- [ ] **Step 8: Commit checkpoint**

> **Suggested commit message:** "feat: add User, Lecturer, Student, and Lecturer Availability APIs"

```bash
git add backend/app/schemas/user.py backend/app/routers/users.py backend/app/main.py backend/tests/test_users.py
```

---

## Task 13: Final Verification

- [ ] **Step 1: Run the full test suite one final time**

```bash
cd backend
source venv/Scripts/activate
pytest -v --tb=short
```

Expected: all tests pass with no failures or errors.

- [ ] **Step 2: Start the server and verify the API docs**

```bash
uvicorn app.main:app --reload
```

Open `http://127.0.0.1:8000/docs` in your browser. You should see all endpoints grouped by tag:
- Authentication
- Universities
- Faculties
- Departments
- Rooms
- Semesters
- Academic Structure
- Courses
- Users

- [ ] **Step 3: Final commit checkpoint**

> **Suggested commit message:** "chore: complete backend foundation — all CRUD APIs tested and passing"

```bash
git add .
```

---

## Task 14: Seed Data Script

**Files:**
- Create: `backend/seed.py`

This script inserts realistic reference data into the database so that you can test every endpoint without manually creating records via the API. It seeds one university (University of Buea), one faculty (FET), two departments (EE, CE), a semester, time slots, two rooms, one admin user, and one student user.

- [ ] **Step 1: Create `backend/seed.py`**

```python
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from app.database import SessionLocal, engine
from app import models
from app.core.security import get_password_hash

models.Base.metadata.create_all(bind=engine)


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

        room_amp = models.Room(
            name="Amphi 750", capacity=750,
            room_type="lecture_hall", university_id=university.id,
        )
        room_lab = models.Room(
            name="EE Lab 1", capacity=30,
            room_type="lab", university_id=university.id,
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
        student = models.User(
            email="student@ub.cm",
            hashed_password=get_password_hash("student123"),
            full_name="Test Student",
            role="student",
            is_active=True,
            university_id=university.id,
            department_id=dept_ee.id,
        )
        db.add_all([admin, student])
        db.commit()
        print("Seed complete.")
        print("  Admin:   admin@ub.cm / admin123")
        print("  Student: student@ub.cm / student123")
    except Exception as e:
        db.rollback()
        raise e
    finally:
        db.close()


if __name__ == "__main__":
    seed()
```

- [ ] **Step 2: Run the seed script**

```bash
cd backend
source venv/Scripts/activate
python seed.py
```

Expected output:
```
Seed complete.
  Admin:   admin@ub.cm / admin123
  Student: student@ub.cm / student123
```

Running it a second time prints "Database already seeded — skipping." without error.

- [ ] **Step 3: Verify via the API**

```bash
uvicorn app.main:app --reload
```

Open `http://127.0.0.1:8000/docs`, use the `/auth/login` endpoint with `admin@ub.cm` / `admin123`. You should get a JWT token back.

- [ ] **Step 4: Commit checkpoint**

> **Suggested commit message:** "feat: add seed script with UB reference data"

```bash
git add backend/seed.py
```

---

## What's Next

**Plan 2 — Timetable Generation Engine** will add:
- `Timetable` and `TimetableEntry` models
- OR-Tools constraint solver integration
- Pre-processing: merge decision, lab split detection
- Overcapacity handling with soft constraints
- Head conflict resolution (add session vs. rotation)
- Background task for async generation
- Timetable status workflow (draft → published)

**Plan 3 — Flutter Frontend** will add:
- Role-based navigation and screens
- Timetable grid view
- UI design phase using the frontend-design skill
