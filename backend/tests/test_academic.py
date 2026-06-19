from tests.conftest import make_university


def setup_department(client, auth_headers):
    uni = make_university(client, auth_headers)
    faculty = client.post("/faculties/", json={"name": "FET", "code": "FET", "university_id": uni["id"]},
                          headers=auth_headers).json()
    return client.post("/departments/", json={"name": "EE", "code": "EE", "faculty_id": faculty["id"]},
                       headers=auth_headers).json()


def test_create_level(client, auth_headers):
    dept = setup_department(client, auth_headers)
    response = client.post("/levels/", json={"number": 300, "department_id": dept["id"]},
                           headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["number"] == 300


def test_list_levels(client, auth_headers):
    response = client.get("/levels/", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_create_class(client, auth_headers):
    dept = setup_department(client, auth_headers)
    level = client.post("/levels/", json={"number": 300, "department_id": dept["id"]},
                        headers=auth_headers).json()
    response = client.post("/classes/", json={
        "name": "EE300", "population": 120, "level_id": level["id"]
    }, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["name"] == "EE300"
    assert response.json()["population"] == 120


def test_list_classes(client, auth_headers):
    response = client.get("/classes/", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_create_group(client, auth_headers):
    dept = setup_department(client, auth_headers)
    level = client.post("/levels/", json={"number": 100, "department_id": dept["id"]},
                        headers=auth_headers).json()
    student_class = client.post("/classes/", json={"name": "EE100", "population": 80, "level_id": level["id"]},
                                headers=auth_headers).json()
    response = client.post("/groups/", json={"name": "A", "size": 40, "class_id": student_class["id"]},
                           headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["name"] == "A"
