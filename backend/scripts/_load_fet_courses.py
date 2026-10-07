"""Load the FET case-study courses into the existing departments/levels.

Rules:
  - All courses are first semester (semester=1).
  - Room type / sessions come ONLY from a bracket in the title:
      (... lab ...) -> lab ;  (outdoor) -> outdoor ;  number in bracket -> sessions
      no bracket -> lecture_hall, 2 sessions/week.
  - A course code that appears under more than one department is a JOINT course:
    it is created once under a "home" department (chosen by code prefix) and
    linked to the exact class of each other department/level via SharedCourse.
Idempotent: existing courses/links are left alone. Prints a summary.
"""
import re
from app.database import SessionLocal
from app.models.university import Faculty, Department
from app.models.academic import Level, Class
from app.models.course import Course, SharedCourse

FACULTY_CODE = "FET"
PREFIX_DEPT = {"CEF": "CE", "EEF": "EE", "MEF": "ME", "CIV": "CIV", "FET": None}

# dept_code -> level_number -> ["CODE - title", ...]
DATA = {
    "CE": {
        200: [
            "CEF201 - analysis",
            "CEF203 - linear algebra",
            "CEF205 - introduction to computing",
            "CEF207 - computer programming I",
            "CEF211 - boolean algebra and logic circuits",
            "EEF261 - circuit analysis",
            "EEF269 - physics for engineering I",
        ],
        300: [
            "CEF331 - object oriented programming and UML",
            "CEF333 - hardware and software maintenance laboratory",
            "CEF341 - algorithms and data structures",
            "CEF345 - software development tools",
            "CEF347 - operating systems",
            "CEF349 - analysis and design of information systems",
            "EEF363 - analog electronics II",
            "EEF365 - microcontrollers and microprocessors",
            "EEF367 - digital electronics laboratory (electrical lab, 3)",
            "FET301 - statistics and probability",
        ],
        400: [
            "CEF401 - operational research",
            "CEF405 - analysis and design of algorithms",
            "CEF415 - technical writing",
            "CEF427 - advanced operating systems",
            "CEF431 - software quality : tools and methods",
            "CEF447 - data warehouse and data mining",
            "CEF451 - security of information systems and cybersecurity",
            "CEF473 - system administration (Unix, Linux, windows)",
            "CEF479 - computer networks laboratory (computer lab)",
            "EEF467 - feedback systems",
        ],
    },
    "EE": {
        200: [
            "EEF261 - circuit analysis",
            "EEF263 - digital electronics I",
            "EEF265 - signal and systems",
            "EEF267 - fundamentals of electrical engineering I",
            "CEF201 - analysis",
            "EEF269 - physics for engineering I",
            "CEF207 - programming I",
        ],
        300: [
            "CEF347 - operating systems",
            "EEF361 - electronic measurements",
            "EEF363 - analog electronics II",
            "EEF365 - micro-controllers and microprocessors",
            "EEF367 - digital electronics laboratory (electrical lab, 3)",
            "EEF333 - introduction to renewable energy",
            "EEF349 - fundamentals of electrical machines",
            "FET301 - probability and statistics",
        ],
        400: [
            "EEF467 - feedback systems",
            "EEF469 - microelectronics",
            "EEF481 - electric machines I",
            "EEF483 - power electronics and control",
            "EEF485 - sequence control lab (electrical lab)",
            "EEF487 - electrical power system engineering I",
            "EEF489 - electrical installations",
            "EEF491 - renewable energy components and technologies",
            "EEF493 - electrical transmission lines",
        ],
    },
    "CIV": {
        200: [
            "CIV213 - fundamentals of civil engineering",
            "CIV201 - computing 1 : general computing",
            "CIV203 - electromagnetism I",
            "CIV205 - mechanics I",
            "CIV207 - physics laboratory (CIV lab)",
            "CIV209 - real analysis I",
            "CIV211 - general algebra",
        ],
        300: [
            "CIV301 - programming and application software",
            "CIV303 - electrokinetics",
            "CIV305 - solid mechanics",
            "CIV307 - electric and electronic circuits",
            "CIV309 - probability and statistics",
            "CIV311 - series",
            "CIV313 - electrochemistry",
            "CIV315 - civil engineering materials",
        ],
        400: [
            "CIV401 - computer aided design/drawing (CAD)",
            "CIV405 - continuum mechanics",
            "CIV407 - construction laboratory : tools and material",
            "CIV409 - building design; architecture and technology",
            "CIV413 - geological engineering",
            "CIV415 - economy, management and entrepreneurship",
            "CIV417 - communication techniques",
            "CIV411 - acoustic and thermal comfort in buildings",
            "CIV433 - worshop practice (outdoor)",
        ],
    },
    "ME": {
        300: [
            "MEF365 - Mechanical vibrations",
            "MEF361 - mechanics II (Solid mechanics)",
            "MEF353 - Manufacturing technology",
            "MEF305 - Energy process and system engineering",
            "MEF303 - elasticity and strength of materials",
            "MEF301 - design I: conceptual design",
            "FET301 - probability and statistics",
        ],
        400: [
            "EEF467 - feedback systems",
            "EEF483 - power electronics and control",
            "MEF413 - industrial safety",
            "MEF437 - automation programming",
            "MEF455 - control and feedback engineering",
            "MEF469 - sensors, transducers and actuators",
            "MEF471 - Vehicle electronics and control",
            "MEF493 - Electrodynamics",
        ],
    },
}


def parse(raw):
    code, name = [x.strip() for x in raw.split(" - ", 1)]
    room, hours = "lecture_hall", 2
    m = re.search(r"\(([^)]*)\)", name)
    if m:
        inside = m.group(1).lower()
        if "outdoor" in inside:
            room = "outdoor"
        elif "lab" in inside:
            room = "lab"
        nums = re.findall(r"\d+", inside)
        if nums:
            hours = int(nums[0])
    clean = re.sub(r"\s*\([^)]*\)", "", name).strip()
    return code, clean, room, hours


def main():
    db = SessionLocal()
    fac = db.query(Faculty).filter(Faculty.code == FACULTY_CODE).first()
    if not fac:
        print("FET faculty not found"); return
    depts = {d.code: d for d in db.query(Department).filter(Department.faculty_id == fac.id).all()}

    def level_of(dc, num):
        return db.query(Level).filter(
            Level.department_id == depts[dc].id, Level.number == num).first()

    def class_of(level):
        return db.query(Class).filter(Class.level_id == level.id).first()

    # group occurrences by code
    occ = {}
    for dc, levels in DATA.items():
        for num, raws in levels.items():
            for raw in raws:
                code, name, room, hours = parse(raw)
                occ.setdefault(code, []).append(
                    dict(dc=dc, num=num, name=name, room=room, hours=hours))

    created, shared, skipped = [], [], []
    for code, occs in occ.items():
        target = PREFIX_DEPT.get(code[:3])
        home = next((o for o in occs if o["dc"] == target), None) or occs[0]
        level = level_of(home["dc"], home["num"])
        dept = depts[home["dc"]]
        course = db.query(Course).filter(
            Course.code == code, Course.department_id == dept.id).first()
        if course:
            skipped.append(code)
        else:
            course = Course(code=code, name=home["name"], room_type_required=home["room"],
                            level_id=level.id, department_id=dept.id,
                            weekly_hours=home["hours"], semester=1)
            db.add(course); db.flush()
            created.append((code, home["dc"], home["num"], home["room"], home["hours"]))
        for o in occs:
            if o is home:
                continue
            cls = class_of(level_of(o["dc"], o["num"]))
            exists = db.query(SharedCourse).filter(
                SharedCourse.course_id == course.id, SharedCourse.class_id == cls.id).first()
            if not exists:
                db.add(SharedCourse(course_id=course.id, class_id=cls.id))
                shared.append((code, home["dc"], home["num"], o["dc"], o["num"]))

    db.commit()

    print(f"\nCreated {len(created)} courses, {len(shared)} joint links, skipped {len(skipped)} existing.\n")
    by_dept = {}
    for code, dc, num, room, hrs in created:
        by_dept.setdefault(dc, []).append((num, code, room, hrs))
    for dc in sorted(by_dept):
        print(f"{dc}:")
        for num, code, room, hrs in sorted(by_dept[dc]):
            tag = "" if room == "lecture_hall" and hrs == 2 else f"   <-- {room}, {hrs}/wk"
            print(f"   L{num}  {code}{tag}")
    if shared:
        print("\nJoint courses (home -> also attended by):")
        for code, hdc, hnum, odc, onum in shared:
            print(f"   {code}: {hdc}{hnum} -> {odc}{onum}")
    if skipped:
        print(f"\nSkipped (already present): {', '.join(sorted(skipped))}")
    db.close()


if __name__ == "__main__":
    main()
