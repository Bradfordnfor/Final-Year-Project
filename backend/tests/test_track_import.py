from tests.test_course_bulk_import import setup_faculty_head, _upload


def _level_id(client, ctx):
    # setup_faculty_head already created level 400; fetch its id.
    # NOTE: there is no /departments/{dept_id}/levels endpoint in this app;
    # /levels/ returns all levels, so filter client-side by department + number.
    levels = client.get("/levels/", headers=ctx["headers"]).json()
    return next(l["id"] for l in levels
                if l["department_id"] == ctx["dept"]["id"] and l["number"] == 400)


def _make_track_classes(client, ctx):
    """Create two track-classes under the existing Computer Engineering level 400."""
    lid = _level_id(client, ctx)
    sw = client.post("/classes/", json={
        "name": "CE400 Software", "population": 120,
        "level_id": lid, "track": "Software",
    }, headers=ctx["headers"]).json()
    net = client.post("/classes/", json={
        "name": "CE400 Networking", "population": 80,
        "level_id": lid, "track": "Networking",
    }, headers=ctx["headers"]).json()
    return sw, net


def test_import_track_column_targets_class(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)  # creates dept + level 400
    sw, net = _make_track_classes(client, ctx)
    csv_text = (
        "code,name,level,department,semester,track\n"
        "CE401SW,Software Design,400,Computer Engineering,1,Software\n"
        "CE402NET,Routing,400,Computer Engineering,1,Networking\n"
        "CE400C,Ethics,400,Computer Engineering,1,\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    assert r.status_code == 200
    # Verify class_id via the courses list.
    courses = client.get("/courses/", headers=ctx["headers"]).json()
    by_code = {c["code"]: c for c in courses}
    assert by_code["CE401SW"]["class_id"] == sw["id"]
    assert by_code["CE402NET"]["class_id"] == net["id"]
    assert by_code["CE400C"]["class_id"] is None   # blank track = whole level


def test_import_unknown_track_is_skipped(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    _make_track_classes(client, ctx)
    csv_text = (
        "code,name,level,department,semester,track\n"
        "CE499X,Mystery,400,Computer Engineering,1,Robotics\n"
    )
    r = _upload(client, ctx["headers"], csv_text)
    assert r.status_code == 200
    body = r.json()
    assert body["created"] == []
    assert any("Robotics" in s["reason"] or "track" in s["reason"].lower()
               for s in body["skipped"])
