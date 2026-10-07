import os
from collections import Counter, defaultdict
from ortools.sat.python import cp_model
from app.solver.models import SolverInput, SolverAssignment, SolverResult


def explain_infeasibility(solver_input: SolverInput) -> str:
    """Best-effort, human-readable reason a model came back INFEASIBLE.

    Checks the hard-constraint headroom the same way the model enforces it and
    returns the first shortfall found. Room capacity/overflow is only a soft
    penalty in solve_timetable(), so it can never cause infeasibility and is
    deliberately not mentioned here.
    """
    sessions = solver_input.sessions
    time_slots = solver_input.time_slots
    rooms = solver_input.rooms
    n_t = len(time_slots)
    n_r = len(rooms)
    n_s = len(sessions)

    # A required room type with no matching room at all.
    rooms_by_type = Counter(r["room_type"] for r in rooms)
    sess_by_type = Counter(s.room_type_required for s in sessions)
    missing = sorted(t for t in sess_by_type if rooms_by_type.get(t, 0) == 0)
    if missing:
        return (
            "Some sessions need a room type the selected buildings don't have: "
            + ", ".join(missing)
            + ". Add a room of that type (or a building that has one), then regenerate."
        )

    # Not enough room-slots overall to hold every session.
    if n_s > n_t * n_r:
        return (
            f"There isn't enough room in the timetable: {n_s} sessions must each take "
            f"a room in a time slot, but the selected buildings provide only {n_r} "
            f"rooms x {n_t} time slots = {n_t * n_r} openings. Add more buildings or "
            "rooms, or define more time slots, then regenerate."
        )

    # A single room type is oversubscribed.
    for t, need in sess_by_type.items():
        avail = rooms_by_type.get(t, 0) * n_t
        if need > avail:
            return (
                f"Too many '{t}' sessions: {need} are needed but only "
                f"{rooms_by_type.get(t, 0)} '{t}' room(s) x {n_t} time slots = {avail} "
                "openings are available. Add more rooms of that type or more time "
                "slots, then regenerate."
            )

    # A lecturer has more sessions than they have free time slots.
    slot_ids = {ts["id"] for ts in time_slots}
    unavail = solver_input.lecturer_unavailability
    lect_counts = Counter(s.lecturer_id for s in sessions)
    for lect_id, cnt in lect_counts.items():
        free = n_t - len(set(unavail.get(lect_id, [])) & slot_ids)
        if cnt > free:
            return (
                f"A lecturer is assigned {cnt} sessions but has only {free} free time "
                "slots (one session can run per slot). Reduce that lecturer's courses, "
                "free up their availability, or add more time slots, then regenerate."
            )

    # A class has more sessions than there are time slots.
    class_counts: dict[int, int] = defaultdict(int)
    for s in sessions:
        for cid in s.class_ids:
            class_counts[cid] += 1
    for cid, cnt in class_counts.items():
        if cnt > n_t:
            return (
                f"A class has {cnt} sessions but there are only {n_t} time slots (a "
                "class can attend one session per slot). Reduce that class's "
                "courses/weekly hours or add more time slots, then regenerate."
            )

    # No single obvious shortfall — the constraints just can't all be met together.
    return (
        "The timetable's constraints can't all be satisfied at once — usually too "
        "many sessions for the available rooms and time slots, or unavoidable "
        "lecturer/class clashes. Add rooms or time slots, or reduce the load, then "
        "regenerate."
    )


def solve_timetable(solver_input: SolverInput) -> SolverResult:
    model = cp_model.CpModel()

    sessions = solver_input.sessions
    timeslots = solver_input.time_slots
    rooms = solver_input.rooms

    n_s = len(sessions)
    n_t = len(timeslots)
    n_r = len(rooms)

    if n_s == 0:
        return SolverResult(assignments=[], solve_time_seconds=0.0, status="optimal")

    assign = {}
    for s in range(n_s):
        for t in range(n_t):
            for r in range(n_r):
                assign[(s, t, r)] = model.NewBoolVar(f"a_{s}_{t}_{r}")

    # Each session scheduled exactly once
    for s in range(n_s):
        model.AddExactlyOne(
            assign[(s, t, r)]
            for t in range(n_t)
            for r in range(n_r)
        )

    # At most one session per room per timeslot
    for t in range(n_t):
        for r in range(n_r):
            model.AddAtMostOne(assign[(s, t, r)] for s in range(n_s))

    # Lecturer teaches at most one session per timeslot
    lecturer_sessions = defaultdict(list)
    for s, session in enumerate(sessions):
        lecturer_sessions[session.lecturer_id].append(s)

    for lect_id, s_indices in lecturer_sessions.items():
        for t in range(n_t):
            model.AddAtMostOne(
                assign[(s, t, r)]
                for s in s_indices
                for r in range(n_r)
            )

    # Class attends at most one session per timeslot
    class_sessions = defaultdict(list)
    for s, session in enumerate(sessions):
        for class_id in session.class_ids:
            class_sessions[class_id].append(s)

    for class_id, s_indices in class_sessions.items():
        for t in range(n_t):
            model.AddAtMostOne(
                assign[(s, t, r)]
                for s in s_indices
                for r in range(n_r)
            )

    # Room type must match session requirement
    for s, session in enumerate(sessions):
        for t in range(n_t):
            for r, room in enumerate(rooms):
                if room["room_type"] != session.room_type_required:
                    model.Add(assign[(s, t, r)] == 0)

    # Lecturer unavailability
    unavailability = solver_input.lecturer_unavailability
    for s, session in enumerate(sessions):
        blocked_slots = unavailability.get(session.lecturer_id, [])
        for t, timeslot in enumerate(timeslots):
            if timeslot["id"] in blocked_slots:
                for r in range(n_r):
                    model.Add(assign[(s, t, r)] == 0)

    # Objective: choose rooms that fit well rather than any feasible room.
    # For a session placed in a room that covers it, the cost is the wasted
    # seats (capacity - population), so the solver prefers the tightest room.
    # A room too small to hold the session carries a large penalty, so the big
    # and joint (merged) sessions are pushed into the big halls and the small
    # classes take the small rooms — instead of assignments being arbitrary.
    OVERFLOW_PENALTY = 10_000_000
    objective_terms = []
    for s, session in enumerate(sessions):
        for r, room in enumerate(rooms):
            if room["room_type"] != session.room_type_required:
                continue
            if room["room_type"] == "outdoor":
                cost = 0  # outdoor sessions have no real room capacity
            elif room["capacity"] >= session.population:
                cost = room["capacity"] - session.population
            else:
                cost = OVERFLOW_PENALTY + (session.population - room["capacity"])
            if cost == 0:
                continue
            for t in range(n_t):
                objective_terms.append(cost * assign[(s, t, r)])
    if objective_terms:
        model.Minimize(sum(objective_terms))

    cp_solver = cp_model.CpSolver()
    cp_solver.parameters.max_time_in_seconds = 120.0
    # Search in parallel across all CPU cores. CP-SAT under a wall-clock time
    # limit is non-deterministic: the same model can solve quickly one run and
    # time out the next depending on machine load. Using every core makes the
    # solver far more likely to find a solution we know exists before the limit.
    cp_solver.parameters.num_search_workers = os.cpu_count() or 8
    status_code = cp_solver.Solve(model)

    status_map = {
        cp_model.OPTIMAL: "optimal",
        cp_model.FEASIBLE: "feasible",
        cp_model.INFEASIBLE: "infeasible",
        cp_model.UNKNOWN: "unknown",
    }
    status = status_map.get(status_code, "unknown")

    assignments = []
    if status_code in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        for s, session in enumerate(sessions):
            for t in range(n_t):
                for r, room in enumerate(rooms):
                    if cp_solver.Value(assign[(s, t, r)]):
                        assignments.append(SolverAssignment(
                            session=session,
                            time_slot_id=timeslots[t]["id"],
                            room_id=room["id"],
                            is_overcapacity=session.population > room["capacity"],
                        ))

    return SolverResult(
        assignments=assignments,
        solve_time_seconds=cp_solver.WallTime(),
        status=status,
    )
