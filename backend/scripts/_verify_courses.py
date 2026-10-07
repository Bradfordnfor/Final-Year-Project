from app.database import SessionLocal
from app.models.academic import Class
from app.models.course import Course, SharedCourse

db = SessionLocal()
tot = db.query(Course).count()
sc = db.query(SharedCourse).count()
print(f"Total courses: {tot} | shared (joint) links: {sc}")

labs = db.query(Course).filter(Course.room_type_required != "lecture_hall").all()
print("Non-lecture rooms:",
      ", ".join(f"{c.code}({c.room_type_required},{c.weekly_hours}/wk)" for c in labs))

print("All courses semester=1:", all(c.semester == 1 for c in db.query(Course).all()))

print("--- joint courses: home class + also attended by ---")
for c in db.query(Course).all():
    links = db.query(SharedCourse).filter(SharedCourse.course_id == c.id).all()
    if links:
        home = db.query(Class).filter(Class.level_id == c.level_id).first()
        shares = [db.get(Class, l.class_id).name for l in links]
        print(f"  {c.code}: {home.name} + {shares}")
db.close()
