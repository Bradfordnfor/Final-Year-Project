from typing import Optional
from pydantic import BaseModel


class CourseCreate(BaseModel):
    code: str
    name: str
    room_type_required: str = "lecture_hall"
    level_id: Optional[int] = None
    department_id: Optional[int] = None
    university_id: Optional[int] = None
    lecturer_id: Optional[int] = None
    class_id: Optional[int] = None
    weekly_hours: int = 2
    semester: int = 1  # 1 = first, 2 = second, 0 = both


class CourseUpdate(BaseModel):
    code: Optional[str] = None
    name: Optional[str] = None
    room_type_required: Optional[str] = None
    lecturer_id: Optional[int] = None
    class_id: Optional[int] = None
    weekly_hours: Optional[int] = None
    semester: Optional[int] = None


class CourseOut(BaseModel):
    id: int
    code: str
    name: str
    room_type_required: str
    level_id: Optional[int]
    department_id: Optional[int]
    university_id: Optional[int]
    lecturer_id: Optional[int]
    class_id: Optional[int]
    weekly_hours: int
    semester: int

    model_config = {"from_attributes": True}


class SharedCourseCreate(BaseModel):
    course_id: int
    class_id: int


class SharedCourseOut(BaseModel):
    id: int
    course_id: int
    class_id: int

    model_config = {"from_attributes": True}
