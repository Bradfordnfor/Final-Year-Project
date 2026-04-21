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
