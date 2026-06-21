from collections import defaultdict
from ortools.sat.python import cp_model
from app.solver.models import SolverInput, SolverAssignment, SolverResult


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
    cp_solver.parameters.max_time_in_seconds = 60.0
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
