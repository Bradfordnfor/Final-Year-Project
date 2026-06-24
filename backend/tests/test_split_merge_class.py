"""Manual over-capacity relief: split a class out of a merged session, or
merge a class into another session of the same course.

These endpoints let a timetable officer fix an over-crowded room by hand after
generation — pulling one class into its own session, or folding a class into a
sibling session that still has room (within the overflow allowance)."""
from app.models.university import University, Faculty, Department
from app.models.academic import Level, Class, Semester, TimeSlot
from app.models.building import Building
from app.models.room import Room
from app.models.course import Course
from app.models.user import User, Lecturer
from app.models.timetable import (
    TimetableRun, TimetableRunFaculty, TimetableEntry, TimetableEntryClass,
)
from app.core.security import get_password_hash


def _setup(db):
    """Build a faculty with two equal classes, a small and a big room, two time
    slots, one course and one lecturer, plus a draft run. Returns the ids the
    tests need and an officer's auth token."""
    uni = University(name="UB", slug="ub-sm", overflow_threshold=0.2)
    db.add(uni); db.flush()
    fac = Faculty(name="FET", code="FET", sessions_per_week=2,
                  session_duration_hours=2, university_id=uni.id)
    db.add(fac); db.flush()
    dept = Department(name="Computer Engineering", code="CE", faculty_id=fac.id)
    db.add(dept); db.flush()
    level = Level(number=200, department_id=dept.id)
    db.add(level); db.flush()
    class_a = Class(name="CE200-A", population=150, level_id=level.id)
    class_b = Class(name="CE200-B", population=150, level_id=level.id)
    db.add_all([class_a, class_b]); db.flush()

    bld = Building(name="Block A", university_id=uni.id)
    db.add(bld); db.flush()
    small = Room(name="Room S", capacity=200, room_type="lecture_hall",
                 building_id=bld.id)
    big = Room(name="Hall B", capacity=400, room_type="lecture_hall",
               building_id=bld.id)
    db.add_all([small, big]); db.flush()

    sem = Semester(name="S1", start_date="2025-09-01", end_date="2026-01-31",
                   term=1, university_id=uni.id)
    db.add(sem); db.flush()
    slot1 = TimeSlot(day_of_week="Monday", start_time="08:00", end_time="10:00",
                     semester_id=sem.id)
    slot2 = TimeSlot(day_of_week="Tuesday", start_time="10:00", end_time="12:00",
                     semester_id=sem.id)
    db.add_all([slot1, slot2]); db.flush()

    lec_user = User(email="lec@test.com",
                    hashed_password=get_password_hash("pass123"),
                    full_name="Lec", role="lecturer", is_active=True,
                    university_id=uni.id)
    db.add(lec_user); db.flush()
    lec = Lecturer(user_id=lec_user.id, department_id=dept.id)
    db.add(lec); db.flush()

    course = Course(code="CE201", name="Data Structures", level_id=level.id,
                    department_id=dept.id, weekly_hours=2)
    db.add(course); db.flush()

    officer = User(email="off@test.com",
                   hashed_password=get_password_hash("pass123"),
                   full_name="Officer", role="timetable_officer",
                   is_active=True, university_id=uni.id)
    db.add(officer); db.flush()

    run = TimetableRun(name="Run 1", semester_id=sem.id, created_by=officer.id,
                       status="draft")
    db.add(run); db.flush()
    db.add(TimetableRunFaculty(run_id=run.id, faculty_id=fac.id))
    db.commit()

    return {
        "run": run.id, "course": course.id, "lec": lec.id,
        "class_a": class_a.id, "class_b": class_b.id,
        "small": small.id, "big": big.id, "slot1": slot1.id, "slot2": slot2.id,
    }


def _merged_entry(db, ids, classes, room, slot):
    """An entry holding the given classes in one room at one slot."""
    entry = TimetableEntry(run_id=ids["run"], course_id=ids["course"],
                           lecturer_id=ids["lec"], room_id=room,
                           time_slot_id=slot, week_pattern="every_week")
    db.add(entry); db.flush()
    for c in classes:
        db.add(TimetableEntryClass(entry_id=entry.id, class_id=c))
    db.commit()
    return entry.id


def _token(client):
    return client.post("/auth/login", json={
        "email": "off@test.com", "password": "pass123"}).json()["access_token"]


# ── Split ("take a class out") ────────────────────────────────────────────────

def test_split_relieves_overcapacity(client, db):
    ids = _setup(db)
    # 150 + 150 = 300 in a 200-seat room → over capacity.
    entry = _merged_entry(db, ids, [ids["class_a"], ids["class_b"]],
                          ids["small"], ids["slot1"])
    token = _token(client)

    resp = client.post(
        f"/runs/{ids['run']}/entries/{entry}/split-class",
        json={"class_id": ids["class_b"], "new_time_slot_id": ids["slot2"],
              "new_room_id": ids["big"]},
        headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200, resp.text
    new_id = resp.json()["new_entry_id"]

    db.expire_all()
    src = db.get(TimetableEntry, entry)
    new = db.get(TimetableEntry, new_id)
    assert [ec.class_id for ec in src.entry_classes] == [ids["class_a"]]
    assert src.is_overcapacity is False          # 150 now fits the 200-seat room
    assert src.is_merged is False                # only one class left
    assert [ec.class_id for ec in new.entry_classes] == [ids["class_b"]]
    assert new.room_id == ids["big"]


def test_split_rejects_single_class_session(client, db):
    ids = _setup(db)
    entry = _merged_entry(db, ids, [ids["class_a"]], ids["small"], ids["slot1"])
    token = _token(client)

    resp = client.post(
        f"/runs/{ids['run']}/entries/{entry}/split-class",
        json={"class_id": ids["class_a"], "new_time_slot_id": ids["slot2"],
              "new_room_id": ids["big"]},
        headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 400


def test_split_rejects_room_clash(client, db):
    ids = _setup(db)
    entry = _merged_entry(db, ids, [ids["class_a"], ids["class_b"]],
                          ids["small"], ids["slot1"])
    token = _token(client)

    # Target the same room/slot the session itself already uses → clash.
    resp = client.post(
        f"/runs/{ids['run']}/entries/{entry}/split-class",
        json={"class_id": ids["class_b"], "new_time_slot_id": ids["slot1"],
              "new_room_id": ids["small"]},
        headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 409


# ── Merge ("put a class in") ──────────────────────────────────────────────────

def test_merge_folds_class_into_sibling_and_deletes_emptied_source(client, db):
    ids = _setup(db)
    target = _merged_entry(db, ids, [ids["class_a"]], ids["big"], ids["slot1"])
    source = _merged_entry(db, ids, [ids["class_b"]], ids["small"], ids["slot2"])
    token = _token(client)

    # 150 + 150 = 300 ≤ 400 * 1.2 → fits.
    resp = client.post(
        f"/runs/{ids['run']}/entries/{source}/merge-class",
        json={"class_id": ids["class_b"], "target_entry_id": target},
        headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200, resp.text

    db.expire_all()
    tgt = db.get(TimetableEntry, target)
    assert sorted(ec.class_id for ec in tgt.entry_classes) == \
        sorted([ids["class_a"], ids["class_b"]])
    assert tgt.is_merged is True
    assert db.get(TimetableEntry, source) is None   # emptied source removed


def test_merge_rejects_when_target_room_too_small(client, db):
    ids = _setup(db)
    # Target is the 200-seat room; 150 + 150 = 300 > 200 * 1.2 = 240.
    target = _merged_entry(db, ids, [ids["class_a"]], ids["small"], ids["slot1"])
    source = _merged_entry(db, ids, [ids["class_b"]], ids["big"], ids["slot2"])
    token = _token(client)

    resp = client.post(
        f"/runs/{ids['run']}/entries/{source}/merge-class",
        json={"class_id": ids["class_b"], "target_entry_id": target},
        headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 409


def test_merge_rejects_different_course(client, db):
    ids = _setup(db)
    # A second course → the two sessions are not siblings.
    other = Course(code="CE202", name="Algorithms", level_id=None,
                   department_id=None, weekly_hours=2)
    db.add(other); db.commit()
    target = _merged_entry(db, ids, [ids["class_a"]], ids["big"], ids["slot1"])
    source = TimetableEntry(run_id=ids["run"], course_id=other.id,
                            lecturer_id=ids["lec"], room_id=ids["small"],
                            time_slot_id=ids["slot2"], week_pattern="every_week")
    db.add(source); db.flush()
    db.add(TimetableEntryClass(entry_id=source.id, class_id=ids["class_b"]))
    db.commit()
    token = _token(client)

    resp = client.post(
        f"/runs/{ids['run']}/entries/{source.id}/merge-class",
        json={"class_id": ids["class_b"], "target_entry_id": target},
        headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 400
