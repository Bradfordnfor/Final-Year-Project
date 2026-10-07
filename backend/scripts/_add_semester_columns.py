"""One-off schema update: add courses.semester and semesters.term to the live
database. Idempotent (ADD COLUMN IF NOT EXISTS), safe to run more than once.
The project has no applied migrations, so this brings an existing Postgres DB
in line with the updated models."""
from sqlalchemy import text
from app.database import engine

statements = [
    "ALTER TABLE courses ADD COLUMN IF NOT EXISTS semester INTEGER NOT NULL DEFAULT 1",
    "ALTER TABLE semesters ADD COLUMN IF NOT EXISTS term INTEGER NOT NULL DEFAULT 1",
]

with engine.begin() as conn:
    for stmt in statements:
        conn.execute(text(stmt))
        print("OK:", stmt)
print("Done.")
