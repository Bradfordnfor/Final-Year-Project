from tests.conftest import make_university


def _make_level(client, headers):
    uni = make_university(client, headers)
    fac = client.post("/faculties/", json={
        "name": "FET", "code": "FET", "university_id": uni["id"],
    }, headers=headers).json()
    dept = client.post("/departments/", json={
        "name": "Computer Engineering", "code": "CEF", "faculty_id": fac["id"],
    }, headers=headers).json()
    level = client.post("/levels/", json={
        "number": 400, "department_id": dept["id"],
    }, headers=headers).json()
    return dept, level


def test_class_accepts_track(client, auth_headers):
    _dept, level = _make_level(client, auth_headers)
    r = client.post("/classes/", json={
        "name": "CE400 Software", "population": 120,
        "level_id": level["id"], "track": "Software",
    }, headers=auth_headers)
    assert r.status_code == 201
    assert r.json()["track"] == "Software"


def test_class_track_defaults_to_null(client, auth_headers):
    _dept, level = _make_level(client, auth_headers)
    r = client.post("/classes/", json={
        "name": "CE400", "population": 200, "level_id": level["id"],
    }, headers=auth_headers)
    assert r.status_code == 201
    assert r.json()["track"] is None


def test_course_accepts_class_id(client, auth_headers):
    dept, level = _make_level(client, auth_headers)
    cls = client.post("/classes/", json={
        "name": "CE400 Software", "population": 120,
        "level_id": level["id"], "track": "Software",
    }, headers=auth_headers).json()
    r = client.post("/courses/", json={
        "code": "CEF440", "name": "Internet Programming",
        "level_id": level["id"], "department_id": dept["id"],
        "class_id": cls["id"], "weekly_hours": 2, "semester": 1,
    }, headers=auth_headers)
    assert r.status_code == 201
    assert r.json()["class_id"] == cls["id"]


def test_course_class_id_defaults_to_null(client, auth_headers):
    dept, level = _make_level(client, auth_headers)
    r = client.post("/courses/", json={
        "code": "CEF441", "name": "Common Course",
        "level_id": level["id"], "department_id": dept["id"],
        "weekly_hours": 2, "semester": 1,
    }, headers=auth_headers)
    assert r.status_code == 201
    assert r.json()["class_id"] is None
