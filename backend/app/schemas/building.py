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
