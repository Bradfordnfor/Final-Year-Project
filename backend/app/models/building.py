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
