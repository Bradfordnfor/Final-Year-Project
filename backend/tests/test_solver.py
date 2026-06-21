from app.solver.models import ScheduleSession, SolverInput
from app.solver.solver import solve_timetable


def make_session(id_, course_id, lecturer_id, class_ids, population, session_num=1, room_type="lecture_hall"):
    return ScheduleSession(
        id=id_, course_id=course_id, course_code=f"C{course_id}",
        lecturer_id=lecturer_id, room_type_required=room_type,
        class_ids=class_ids, population=population, session_number=session_num,
    )


def make_slot(id_, day, start="07:00", end="09:00"):
    return {"id": id_, "day": day, "start": start, "end": end}


def make_room(id_, capacity, room_type="lecture_hall"):
    return {"id": id_, "capacity": capacity, "room_type": room_type}


def test_simple_two_session_schedule():
    sessions = [
        make_session("s1", course_id=1, lecturer_id=1, class_ids=[1], population=50),
        make_session("s2", course_id=2, lecturer_id=2, class_ids=[2], population=40),
    ]
    slots = [make_slot(1, "Monday"), make_slot(2, "Wednesday")]
    rooms = [make_room(1, 100), make_room(2, 60)]
    result = solve_timetable(SolverInput(
        sessions=sessions, time_slots=slots, rooms=rooms,
        lecturer_unavailability={},
    ))
    assert result.status in ("optimal", "feasible")
    assert len(result.assignments) == 2
    slot_room_pairs = [(a.time_slot_id, a.room_id) for a in result.assignments]
    assert len(slot_room_pairs) == len(set(slot_room_pairs))


def test_no_lecturer_double_booking():
    sessions = [
        make_session("s1", course_id=1, lecturer_id=99, class_ids=[1], population=30),
        make_session("s2", course_id=2, lecturer_id=99, class_ids=[2], population=30),
    ]
    slots = [make_slot(1, "Monday"), make_slot(2, "Tuesday")]
    rooms = [make_room(1, 50), make_room(2, 50)]
    result = solve_timetable(SolverInput(
        sessions=sessions, time_slots=slots, rooms=rooms,
        lecturer_unavailability={},
    ))
    assert result.status in ("optimal", "feasible")
    slot_ids = [a.time_slot_id for a in result.assignments]
    assert slot_ids[0] != slot_ids[1]


def test_no_class_double_booking():
    sessions = [
        make_session("s1", course_id=1, lecturer_id=1, class_ids=[10], population=60),
        make_session("s2", course_id=2, lecturer_id=2, class_ids=[10], population=60),
    ]
    slots = [make_slot(1, "Monday"), make_slot(2, "Wednesday")]
    rooms = [make_room(1, 100), make_room(2, 100)]
    result = solve_timetable(SolverInput(
        sessions=sessions, time_slots=slots, rooms=rooms,
        lecturer_unavailability={},
    ))
    assert result.status in ("optimal", "feasible")
    slot_ids = [a.time_slot_id for a in result.assignments]
    assert slot_ids[0] != slot_ids[1]


def test_room_type_constraint():
    sessions = [make_session("s1", 1, 1, [1], 20, room_type="lab")]
    slots = [make_slot(1, "Monday")]
    rooms = [make_room(1, 100, "lecture_hall"), make_room(2, 30, "lab")]
    result = solve_timetable(SolverInput(
        sessions=sessions, time_slots=slots, rooms=rooms,
        lecturer_unavailability={},
    ))
    assert result.status in ("optimal", "feasible")
    assert result.assignments[0].room_id == 2


def test_lecturer_unavailability_respected():
    sessions = [make_session("s1", 1, 5, [1], 30)]
    slots = [make_slot(1, "Friday"), make_slot(2, "Monday")]
    rooms = [make_room(1, 50)]
    result = solve_timetable(SolverInput(
        sessions=sessions, time_slots=slots, rooms=rooms,
        lecturer_unavailability={5: [1]},
    ))
    assert result.status in ("optimal", "feasible")
    assert result.assignments[0].time_slot_id == 2


def test_overcapacity_flagged():
    sessions = [make_session("s1", 1, 1, [1], population=800)]
    slots = [make_slot(1, "Monday")]
    rooms = [make_room(1, 700)]
    result = solve_timetable(SolverInput(
        sessions=sessions, time_slots=slots, rooms=rooms,
        lecturer_unavailability={},
    ))
    assert result.status in ("optimal", "feasible")
    assert result.assignments[0].is_overcapacity is True


def test_prefers_best_capacity_fit():
    # One slot, two rooms — both sessions share the slot in different rooms.
    # The big (joint-style) session must take the big hall and the small class
    # the small room, not the other way round.
    sessions = [
        make_session("big", course_id=1, lecturer_id=1, class_ids=[1], population=180),
        make_session("small", course_id=2, lecturer_id=2, class_ids=[2], population=60),
    ]
    slots = [make_slot(1, "Monday")]
    rooms = [make_room(1, 200), make_room(2, 100)]
    result = solve_timetable(SolverInput(
        sessions=sessions, time_slots=slots, rooms=rooms,
        lecturer_unavailability={},
    ))
    assert result.status in ("optimal", "feasible")
    by_session = {a.session.id: a.room_id for a in result.assignments}
    assert by_session["big"] == 1    # 200-seat hall
    assert by_session["small"] == 2  # 100-seat room


def test_infeasible_returns_infeasible_status():
    sessions = [
        make_session("s1", 1, 99, [1], 30),
        make_session("s2", 2, 99, [2], 30),
    ]
    slots = [make_slot(1, "Monday")]  # only 1 slot, same lecturer — impossible
    rooms = [make_room(1, 50), make_room(2, 50)]
    result = solve_timetable(SolverInput(
        sessions=sessions, time_slots=slots, rooms=rooms,
        lecturer_unavailability={},
    ))
    assert result.status == "infeasible"
