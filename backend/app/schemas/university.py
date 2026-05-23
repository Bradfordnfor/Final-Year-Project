from typing import Optional
from pydantic import BaseModel


class UniversityCreate(BaseModel):
    name: str
    slug: str
    overflow_threshold: float = 0.20


class UniversityWithAdminCreate(BaseModel):
    # University
    name: str
    slug: str
    overflow_threshold: float = 0.20
    # First admin account
    admin_full_name: str
    admin_email: str
    admin_password: str


class UniversityOut(BaseModel):
    id: int
    name: str
    slug: str
    overflow_threshold: float

    model_config = {"from_attributes": True}


class UniversityCreateResponse(BaseModel):
    id: int
    name: str
    slug: str
    overflow_threshold: float
    admin_id: int
    admin_email: str
    admin_full_name: str


class FacultyCreate(BaseModel):
    name: str
    code: str
    sessions_per_week: int = 2
    session_duration_hours: int = 2
    university_id: int


class FacultyOut(BaseModel):
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


class DepartmentOut(BaseModel):
    id: int
    name: str
    code: str
    faculty_id: int

    model_config = {"from_attributes": True}
