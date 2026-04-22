def test_create_university(client, auth_headers):
    response = client.post("/universities/", json={
        "name": "University of Buea",
        "slug": "ub",
        "overflow_threshold": 0.20,
    }, headers=auth_headers)
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "University of Buea"
    assert data["slug"] == "ub"


def test_list_universities(client, auth_headers):
    client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers)
    response = client.get("/universities/", headers=auth_headers)
    assert response.status_code == 200
    assert len(response.json()) == 1


def test_get_university_not_found(client, auth_headers):
    response = client.get("/universities/999", headers=auth_headers)
    assert response.status_code == 404


def test_update_university(client, auth_headers):
    create = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers)
    uid = create.json()["id"]
    response = client.put(f"/universities/{uid}", json={
        "name": "University of Buea Updated",
        "slug": "ub",
        "overflow_threshold": 0.25,
    }, headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["name"] == "University of Buea Updated"


def test_delete_university(client, auth_headers):
    create = client.post("/universities/", json={"name": "UB", "slug": "ub"}, headers=auth_headers)
    uid = create.json()["id"]
    response = client.delete(f"/universities/{uid}", headers=auth_headers)
    assert response.status_code == 204
