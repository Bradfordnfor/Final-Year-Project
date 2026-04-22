from dataclasses import dataclass, field
from typing import Optional


@dataclass
class ScheduleSession:
    """One meeting to schedule (one course session for one week)."""
    id: str
    course_id: int
    course_code: str
    lecturer_id: int
    room_type_required: str        # lecture_hall | lab | outdoor
    class_ids: list[int]
    population: int
    session_number: int
    group_id: Optional[int] = None
    is_merged: bool = False


@dataclass
class ConflictFlag:
    """A problem found during preprocessing that needs head resolution."""
    conflict_type: str             # lab_split_conflict | no_room_available
    course_id: int
    class_id: Optional[int] = None
    groups_needed: int = 0
    sessions_available: int = 0
    details: str = ""


@dataclass
class SolverInput:
    sessions: list[ScheduleSession]
    time_slots: list[dict]         # [{"id": 1, "day": "Monday", "start": "07:00", "end": "09:00"}]
    rooms: list[dict]              # [{"id": 1, "capacity": 700, "room_type": "lecture_hall"}]
    lecturer_unavailability: dict[int, list[int]]  # lecturer_id -> [timeslot_ids]


@dataclass
class SolverAssignment:
    session: ScheduleSession
    time_slot_id: int
    room_id: int
    is_overcapacity: bool = False


@dataclass
class SolverResult:
    assignments: list[SolverAssignment]
    solve_time_seconds: float
    status: str                    # optimal | feasible | infeasible | unknown
