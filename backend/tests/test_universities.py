from tests.conftest import make_university


def test_create_university(client, auth_headers):
    response = client.post("/universities/", json={
        "name": "University of Buea",
        "slug": "ub",
        "overflow_threshold": 0.20,
        "admin_full_name": "UB Admin",
        "admin_email": "admin_ub@test.com",
    }, headers=auth_headers)
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "University of Buea"
    assert data["slug"] == "ub"
    # the response now also reports the created admin account
    assert data["admin_email"] == "admin_ub@test.com"


def test_list_universities(client, auth_headers):
    make_university(client, auth_headers)
    response = client.get("/universities/", headers=auth_headers)
    assert response.status_code == 200
    assert len(response.json()) == 1


def test_get_university_not_found(client, auth_headers):
    response = client.get("/universities/999", headers=auth_headers)
    assert response.status_code == 404


def test_update_university(client, auth_headers):
    uid = make_university(client, auth_headers)["id"]
    response = client.put(f"/universities/{uid}", json={
        "name": "University of Buea Updated",
        "slug": "ub",
        "overflow_threshold": 0.25,
    }, headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["name"] == "University of Buea Updated"


def test_delete_university(client, auth_headers):
    uid = make_university(client, auth_headers)["id"]
    response = client.delete(f"/universities/{uid}", headers=auth_headers)
    assert response.status_code == 204


def test_delete_university_with_data_cascades(client, auth_headers):
    """A super admin deleting a university must remove its owned data too,
    not crash on a foreign-key/NOT NULL violation."""
    uni = make_university(client, auth_headers, slug="ub-cascade")
    fac = client.post("/faculties/", json={
        "name": "FET", "code": "FET", "university_id": uni["id"],
    }, headers=auth_headers).json()
    client.post("/buildings/", json={
        "name": "Block A", "university_id": uni["id"],
    }, headers=auth_headers)
    client.post("/semesters/", json={
        "name": "S1", "start_date": "2025-09-01", "end_date": "2026-01-31",
        "university_id": uni["id"],
    }, headers=auth_headers)

    response = client.delete(f"/universities/{uni['id']}", headers=auth_headers)
    assert response.status_code == 204

    # the university and its children are gone
    assert client.get(f"/universities/{uni['id']}", headers=auth_headers).status_code == 404
    faculties = client.get("/faculties/", headers=auth_headers).json()
    assert all(f["id"] != fac["id"] for f in faculties)
