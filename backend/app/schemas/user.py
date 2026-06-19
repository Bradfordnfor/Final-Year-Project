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
    full_name: str = ""

    model_config = {"from_attributes": True}

    @classmethod
    def from_lecturer(cls, lecturer) -> "LecturerOut":
        return cls(
            id=lecturer.id,
            user_id=lecturer.user_id,
            department_id=lecturer.department_id,
            full_name=lecturer.user.full_name if lecturer.user else "",
        )


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
