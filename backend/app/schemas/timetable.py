from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class RunCreate(BaseModel):
    name: str
    semester_id: int
    faculty_ids: list[int]
    building_ids: list[int]


class RunResponse(BaseModel):
    id: int
    name: str
    status: str
    semester_id: int
    created_by: int
    generated_at: Optional[datetime]
    created_at: datetime
    faculty_ids: list[int] = []
    building_ids: list[int] = []

    model_config = {"from_attributes": True}


class TimetableEntryResponse(BaseModel):
    id: int
    run_id: int
    course_id: int
    lecturer_id: int
    room_id: int
    time_slot_id: int
    group_id: Optional[int]
    week_pattern: str
    rotation_sequence: Optional[str]
    is_overcapacity: bool
    is_merged: bool
    class_ids: list[int] = []

    model_config = {"from_attributes": True}


class TimetableConflictResponse(BaseModel):
    id: int
    run_id: int
    conflict_type: str
    course_id: Optional[int]
    class_id: Optional[int]
    details: str
    resolved: bool
    resolution: Optional[str]

    model_config = {"from_attributes": True}


class ConflictResolutionRequest(BaseModel):
    resolution: str  # add_session | rotate_groups


class GenerationJobResponse(BaseModel):
    status: str
    error_message: Optional[str] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class ManualSlotMoveRequest(BaseModel):
    entry_id: int
    new_time_slot_id: int
    new_room_id: int


class NotificationResponse(BaseModel):
    id: int
    message: str
    notification_type: str
    is_read: bool
    created_at: datetime

    model_config = {"from_attributes": True}
