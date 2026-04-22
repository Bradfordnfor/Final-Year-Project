def setup_semester_and_department(client, auth_headers):
    uni = client.post("/universities/", json={"name": "UB TT", "slug": "ub-tt"},
                      headers=auth_headers).json()
    fac = client.post("/faculties/", json={"name": "FET", "code": "FET-TT", "university_id": uni["id"]},
                      headers=auth_headers).json()
    dept = client.post("/departments/", json={"name": "EE", "code": "EE-TT", "faculty_id": fac["id"]},
                       headers=auth_headers).json()
    sem = client.post("/semesters/", json={
        "name": "S1 2025", "start_date": "2025-09-01",
        "end_date": "2026-01-31", "university_id": uni["id"],
    }, headers=auth_headers).json()
    return sem, dept


def test_create_timetable(client, auth_headers):
    sem, dept = setup_semester_and_department(client, auth_headers)
    response = client.post("/timetables/", json={
        "semester_id": sem["id"], "department_id": dept["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    data = response.json()
    assert data["status"] == "draft"
    assert data["semester_id"] == sem["id"]


def test_list_timetables(client, auth_headers):
    response = client.get("/timetables/", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_get_timetable(client, auth_headers):
    sem, dept = setup_semester_and_department(client, auth_headers)
    tt = client.post("/timetables/", json={
        "semester_id": sem["id"], "department_id": dept["id"],
    }, headers=auth_headers).json()
    response = client.get(f"/timetables/{tt['id']}", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["id"] == tt["id"]


def test_advance_timetable_status(client, auth_headers):
    sem, dept = setup_semester_and_department(client, auth_headers)
    tt = client.post("/timetables/", json={
        "semester_id": sem["id"], "department_id": dept["id"],
    }, headers=auth_headers).json()
    response = client.post(f"/timetables/{tt['id']}/advance-status", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["status"] == "under_review"


def test_cannot_publish_without_approval(client, auth_headers):
    sem, dept = setup_semester_and_department(client, auth_headers)
    tt = client.post("/timetables/", json={
        "semester_id": sem["id"], "department_id": dept["id"],
    }, headers=auth_headers).json()
    response = client.post(f"/timetables/{tt['id']}/publish", headers=auth_headers)
    assert response.status_code == 400


def test_get_generation_job_status(client, auth_headers):
    sem, dept = setup_semester_and_department(client, auth_headers)
    tt = client.post("/timetables/", json={
        "semester_id": sem["id"], "department_id": dept["id"],
    }, headers=auth_headers).json()
    response = client.get(f"/timetables/{tt['id']}/job-status", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["status"] == "no_job"
