"""Track-aware admin behaviours added after the whole-feature review:
- public-levels exposes every class at a level (so filtered/exported timetables
  don't silently drop a track),
- deleting a class is blocked (clear 400) when courses/groups/shared links still
  point at it, instead of a raw 500.
"""
from tests.test_course_bulk_import import setup_faculty_head


def _level_id(client, ctx):
    return next(
        l["id"] for l in client.get("/levels/", headers=ctx["headers"]).json()
        if l["department_id"] == ctx["dept"]["id"] and l["number"] == 400
    )


def _two_track_classes(client, ctx, lid):
    sw = client.post("/classes/", json={
        "name": "CE400 Software", "population": 120, "level_id": lid, "track": "Software",
    }, headers=ctx["headers"]).json()
    net = client.post("/classes/", json={
        "name": "CE400 Networking", "population": 80, "level_id": lid, "track": "Networking",
    }, headers=ctx["headers"]).json()
    return sw, net


def test_public_levels_exposes_all_classes(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    lid = _level_id(client, ctx)
    sw, net = _two_track_classes(client, ctx, lid)

    levels = client.get(
        f"/faculty-setup/public-levels?department_id={ctx['dept']['id']}"
    ).json()
    node = next(l for l in levels if l["number"] == 400)
    assert set(node["class_ids"]) == {sw["id"], net["id"]}


def test_delete_class_blocked_when_course_targets_it(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    lid = _level_id(client, ctx)
    sw, _net = _two_track_classes(client, ctx, lid)

    # A course targeting the Software track (created as super_admin, since the
    # /courses/ endpoint is scoped to admin/timetable-officer roles).
    r = client.post("/courses/", json={
        "code": "CE401SW", "name": "Software Design",
        "level_id": lid, "department_id": ctx["dept"]["id"],
        "class_id": sw["id"], "weekly_hours": 2, "semester": 1,
    }, headers=auth_headers)
    assert r.status_code == 201 and r.json()["class_id"] == sw["id"]

    r = client.delete(f"/classes/{sw['id']}", headers=ctx["headers"])
    assert r.status_code == 400
    assert "course" in r.json()["detail"].lower()


def test_delete_class_allowed_when_unreferenced(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    lid = _level_id(client, ctx)
    _sw, net = _two_track_classes(client, ctx, lid)

    r = client.delete(f"/classes/{net['id']}", headers=ctx["headers"])
    assert r.status_code == 204


def test_public_levels_includes_classes_with_tracks(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)
    lid = _level_id(client, ctx)
    sw, net = _two_track_classes(client, ctx, lid)

    levels = client.get(
        f"/faculty-setup/public-levels?department_id={ctx['dept']['id']}"
    ).json()
    node = next(l for l in levels if l["number"] == 400)
    by_track = {c["track"]: c for c in node["classes"]}
    assert by_track["Software"]["id"] == sw["id"]
    assert by_track["Networking"]["id"] == net["id"]
