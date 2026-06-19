from typing import Optional
from pydantic import BaseModel


class SemesterCreate(BaseModel):
    name: str
    start_date: str
    end_date: str
    university_id: int
    term: int = 1  # 1 = first semester of the year, 2 = second


class SemesterUpdate(BaseModel):
    name: Optional[str] = None
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    is_active: Optional[bool] = None
    term: Optional[int] = None


class SemesterOut(BaseModel):
    id: int
    name: str
    start_date: str
    end_date: str
    is_active: bool
    university_id: int
    term: int

    model_config = {"from_attributes": True}


class TimeSlotCreate(BaseModel):
    day_of_week: str
    start_time: str
    end_time: str
    semester_id: int


class TimeSlotOut(BaseModel):
    id: int
    day_of_week: str
    start_time: str
    end_time: str
    semester_id: int

    model_config = {"from_attributes": True}


class LevelCreate(BaseModel):
    number: int
    department_id: int


class LevelOut(BaseModel):
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


class ClassOut(BaseModel):
    id: int
    name: str
    population: int
    level_id: int

    model_config = {"from_attributes": True}


class ClassGroupCreate(BaseModel):
    name: str
    size: int
    class_id: int


class ClassGroupUpdate(BaseModel):
    name: Optional[str] = None
    size: Optional[int] = None


class ClassGroupOut(BaseModel):
    id: int
    name: str
    size: int
    class_id: int

    model_config = {"from_attributes": True}
