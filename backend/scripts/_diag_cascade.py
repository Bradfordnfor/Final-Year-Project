"""Diagnostic: run the university cascade against the REAL database inside a
transaction, then ROLL BACK so nothing is actually deleted. Prints the real
traceback if it fails. Safe to run repeatedly."""
import sys
import traceback

from app.database import SessionLocal
from app.routers.universities import _delete_university_cascade

university_id = int(sys.argv[1]) if len(sys.argv) > 1 else 1

db = SessionLocal()
try:
    _delete_university_cascade(db, university_id)
    print(f"OK: cascade for university {university_id} executed with no error (rolling back).")
except Exception:
    print(f"FAILED: cascade for university {university_id} raised:")
    traceback.print_exc()
finally:
    db.rollback()
    db.close()
    print("Rolled back — no data was changed.")
