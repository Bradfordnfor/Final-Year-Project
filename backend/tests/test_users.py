def setup_department(client, auth_headers):
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers).json()
    faculty = client.post("/faculties/", json={"name": "FET", "code": "FET", "university_id": uni["id"]},
                          headers=auth_headers).json()
    return client.post("/departments/", json={"name": "EE", "code": "EE", "faculty_id": faculty["id"]},
                       headers=auth_headers).json()


def test_create_user(client, auth_headers):
    response = client.post("/users/", json={
        "email": "lecturer@ub.cm", "password": "pass123",
        "full_name": "Dr. Smith", "role": "lecturer",
    }, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["email"] == "lecturer@ub.cm"
    assert response.json()["role"] == "lecturer"


def test_list_users(client, auth_headers):
    response = client.get("/users/", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_create_lecturer_profile(client, auth_headers):
    dept = setup_department(client, auth_headers)
    user = client.post("/users/", json={
        "email": "lect2@ub.cm", "password": "pass123",
        "full_name": "Dr. Jones", "role": "lecturer",
    }, headers=auth_headers).json()
    response = client.post("/lecturers/", json={
        "user_id": user["id"], "department_id": dept["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["user_id"] == user["id"]


def test_list_lecturers(client, auth_headers):
    response = client.get("/lecturers/", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_create_student_profile(client, auth_headers):
    dept = setup_department(client, auth_headers)
    level = client.post("/levels/", json={"number": 300, "department_id": dept["id"]},
                        headers=auth_headers).json()
    cls = client.post("/classes/", json={"name": "EE300", "population": 100, "level_id": level["id"]},
                      headers=auth_headers).json()
    user = client.post("/users/", json={
        "email": "student@ub.cm", "password": "pass123",
        "full_name": "Jane Doe", "role": "student",
    }, headers=auth_headers).json()
    response = client.post("/students/", json={
        "user_id": user["id"], "class_id": cls["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["user_id"] == user["id"]


def test_add_lecturer_availability(client, auth_headers):
    dept = setup_department(client, auth_headers)
    user = client.post("/users/", json={
        "email": "lect3@ub.cm", "password": "pass123",
        "full_name": "Dr. Brown", "role": "lecturer",
    }, headers=auth_headers).json()
    lecturer = client.post("/lecturers/", json={
        "user_id": user["id"], "department_id": dept["id"],
    }, headers=auth_headers).json()
    uni = client.post("/universities/", json={"name": "UB2", "slug": "ub2"}, headers=auth_headers).json()
    semester = client.post("/semesters/", json={
        "name": "S1", "start_date": "2025-09-01", "end_date": "2026-01-31", "university_id": uni["id"],
    }, headers=auth_headers).json()
    timeslot = client.post("/semesters/timeslots/", json={
        "day_of_week": "Friday", "start_time": "07:00", "end_time": "09:00",
        "semester_id": semester["id"],
    }, headers=auth_headers).json()
    response = client.post("/lecturers/availability/", json={
        "lecturer_id": lecturer["id"], "time_slot_id": timeslot["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["lecturer_id"] == lecturer["id"]
