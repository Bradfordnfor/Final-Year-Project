"""Tests for the timetable run API (/runs/)."""
from tests.conftest import make_university


def _semester(client, auth_headers, slug="ub"):
    uni = make_university(client, auth_headers, slug=slug)
    sem = client.post("/semesters/", json={
        "name": "S1 2025", "start_date": "2025-09-01",
        "end_date": "2026-01-31", "university_id": uni["id"],
    }, headers=auth_headers).json()
    return uni, sem


def _create_run(client, auth_headers, sem, faculty_ids=None, building_ids=None):
    return client.post("/runs/", json={
        "name": "Run 1", "semester_id": sem["id"],
        "faculty_ids": faculty_ids or [], "building_ids": building_ids or [],
    }, headers=auth_headers).json()


def test_create_run(client, auth_headers):
    _uni, sem = _semester(client, auth_headers)
    response = client.post("/runs/", json={
        "name": "Run 1", "semester_id": sem["id"],
        "faculty_ids": [], "building_ids": [],
    }, headers=auth_headers)
    assert response.status_code == 201
    data = response.json()
    assert data["status"] == "draft"
    assert data["semester_id"] == sem["id"]


def test_list_runs(client, auth_headers):
    response = client.get("/runs/", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_get_run(client, auth_headers):
    _uni, sem = _semester(client, auth_headers)
    run = _create_run(client, auth_headers, sem)
    response = client.get(f"/runs/{run['id']}", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["id"] == run["id"]


def test_delete_run(client, auth_headers):
    _uni, sem = _semester(client, auth_headers)
    run = _create_run(client, auth_headers, sem)
    response = client.delete(f"/runs/{run['id']}", headers=auth_headers)
    assert response.status_code == 204


def test_job_status_when_no_job(client, auth_headers):
    _uni, sem = _semester(client, auth_headers)
    run = _create_run(client, auth_headers, sem)
    response = client.get(f"/runs/{run['id']}/job-status", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["status"] == "no_job"


def test_cannot_publish_a_draft(client, auth_headers):
    _uni, sem = _semester(client, auth_headers)
    run = _create_run(client, auth_headers, sem)
    response = client.post(f"/runs/{run['id']}/publish", headers=auth_headers)
    assert response.status_code == 400


def test_submit_for_review_requires_a_faculty_head(client, auth_headers):
    uni, sem = _semester(client, auth_headers)
    fac = client.post("/faculties/", json={
        "name": "FET", "code": "FET", "university_id": uni["id"],
    }, headers=auth_headers).json()
    run = _create_run(client, auth_headers, sem, faculty_ids=[fac["id"]])

    # No head yet -> submission is rejected
    blocked = client.post(f"/runs/{run['id']}/submit-for-review", headers=auth_headers)
    assert blocked.status_code == 400

    # Assign a head, then submission advances the run to under_review
    client.post("/users/", json={
        "email": "fhead@ub.cm",
        "full_name": "FET Head", "role": "faculty_head", "faculty_id": fac["id"],
    }, headers=auth_headers)
    ok = client.post(f"/runs/{run['id']}/submit-for-review", headers=auth_headers)
    assert ok.status_code == 200
    assert ok.json()["status"] == "under_review"
