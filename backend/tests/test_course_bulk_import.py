import io
from openpyxl import Workbook
from tests.conftest import make_university


def _login(client, email, password="password123"):
    r = client.post("/auth/login", json={"email": email, "password": password})
    return r.json()["access_token"]


def _headers(token):
    return {"Authorization": f"Bearer {token}"}


def setup_faculty_head(client, auth_headers, level_number=400):
    """Create uni + faculty + department + level + an active faculty head.

    Returns dict with uni, faculty, dept and the head's auth headers.
    """
    uni = make_university(client, auth_headers)
    fac = client.post("/faculties/", json={
        "name": "FET", "code": "FET", "university_id": uni["id"],
    }, headers=auth_headers).json()
    dept = client.post("/departments/", json={
        "name": "Computer Engineering", "code": "CEF", "faculty_id": fac["id"],
    }, headers=auth_headers).json()
    client.post("/levels/", json={"number": level_number, "department_id": dept["id"]},
                headers=auth_headers)
    client.post("/users/", json={
        "email": "head@test.com", "password": "password123",
        "full_name": "Head One", "role": "faculty_head",
        "university_id": uni["id"], "faculty_id": fac["id"],
    }, headers=auth_headers)
    token = _login(client, "head@test.com")
    return {"uni": uni, "fac": fac, "dept": dept, "headers": _headers(token)}


def _upload(client, headers, text, filename="courses.csv", dry_run=False):
    return client.post(
        "/courses/bulk-import/",
        params={"dry_run": dry_run},
        files={"file": (filename, io.BytesIO(text.encode()), "text/csv")},
        headers=headers,
    )


def test_faculty_head_imports_courses(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = (
        "code,name,level,department,semester\n"
        "CEF440,Internet Programming,400,Computer Engineering,1\n"
        "CEF445,Distributed Systems,400,Computer Engineering,2\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    assert r.status_code == 200
    body = r.json()
    assert len(body["created"]) == 2
    assert body["skipped"] == []
    # persisted
    listed = client.get(f"/courses/?department_id={ctx['dept']['id']}",
                        headers=ctx["headers"]).json()
    assert {c["code"] for c in listed} == {"CEF440", "CEF445"}


def test_faculty_head_dry_run_persists_nothing(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = "code,name,level,department\nCEF440,Internet Programming,400,Computer Engineering\n"
    r = _upload(client, ctx["headers"], csv_text, dry_run=True)
    assert r.status_code == 200
    assert r.json()["dry_run"] is True
    assert len(r.json()["created"]) == 1
    listed = client.get(f"/courses/?department_id={ctx['dept']['id']}",
                        headers=ctx["headers"]).json()
    assert listed == []


def test_faculty_head_skips_semester_zero(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = "code,name,level,department,semester\nCEF440,Internet Programming,400,Computer Engineering,0\n"
    r = _upload(client, ctx["headers"], csv_text)
    assert r.json()["created"] == []
    assert r.json()["skipped"][0]["code"] == "CEF440"
    assert "university admin" in r.json()["skipped"][0]["reason"]


def test_faculty_head_skips_unknown_department_and_level(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = (
        "code,name,level,department\n"
        "CEF440,Internet Programming,400,Nonexistent Dept\n"   # bad dept
        "CEF441,Networks,999,Computer Engineering\n"           # bad level
        "CEF442,Databases,400,Computer Engineering\n"          # good
    )
    r = _upload(client, ctx["headers"], csv_text)
    body = r.json()
    assert [c["code"] for c in body["created"]] == ["CEF442"]
    reasons = {s["code"]: s["reason"] for s in body["skipped"]}
    assert "not found" in reasons["CEF440"]
    assert "not found" in reasons["CEF441"]


def test_faculty_head_skips_duplicates(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = "code,name,level,department\nCEF440,Internet Programming,400,Computer Engineering\n"
    _upload(client, ctx["headers"], csv_text)                  # first import creates it
    r = _upload(client, ctx["headers"], csv_text)              # second should skip
    assert r.json()["created"] == []
    assert r.json()["skipped"][0]["reason"] == "already exists"


def test_faculty_head_skips_in_file_duplicate(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = (
        "code,name,level,department\n"
        "CEF440,Internet Programming,400,Computer Engineering\n"
        "CEF440,Internet Programming Again,400,Computer Engineering\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    assert len(r.json()["created"]) == 1
    assert r.json()["skipped"][0]["reason"] == "duplicate row in file"


def test_bulk_import_forbidden_for_super_admin(client, auth_headers):
    # auth_headers is the super_admin from conftest
    r = _upload(client, auth_headers,
                "code,name,level,department\nCEF440,X,400,Computer Engineering\n")
    assert r.status_code == 403


def test_bulk_import_rejects_unreadable_file(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    r = client.post(
        "/courses/bulk-import/",
        files={"file": ("courses.xlsx", io.BytesIO(b"not a real xlsx"), "application/octet-stream")},
        headers=ctx["headers"],
    )
    assert r.status_code == 400
    assert "CSV or Excel" in r.json()["detail"]
