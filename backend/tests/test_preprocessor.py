from app.solver.models import ScheduleSession, ConflictFlag
from app.solver.preprocessor import compute_merge_decision, compute_lab_split


def make_class(id_, population):
    return {"id": id_, "population": population}


def make_room(id_, capacity, room_type="lecture_hall"):
    return {"id": id_, "capacity": capacity, "room_type": room_type}


def make_course(id_, room_type="lecture_hall"):
    return {"id": id_, "code": f"C{id_}", "room_type_required": room_type}


# --- Merge decision tests ---

def test_merge_when_combined_fits_in_room():
    course = make_course(1)
    classes = [make_class(1, 60), make_class(2, 50)]  # combined = 110
    rooms = [make_room(1, 120)]
    sessions, conflict = compute_merge_decision(
        course=course, classes=classes, rooms=rooms,
        lecturer_id=10, sessions_per_week=2, overflow_threshold=0.20
    )
    assert conflict is None
    assert len(sessions) == 2
    assert sessions[0].is_merged is True
    assert sessions[0].population == 110
    assert set(sessions[0].class_ids) == {1, 2}


def test_separate_when_combined_too_large():
    course = make_course(1)
    classes = [make_class(1, 200), make_class(2, 200)]  # combined = 400
    rooms = [make_room(1, 300)]
    sessions, conflict = compute_merge_decision(
        course=course, classes=classes, rooms=rooms,
        lecturer_id=10, sessions_per_week=2, overflow_threshold=0.20
    )
    assert conflict is None
    assert len(sessions) == 4  # 2 classes × 2 sessions each
    assert all(not s.is_merged for s in sessions)
    assert all(len(s.class_ids) == 1 for s in sessions)


def test_single_class_no_merge_needed():
    course = make_course(1)
    classes = [make_class(1, 80)]
    rooms = [make_room(1, 100)]
    sessions, conflict = compute_merge_decision(
        course=course, classes=classes, rooms=rooms,
        lecturer_id=5, sessions_per_week=2, overflow_threshold=0.20
    )
    assert conflict is None
    assert len(sessions) == 2
    assert sessions[0].is_merged is False


# --- Lab split tests ---

def test_no_split_when_population_fits():
    course = make_course(1, room_type="lab")
    student_class = make_class(1, 30)
    labs = [make_room(1, 40, "lab")]
    sessions, conflict = compute_lab_split(
        course=course, student_class=student_class,
        labs=labs, sessions_per_week=2, lecturer_id=7
    )
    assert conflict is None
    assert len(sessions) == 2
    assert sessions[0].group_id is None


def test_split_when_population_exceeds_lab():
    course = make_course(1, room_type="lab")
    student_class = make_class(1, 80)
    labs = [make_room(1, 40, "lab")]
    sessions, conflict = compute_lab_split(
        course=course, student_class=student_class,
        labs=labs, sessions_per_week=2, lecturer_id=7
    )
    assert conflict is None
    assert len(sessions) == 2
    assert all(s.population <= 40 for s in sessions)
    assert sessions[0].session_number != sessions[1].session_number


def test_flag_when_groups_exceed_sessions():
    course = make_course(1, room_type="lab")
    student_class = make_class(1, 130)
    labs = [make_room(1, 40, "lab")]  # needs 4 groups but only 2 sessions
    sessions, conflict = compute_lab_split(
        course=course, student_class=student_class,
        labs=labs, sessions_per_week=2, lecturer_id=7
    )
    assert len(sessions) == 0
    assert conflict is not None
    assert conflict.conflict_type == "lab_split_conflict"
    assert conflict.groups_needed == 4
    assert conflict.sessions_available == 2


def test_no_labs_available():
    course = make_course(1, room_type="lab")
    student_class = make_class(1, 50)
    labs = []
    sessions, conflict = compute_lab_split(
        course=course, student_class=student_class,
        labs=labs, sessions_per_week=2, lecturer_id=7
    )
    assert len(sessions) == 0
    assert conflict is not None
    assert conflict.conflict_type == "no_room_available"
