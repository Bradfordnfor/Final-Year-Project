"""A lecturer may manage their own availability (but not another lecturer's).

Regression tests for the 403 a lecturer hit when setting availability: the
endpoints required a timetable officer, and the client sent the User id where a
Lecturer profile id was expected.
"""
from app.models.university import University, Faculty, Department
from app.models.academic import Semester, TimeSlot
from app.models.user import User, Lecturer
from app.core.security import get_password_hash


def _make_lecturer_user(db, email="lect@test.com"):
    uni = University(name="UB", slug="ub-av", overflow_threshold=0.2)
    db.add(uni); db.flush()
    fac = Faculty(name="FET", code="FET", sessions_per_week=2,
                  session_duration_hours=2, university_id=uni.id)
    db.add(fac); db.flush()
    dept = Department(name="EE", code="EE", faculty_id=fac.id)
    db.add(dept); db.flush()
    sem = Semester(name="S1", start_date="2025-09-01", end_date="2026-01-31",
                   is_active=True, university_id=uni.id)
    db.add(sem); db.flush()
    slot = TimeSlot(day_of_week="Monday", start_time="07:00",
                    end_time="09:00", semester_id=sem.id)
    db.add(slot); db.flush()
    user = User(email=email, hashed_password=get_password_hash("pass123"),
                full_name="Dr Lect", role="lecturer", is_active=True,
                department_id=dept.id)
    db.add(user); db.commit(); db.refresh(user); db.refresh(slot)
    return user, slot, dept


def _login(client, email):
    resp = client.post("/auth/login", json={"email": email, "password": "pass123"})
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}


def test_lecturer_me_auto_provisions_profile(client, db):
    user, _slot, _dept = _make_lecturer_user(db, email="lect2@test.com")
    headers = _login(client, user.email)
    assert db.query(Lecturer).filter(Lecturer.user_id == user.id).first() is None

    me = client.get("/lecturers/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["user_id"] == user.id

    db.expire_all()
    assert db.query(Lecturer).filter(Lecturer.user_id == user.id).first() is not None


def test_lecturer_can_set_own_availability(client, db):
    user, slot, _dept = _make_lecturer_user(db)
    headers = _login(client, user.email)

    lecturer_id = client.get("/lecturers/me", headers=headers).json()["id"]
    resp = client.post("/lecturers/availability/", json={
        "lecturer_id": lecturer_id, "time_slot_id": slot.id,
    }, headers=headers)
    assert resp.status_code == 201


def test_lecturer_cannot_set_another_lecturers_availability(client, db):
    user, slot, dept = _make_lecturer_user(db)
    headers = _login(client, user.email)
    client.get("/lecturers/me", headers=headers)  # provision own profile

    other_user = User(email="other@test.com",
                      hashed_password=get_password_hash("pass123"),
                      full_name="Other", role="lecturer", is_active=True,
                      department_id=dept.id)
    db.add(other_user); db.flush()
    other_lect = Lecturer(user_id=other_user.id, department_id=dept.id)
    db.add(other_lect); db.commit(); db.refresh(other_lect)

    resp = client.post("/lecturers/availability/", json={
        "lecturer_id": other_lect.id, "time_slot_id": slot.id,
    }, headers=headers)
    assert resp.status_code == 403
