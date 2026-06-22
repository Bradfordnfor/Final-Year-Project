"""One-off: delete the broken Run 2, regenerate Run 1 with the current engine,
and print case-study figures + a correctness check. Run from backend/:

    ./venv/Scripts/python.exe scripts/regen_case_study.py
"""
import json
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.database import SessionLocal
from app.models.timetable import TimetableRun, TimetableEntry, TimetableConflict
from app.models.course import Course
from app.routers.timetable import clear_run_result
from app.solver.db_preprocessor import build_solver_input
from app.solver.solver import solve_timetable
from app.solver.postprocessor import save_solver_result

db = SessionLocal()

# 1. Delete the broken, wrongly-published Run 2 (cascades to its rows).
run2 = db.get(TimetableRun, 2)
if run2:
    db.delete(run2)
    db.commit()
    print("Deleted Run 2 (corrupted, published).")

# 2. Regenerate Run 1 with the current engine.
run = db.get(TimetableRun, 1)
faculty_ids = [rf.faculty_id for rf in run.faculties]
building_ids = [rb.building_id for rb in run.buildings]

clear_run_result(run.id, db)
solver_input, conflicts = build_solver_input(
    run.id, run.semester_id, faculty_ids, building_ids, db)
for c in conflicts:
    db.add(TimetableConflict(
        run_id=run.id, conflict_type=c.conflict_type,
        course_id=c.course_id, class_id=c.class_id,
        details=json.dumps({"groups_needed": c.groups_needed,
                            "sessions_available": c.sessions_available,
                            "message": c.details}),
    ))
db.commit()

result = solve_timetable(solver_input)
if result.status in ("optimal", "feasible"):
    save_solver_result(run, result, db)
    run.generated_at = datetime.utcnow()
    db.commit()

print(f"\nSolve status: {result.status}")
print(f"Solve time:   {result.solve_time_seconds:.2f} s")
print(f"Sessions to place: {len(solver_input.sessions)} | "
      f"time slots: {len(solver_input.time_slots)} | "
      f"rooms (incl. virtual): {len(solver_input.rooms)}")

# 3. Figures from the stored result.
entries = db.query(TimetableEntry).filter(TimetableEntry.run_id == run.id).all()
courses = {e.course_id for e in entries}
uni_wide = {e.course_id for e in entries
            if (db.get(Course, e.course_id) and
                db.get(Course, e.course_id).department_id is None)}
classes = {ec.class_id for e in entries for ec in e.entry_classes}
print("\n--- CASE STUDY FIGURES (Run 1) ---")
print(f"sessions placed (entries):    {len(entries)}")
print(f"distinct courses scheduled:   {len(courses)} "
      f"({len(uni_wide)} university-wide)")
print(f"classes covered:              {len(classes)}")
print(f"lecturers involved:           {len({e.lecturer_id for e in entries})}")
print(f"rooms used:                   {len({e.room_id for e in entries if e.room_id is not None})}")
print(f"time slots used:              {len({e.time_slot_id for e in entries})}")
print(f"overcapacity entries:         {sum(1 for e in entries if e.is_overcapacity)}")
print(f"merged (multi-class) entries: {sum(1 for e in entries if e.is_merged)}")
print(f"off-site (no room) entries:   {sum(1 for e in entries if e.room_id is None)}")
print(f"conflicts flagged:            {db.query(TimetableConflict).filter(TimetableConflict.run_id == run.id).count()}")

# 4. Correctness check — the hard constraints must hold.
class_slot = Counter((ec.class_id, e.time_slot_id)
                     for e in entries for ec in e.entry_classes)
lect_slot = Counter((e.lecturer_id, e.time_slot_id) for e in entries)
room_slot = Counter((e.room_id, e.time_slot_id)
                    for e in entries if e.room_id is not None)
print("\n--- CORRECTNESS (must all be 0) ---")
print(f"class double-bookings:    {sum(1 for c in class_slot.values() if c > 1)}")
print(f"lecturer double-bookings: {sum(1 for c in lect_slot.values() if c > 1)}")
print(f"room double-bookings:     {sum(1 for c in room_slot.values() if c > 1)}")

db.close()
