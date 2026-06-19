from tests.conftest import make_university


def setup_department(client, auth_headers):
    uni = make_university(client, auth_headers)
    faculty = client.post("/faculties/", json={"name": "FET", "code": "FET", "university_id": uni["id"]},
                          headers=auth_headers).json()
    return client.post("/departments/", json={"name": "EE", "code": "EE", "faculty_id": faculty["id"]},
                       headers=auth_headers).json()


def setup_class(client, auth_headers, dept):
    level = client.post("/levels/", json={"number": 300, "department_id": dept["id"]},
                        headers=auth_headers).json()
    return client.post("/classes/", json={"name": "EE300", "population": 120, "level_id": level["id"]},
                       headers=auth_headers).json()


def test_create_course(client, auth_headers):
    dept = setup_department(client, auth_headers)
    response = client.post("/courses/", json={
        "code": "ENG 116", "name": "Technical Communication",
        "room_type_required": "lecture_hall", "department_id": dept["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["code"] == "ENG 116"


def test_create_course_requires_lab(client, auth_headers):
    dept = setup_department(client, auth_headers)
    response = client.post("/courses/", json={
        "code": "EE LAB 201", "name": "Circuits Lab",
        "room_type_required": "lab", "department_id": dept["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["room_type_required"] == "lab"


def test_list_courses(client, auth_headers):
    response = client.get("/courses/", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_add_shared_course(client, auth_headers):
    dept = setup_department(client, auth_headers)
    course = client.post("/courses/", json={
        "code": "MTH 201", "name": "Mathematics", "department_id": dept["id"],
    }, headers=auth_headers).json()
    cls = setup_class(client, auth_headers, dept)
    response = client.post("/courses/shared/", json={
        "course_id": course["id"], "class_id": cls["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["course_id"] == course["id"]


def test_update_course(client, auth_headers):
    dept = setup_department(client, auth_headers)
    course = client.post("/courses/", json={
        "code": "OLD 101", "name": "Old Course", "department_id": dept["id"],
    }, headers=auth_headers).json()
    response = client.put(f"/courses/{course['id']}", json={"name": "New Name"},
                          headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["name"] == "New Name"


def test_delete_course(client, auth_headers):
    dept = setup_department(client, auth_headers)
    course = client.post("/courses/", json={
        "code": "DEL 101", "name": "Del Course", "department_id": dept["id"],
    }, headers=auth_headers).json()
    response = client.delete(f"/courses/{course['id']}", headers=auth_headers)
    assert response.status_code == 204
