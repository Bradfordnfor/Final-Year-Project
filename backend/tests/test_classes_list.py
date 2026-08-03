"""The /faculty-setup/classes endpoint labels timetable entries with the real
class name and population, and is reachable by a timetable officer."""
from app.models.university import University, Faculty, Department
from app.models.academic import Level, Class
from app.models.user import User
from app.core.security import get_password_hash
from tests.conftest import activate_user


def test_classes_endpoint_returns_name_and_population(client, db, admin_user):
    uni = University(name="UB", slug="ub-cls", overflow_threshold=0.2)
    db.add(uni); db.flush()
    fac = Faculty(name="FET", code="FET", sessions_per_week=2,
                  session_duration_hours=2, university_id=uni.id)
    db.add(fac); db.flush()
    dept = Department(name="Computer Engineering", code="CE", faculty_id=fac.id)
    db.add(dept); db.flush()
    level = Level(number=200, department_id=dept.id)
    db.add(level); db.flush()
    db.add(Class(name="CE200", population=180, level_id=level.id))
    db.add(User(email="off2@test.com",
                hashed_password=get_password_hash("pass123"),
                full_name="Officer", role="timetable_officer",
                is_active=True, university_id=uni.id))
    db.commit()
    activate_user("off2@test.com", password="pass123")

    token = client.post("/auth/login", json={
        "email": "off2@test.com", "password": "pass123"}).json()["access_token"]
    resp = client.get("/faculty-setup/classes",
                      headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    by_name = {c["name"]: c for c in resp.json()}
    assert "CE200" in by_name
    assert by_name["CE200"]["population"] == 180
