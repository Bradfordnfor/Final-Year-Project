from typing import Optional
from pydantic import BaseModel


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


class CourseOut(BaseModel):
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


class SharedCourseOut(BaseModel):
    id: int
    course_id: int
    class_id: int

    model_config = {"from_attributes": True}
