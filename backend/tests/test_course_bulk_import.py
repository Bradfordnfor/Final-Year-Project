import io
from openpyxl import Workbook
from tests.conftest import make_university, activate_user


def _xlsx_bytes(rows):
    """rows: list of lists; first list is the header. Returns .xlsx bytes."""
    wb = Workbook()
    ws = wb.active
    for r in rows:
        ws.append(r)
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


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
        "email": "head@test.com",
        "full_name": "Head One", "role": "faculty_head",
        "university_id": uni["id"], "faculty_id": fac["id"],
    }, headers=auth_headers)
    activate_user("head@test.com")
    token = _login(client, "head@test.com")
    return {"uni": uni, "fac": fac, "dept": dept, "headers": _headers(token)}


def _add_dept_with_class(client, auth_headers, fac, name, code,
                         level_number=400, class_name=None, population=100,
                         with_class=True):
    """Add a department to `fac` with a Level `level_number` and (optionally) one Class.

    Returns {"dept", "level", "class"} (class is None when with_class=False).
    """
    dept = client.post("/departments/", json={
        "name": name, "code": code, "faculty_id": fac["id"],
    }, headers=auth_headers).json()
    level = client.post("/levels/", json={
        "number": level_number, "department_id": dept["id"],
    }, headers=auth_headers).json()
    cls = None
    if with_class:
        cls = client.post("/classes/", json={
            "name": class_name or f"{code}{level_number}",
            "population": population, "level_id": level["id"],
        }, headers=auth_headers).json()
    return {"dept": dept, "level": level, "class": cls}


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


def test_faculty_head_missing_required_column(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = "code,name,department\nCEF440,Internet Programming,Computer Engineering\n"  # no level
    r = _upload(client, ctx["headers"], csv_text)
    assert r.status_code == 400
    assert "code, name, level, department" in r.json()["detail"]


def test_bulk_import_forbidden_for_timetable_officer(client, auth_headers):
    uni = make_university(client, auth_headers)
    client.post("/users/", json={
        "email": "officer@test.com",
        "full_name": "Officer One", "role": "timetable_officer",
        "university_id": uni["id"],
    }, headers=auth_headers)
    activate_user("officer@test.com")
    token = _login(client, "officer@test.com")
    r = _upload(client, _headers(token),
                "code,name,level,department\nCEF440,X,400,Computer Engineering\n")
    assert r.status_code == 403


def _login_admin(client, auth_headers):
    """make_university creates a university admin admin_<slug>@test.com. Log in."""
    uni = make_university(client, auth_headers)
    token = _login(client, "admin_ub@test.com")
    return uni, _headers(token)


def test_university_admin_imports_year_long_courses(client, auth_headers):
    uni, admin_headers = _login_admin(client, auth_headers)
    csv_text = "code,name\nUB101,Use of English\nUB102,Civics\n"
    r = _upload(client, admin_headers, csv_text)
    assert r.status_code == 200
    body = r.json()
    assert len(body["created"]) == 2
    assert all(c["semester"] == 0 for c in body["created"])
    listed = client.get(f"/courses/?university_id={uni['id']}", headers=admin_headers).json()
    assert {c["code"] for c in listed} == {"UB101", "UB102"}
    assert all(c["department_id"] is None and c["semester"] == 0 for c in listed)


def test_university_admin_skips_duplicate(client, auth_headers):
    uni, admin_headers = _login_admin(client, auth_headers)
    csv_text = "code,name\nUB101,Use of English\n"
    _upload(client, admin_headers, csv_text)
    r = _upload(client, admin_headers, csv_text)
    assert r.json()["created"] == []
    assert r.json()["skipped"][0]["reason"] == "already exists"


def test_university_admin_missing_columns(client, auth_headers):
    _, admin_headers = _login_admin(client, auth_headers)
    r = _upload(client, admin_headers, "code\nUB101\n")   # no name column
    assert r.status_code == 400
    assert "code, name" in r.json()["detail"]


def _create_lecturer(client, auth_headers, uni, dept, fac, email, full_name):
    """Create a user + Lecturer profile in the given university/department/faculty.

    Returns the created lecturer dict (has "id").
    """
    user = client.post("/users/", json={
        "email": email,
        "full_name": full_name, "role": "lecturer",
        "university_id": uni["id"], "department_id": dept["id"], "faculty_id": fac["id"],
    }, headers=auth_headers).json()
    lect = client.post("/lecturers/", json={
        "user_id": user["id"], "department_id": dept["id"],
    }, headers=auth_headers).json()
    return lect


def test_faculty_head_import_matches_lecturer_exactly(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    lect = _create_lecturer(client, auth_headers, ctx["uni"], ctx["dept"], ctx["fac"],
                             "ateba.john@test.com", "Ateba John")
    csv_text = (
        "code,name,level,department,lecturer\n"
        "CEF440,Internet Programming,400,Computer Engineering,Dr. Ateba John\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    assert r.status_code == 200
    body = r.json()
    assert len(body["created"]) == 1
    assert body["created"][0]["lecturer_note"] is None
    listed = client.get(f"/courses/?department_id={ctx['dept']['id']}",
                        headers=ctx["headers"]).json()
    course = next(c for c in listed if c["code"] == "CEF440")
    assert course["lecturer_id"] == lect["id"]


def test_faculty_head_import_lecturer_not_found(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = (
        "code,name,level,department,lecturer\n"
        "CEF440,Internet Programming,400,Computer Engineering,Nobody Here\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    assert r.status_code == 200
    body = r.json()
    assert len(body["created"]) == 1
    assert body["created"][0]["lecturer_note"] == "not found - assign manually"
    listed = client.get(f"/courses/?department_id={ctx['dept']['id']}",
                        headers=ctx["headers"]).json()
    course = next(c for c in listed if c["code"] == "CEF440")
    assert course["lecturer_id"] is None


def test_faculty_head_import_lecturer_ambiguous(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    _create_lecturer(client, auth_headers, ctx["uni"], ctx["dept"], ctx["fac"],
                      "ateba1@test.com", "Ateba")
    _create_lecturer(client, auth_headers, ctx["uni"], ctx["dept"], ctx["fac"],
                      "ateba2@test.com", "Dr Ateba")
    csv_text = (
        "code,name,level,department,lecturer\n"
        "CEF440,Internet Programming,400,Computer Engineering,Ateba\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    assert r.status_code == 200
    body = r.json()
    assert len(body["created"]) == 1
    assert body["created"][0]["lecturer_note"] == "ambiguous - assign manually"
    listed = client.get(f"/courses/?department_id={ctx['dept']['id']}",
                        headers=ctx["headers"]).json()
    course = next(c for c in listed if c["code"] == "CEF440")
    assert course["lecturer_id"] is None


def _upload_xlsx(client, headers, content: bytes, filename="courses.xlsx", dry_run=False):
    return client.post(
        "/courses/bulk-import/",
        params={"dry_run": dry_run},
        files={"file": (filename, io.BytesIO(content), "application/octet-stream")},
        headers=headers,
    )


def test_faculty_head_imports_xlsx(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    content = _xlsx_bytes([
        ["code", "name", "level", "department"],
        ["CEF440", "Internet Programming", 400, "Computer Engineering"],
        ["CEF445", "Distributed Systems", 400, "Computer Engineering"],
    ])
    r = _upload_xlsx(client, ctx["headers"], content)
    assert r.status_code == 200
    body = r.json()
    assert len(body["created"]) == 2
    listed = client.get(f"/courses/?department_id={ctx['dept']['id']}",
                        headers=ctx["headers"]).json()
    assert {c["code"] for c in listed} == {"CEF440", "CEF445"}


def test_university_admin_dry_run_persists_nothing(client, auth_headers):
    uni, admin_headers = _login_admin(client, auth_headers)
    csv_text = "code,name\nUB101,Use of English\nUB102,Civics\n"
    r = _upload(client, admin_headers, csv_text, dry_run=True)
    assert r.status_code == 200
    body = r.json()
    assert body["dry_run"] is True
    assert len(body["created"]) == 2
    listed = client.get(f"/courses/?university_id={uni['id']}", headers=admin_headers).json()
    assert listed == []


def test_shared_course_links_other_department(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)  # owner: Computer Engineering, level 400
    ee = _add_dept_with_class(client, auth_headers, ctx["fac"],
                              "Electrical Engineering", "EEF", 400, "EEF400")
    csv_text = (
        "code,name,level,department,semester\n"
        "CEF201,Circuits,400,Computer Engineering | Electrical Engineering,1\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    assert r.status_code == 200
    body = r.json()
    assert len(body["created"]) == 1
    entry = body["created"][0]
    assert entry["department"] == "Computer Engineering"
    assert entry["shared_with"] == ["Electrical Engineering"]
    assert entry["shared_note"] is None
    # The course was created once, in the owner department...
    listed = client.get(f"/courses/?department_id={ctx['dept']['id']}",
                        headers=ctx["headers"]).json()
    course = next(c for c in listed if c["code"] == "CEF201")
    # ...and linked to the Electrical Engineering level-400 class.
    shared = client.get(f"/courses/{course['id']}/shared",
                        headers=ctx["headers"]).json()
    assert [s["class_id"] for s in shared] == [ee["class"]["id"]]


def test_shared_course_note_when_shared_dept_has_no_class(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    _add_dept_with_class(client, auth_headers, ctx["fac"],
                         "Electrical Engineering", "EEF", 400, with_class=False)
    csv_text = (
        "code,name,level,department\n"
        "CEF201,Circuits,400,Computer Engineering | Electrical Engineering\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    body = r.json()
    assert len(body["created"]) == 1
    entry = body["created"][0]
    assert entry["shared_with"] == []
    assert "has no classes" in entry["shared_note"]
    # Owner course still created.
    listed = client.get(f"/courses/?department_id={ctx['dept']['id']}",
                        headers=ctx["headers"]).json()
    assert any(c["code"] == "CEF201" for c in listed)


def test_shared_course_unknown_shared_dept_is_noted(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = (
        "code,name,level,department\n"
        "CEF201,Circuits,400,Computer Engineering | Ghost Department\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    entry = r.json()["created"][0]
    assert entry["shared_with"] == []
    assert "not found" in entry["shared_note"]


def test_single_department_row_has_empty_shared(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = "code,name,level,department\nCEF440,Internet Programming,400,Computer Engineering\n"
    entry = _upload(client, ctx["headers"], csv_text).json()["created"][0]
    assert entry["shared_with"] == []
    assert entry["shared_note"] is None


def test_shared_course_dry_run_persists_no_links(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    ee = _add_dept_with_class(client, auth_headers, ctx["fac"],
                              "Electrical Engineering", "EEF", 400, "EEF400")
    csv_text = (
        "code,name,level,department\n"
        "CEF201,Circuits,400,Computer Engineering | Electrical Engineering\n"
    )
    r = _upload(client, ctx["headers"], csv_text, dry_run=True)
    body = r.json()
    assert body["dry_run"] is True
    assert body["created"][0]["shared_with"] == ["Electrical Engineering"]
    # Nothing persisted: no course, hence no shared links.
    listed = client.get(f"/courses/?department_id={ctx['dept']['id']}",
                        headers=ctx["headers"]).json()
    assert listed == []


def test_shared_course_xlsx(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    ee = _add_dept_with_class(client, auth_headers, ctx["fac"],
                              "Electrical Engineering", "EEF", 400, "EEF400")
    content = _xlsx_bytes([
        ["code", "name", "level", "department"],
        ["CEF201", "Circuits", 400, "Computer Engineering | Electrical Engineering"],
    ])
    r = _upload_xlsx(client, ctx["headers"], content)
    assert r.status_code == 200
    entry = r.json()["created"][0]
    assert entry["shared_with"] == ["Electrical Engineering"]


def test_shared_course_empty_department_cell_is_skipped(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    csv_text = (
        "code,name,level,department\n"
        "CEF900,Bad Row,400,|\n"                       # degenerate department cell
        "CEF901,Good Row,400,Computer Engineering\n"   # valid, must still import
    )
    r = _upload(client, ctx["headers"], csv_text)
    assert r.status_code == 200
    body = r.json()
    assert [c["code"] for c in body["created"]] == ["CEF901"]
    assert body["skipped"][0]["code"] == "CEF900"
