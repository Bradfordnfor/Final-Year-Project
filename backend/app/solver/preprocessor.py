from math import ceil
from typing import Optional
from app.solver.models import ScheduleSession, ConflictFlag


def compute_merge_decision(
    course: dict,
    classes: list[dict],
    rooms: list[dict],
    lecturer_id: int,
    sessions_per_week: int,
    overflow_threshold: float,
) -> tuple[list[ScheduleSession], Optional[ConflictFlag]]:
    if len(classes) <= 1:
        return _make_sessions(course, classes[0], lecturer_id, sessions_per_week, is_merged=False), None

    compatible_rooms = [r for r in rooms if r["room_type"] == course["room_type_required"]]
    if not compatible_rooms:
        sessions = []
        for cls in classes:
            sessions.extend(_make_sessions(course, cls, lecturer_id, sessions_per_week))
        return sessions, None

    largest_capacity = max(r["capacity"] for r in compatible_rooms)
    combined_population = sum(c["population"] for c in classes)
    merge_threshold = largest_capacity * (1 + overflow_threshold)

    if combined_population <= merge_threshold:
        sessions = []
        for session_num in range(1, sessions_per_week + 1):
            sessions.append(ScheduleSession(
                id=f"course_{course['id']}_merged_session_{session_num}",
                course_id=course["id"],
                course_code=course["code"],
                lecturer_id=lecturer_id,
                room_type_required=course["room_type_required"],
                class_ids=[c["id"] for c in classes],
                population=combined_population,
                session_number=session_num,
                is_merged=True,
            ))
        return sessions, None
    else:
        sessions = []
        for cls in classes:
            sessions.extend(_make_sessions(course, cls, lecturer_id, sessions_per_week))
        return sessions, None


def compute_university_wide_sessions(
    course: dict,
    classes: list[dict],
    rooms: list[dict],
    lecturer_id: int,
    sessions_per_week: int,
    overflow_threshold: float,
) -> list[ScheduleSession]:
    """Build sessions for a university-wide course, sat by every class.

    To keep the number of sessions (and the lecturer's load) low, classes are
    grouped so that each group's combined population fits the largest suitable
    hall plus the university's overflow allowance. Each group becomes one
    session, repeated `sessions_per_week` times. A class too big for any hall
    lands in a group on its own and is flagged over capacity downstream.
    """
    if not classes:
        return []

    compatible = [r for r in rooms if r["room_type"] == course["room_type_required"]]
    if compatible:
        largest = max(r["capacity"] for r in compatible)
        cap = largest * (1 + overflow_threshold)
    else:
        # No capacity-bound room (e.g. outdoor): everyone in a single group.
        cap = float("inf")

    # First-fit-decreasing bin packing: place the biggest classes first.
    groups: list[dict] = []
    for cls in sorted(classes, key=lambda c: c["population"], reverse=True):
        placed = False
        for g in groups:
            if g["pop"] + cls["population"] <= cap:
                g["classes"].append(cls)
                g["pop"] += cls["population"]
                placed = True
                break
        if not placed:
            groups.append({"classes": [cls], "pop": cls["population"]})

    sessions: list[ScheduleSession] = []
    for gi, g in enumerate(groups):
        for n in range(1, sessions_per_week + 1):
            sessions.append(ScheduleSession(
                id=f"course_{course['id']}_uwgroup_{gi}_session_{n}",
                course_id=course["id"],
                course_code=course["code"],
                lecturer_id=lecturer_id,
                room_type_required=course["room_type_required"],
                class_ids=[c["id"] for c in g["classes"]],
                population=g["pop"],
                session_number=n,
                is_merged=len(g["classes"]) > 1,
            ))
    return sessions


def compute_lab_split(
    course: dict,
    student_class: dict,
    labs: list[dict],
    sessions_per_week: int,
    lecturer_id: int,
) -> tuple[list[ScheduleSession], Optional[ConflictFlag]]:
    if not labs:
        return [], ConflictFlag(
            conflict_type="no_room_available",
            course_id=course["id"],
            class_id=student_class["id"],
            details=f"No lab rooms exist for course {course['code']}",
        )

    largest_lab = max(labs, key=lambda r: r["capacity"])
    population = student_class["population"]

    if population <= largest_lab["capacity"]:
        return _make_sessions(course, student_class, lecturer_id, sessions_per_week), None

    groups_needed = ceil(population / largest_lab["capacity"])

    if groups_needed > sessions_per_week:
        return [], ConflictFlag(
            conflict_type="lab_split_conflict",
            course_id=course["id"],
            class_id=student_class["id"],
            groups_needed=groups_needed,
            sessions_available=sessions_per_week,
            details=(
                f"{course['code']}: {population} students need {groups_needed} groups "
                f"but only {sessions_per_week} sessions/week available."
            ),
        )

    group_size = ceil(population / groups_needed)
    sessions = []
    for i in range(groups_needed):
        actual_size = min(group_size, population - i * group_size)
        if actual_size <= 0:
            break
        sessions.append(ScheduleSession(
            id=f"course_{course['id']}_class_{student_class['id']}_group_{i + 1}",
            course_id=course["id"],
            course_code=course["code"],
            lecturer_id=lecturer_id,
            room_type_required="lab",
            class_ids=[student_class["id"]],
            population=actual_size,
            session_number=i + 1,
        ))
    return sessions, None


def _make_sessions(
    course: dict,
    student_class: dict,
    lecturer_id: int,
    sessions_per_week: int,
    is_merged: bool = False,
) -> list[ScheduleSession]:
    return [
        ScheduleSession(
            id=f"course_{course['id']}_class_{student_class['id']}_session_{n}",
            course_id=course["id"],
            course_code=course["code"],
            lecturer_id=lecturer_id,
            room_type_required=course["room_type_required"],
            class_ids=[student_class["id"]],
            population=student_class["population"],
            session_number=n,
            is_merged=is_merged,
        )
        for n in range(1, sessions_per_week + 1)
    ]
