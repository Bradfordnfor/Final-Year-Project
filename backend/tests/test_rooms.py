from tests.conftest import make_university


def test_create_room(client, auth_headers):
    uni = make_university(client, auth_headers)
    building = client.post("/buildings/", json={"name": "FET Block", "university_id": uni["id"]},
                           headers=auth_headers).json()
    response = client.post("/rooms/", json={
        "name": "Amphi A", "capacity": 700, "room_type": "lecture_hall",
        "building_id": building["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Amphi A"
    assert data["capacity"] == 700
    assert data["is_active"] is True


def test_create_outdoor_room(client, auth_headers):
    uni = make_university(client, auth_headers)
    building = client.post("/buildings/", json={"name": "FAVM Area", "university_id": uni["id"]},
                           headers=auth_headers).json()
    response = client.post("/rooms/", json={
        "name": "Teaching Farm", "capacity": 100, "room_type": "outdoor",
        "building_id": building["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["room_type"] == "outdoor"


def test_create_room_invalid_type(client, auth_headers):
    uni = make_university(client, auth_headers)
    building = client.post("/buildings/", json={"name": "FET Block", "university_id": uni["id"]},
                           headers=auth_headers).json()
    response = client.post("/rooms/", json={
        "name": "Bad Room", "capacity": 50, "room_type": "studio",
        "building_id": building["id"],
    }, headers=auth_headers)
    assert response.status_code == 422


def test_list_rooms(client, auth_headers):
    response = client.get("/rooms/", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_update_room_capacity(client, auth_headers):
    uni = make_university(client, auth_headers)
    building = client.post("/buildings/", json={"name": "FET Block", "university_id": uni["id"]},
                           headers=auth_headers).json()
    room = client.post("/rooms/", json={
        "name": "Lab 1", "capacity": 30, "room_type": "lab", "building_id": building["id"],
    }, headers=auth_headers).json()
    response = client.put(f"/rooms/{room['id']}", json={"capacity": 40}, headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["capacity"] == 40


def test_delete_room(client, auth_headers):
    uni = make_university(client, auth_headers)
    building = client.post("/buildings/", json={"name": "FET Block", "university_id": uni["id"]},
                           headers=auth_headers).json()
    room = client.post("/rooms/", json={
        "name": "To Del", "capacity": 20, "room_type": "lab", "building_id": building["id"],
    }, headers=auth_headers).json()
    response = client.delete(f"/rooms/{room['id']}", headers=auth_headers)
    assert response.status_code == 204
