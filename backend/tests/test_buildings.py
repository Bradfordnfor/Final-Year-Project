def test_create_building(client, auth_headers):
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers).json()
    response = client.post("/buildings/", json={
        "name": "FET Main Block",
        "description": "Faculty of Engineering and Technology building",
        "university_id": uni["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "FET Main Block"
    assert data["university_id"] == uni["id"]


def test_create_building_no_description(client, auth_headers):
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers).json()
    response = client.post("/buildings/", json={
        "name": "Amphi Complex", "university_id": uni["id"],
    }, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["description"] is None


def test_list_buildings(client, auth_headers):
    response = client.get("/buildings/", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_get_building_not_found(client, auth_headers):
    response = client.get("/buildings/999", headers=auth_headers)
    assert response.status_code == 404


def test_update_building(client, auth_headers):
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers).json()
    building = client.post("/buildings/", json={"name": "Old Name", "university_id": uni["id"]},
                           headers=auth_headers).json()
    response = client.put(f"/buildings/{building['id']}", json={"name": "New Name"}, headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["name"] == "New Name"


def test_delete_building(client, auth_headers):
    uni = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers).json()
    building = client.post("/buildings/", json={"name": "To Delete", "university_id": uni["id"]},
                           headers=auth_headers).json()
    response = client.delete(f"/buildings/{building['id']}", headers=auth_headers)
    assert response.status_code == 204
