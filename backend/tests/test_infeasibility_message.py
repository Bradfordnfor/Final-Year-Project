"""Unit tests for explain_infeasibility: the human-readable reason a timetable
run came back INFEASIBLE. Pure logic over a SolverInput — no DB needed."""
from app.solver.models import SolverInput, ScheduleSession
from app.solver.solver import explain_infeasibility


def _session(sid, lecturer_id, class_ids, room_type="lecture_hall", population=30):
    return ScheduleSession(
        id=str(sid), course_id=sid, course_code=f"C{sid}",
        lecturer_id=lecturer_id, room_type_required=room_type,
        class_ids=class_ids, population=population, session_number=1,
    )


def _slots(n):
    return [{"id": i, "day": "Monday", "start": "07:00", "end": "09:00"} for i in range(1, n + 1)]


def _rooms(n, room_type="lecture_hall"):
    return [{"id": i, "capacity": 100, "room_type": room_type} for i in range(1, n + 1)]


def test_missing_room_type_is_reported():
    si = SolverInput(
        sessions=[_session(1, 1, [1], room_type="lab")],
        time_slots=_slots(4),
        rooms=_rooms(2, room_type="lecture_hall"),  # no lab
        lecturer_unavailability={},
    )
    msg = explain_infeasibility(si)
    assert "lab" in msg and "room type" in msg.lower()


def test_global_room_slot_shortfall_is_reported():
    # 10 sessions, 2 rooms x 4 slots = 8 openings < 10
    si = SolverInput(
        sessions=[_session(i, i, [i]) for i in range(1, 11)],
        time_slots=_slots(4),
        rooms=_rooms(2),
        lecturer_unavailability={},
    )
    msg = explain_infeasibility(si)
    assert "10 sessions" in msg
    assert "8 openings" in msg


def test_lecturer_overload_is_reported():
    # One lecturer teaches 5 sessions but only 4 slots exist. Plenty of rooms
    # so the global/room-type checks pass first, isolating the lecturer case.
    si = SolverInput(
        sessions=[_session(i, 7, [i]) for i in range(1, 6)],
        time_slots=_slots(4),
        rooms=_rooms(10),
        lecturer_unavailability={},
    )
    msg = explain_infeasibility(si)
    assert "lecturer" in msg.lower()


def test_class_overload_is_reported():
    # One class attends 5 sessions but only 4 slots; each session a distinct
    # lecturer and plenty of rooms so earlier checks pass first.
    si = SolverInput(
        sessions=[_session(i, i, [99]) for i in range(1, 6)],
        time_slots=_slots(4),
        rooms=_rooms(10),
        lecturer_unavailability={},
    )
    msg = explain_infeasibility(si)
    assert "class" in msg.lower()
