from tests.conftest import make_university


def test_create_semester(client, auth_headers):
    uni = make_university(client, auth_headers)
    response = client.post("/semesters/", json={
        "name": "First Semester 2025/2026",
        "start_date": "2025-09-01",
        "end_date": "2026-01-31",
        "university_id": uni["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["name"] == "First Semester 2025/2026"


def test_list_semesters(client, auth_headers):
    response = client.get("/semesters/", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_add_timeslot_to_semester(client, auth_headers):
    uni = make_university(client, auth_headers)
    semester = client.post("/semesters/", json={
        "name": "S1", "start_date": "2025-09-01", "end_date": "2026-01-31", "university_id": uni["id"]
    }, headers=auth_headers).json()
    response = client.post("/semesters/timeslots/", json={
        "day_of_week": "Monday", "start_time": "07:00", "end_time": "09:00",
        "semester_id": semester["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["day_of_week"] == "Monday"


def test_list_timeslots_by_semester(client, auth_headers):
    uni = make_university(client, auth_headers)
    semester = client.post("/semesters/", json={
        "name": "S2", "start_date": "2025-09-01", "end_date": "2026-01-31", "university_id": uni["id"]
    }, headers=auth_headers).json()
    client.post("/semesters/timeslots/", json={
        "day_of_week": "Tuesday", "start_time": "09:00", "end_time": "11:00",
        "semester_id": semester["id"],
    }, headers=auth_headers)
    response = client.get(f"/semesters/{semester['id']}/timeslots", headers=auth_headers)
    assert response.status_code == 200
    assert len(response.json()) >= 1
