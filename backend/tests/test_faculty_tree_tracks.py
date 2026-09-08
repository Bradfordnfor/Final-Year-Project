"""The faculty-setup tree must expose every class at a level (not just the
first), each with its specialization track, so the UI can show and manage
track-classes."""
from tests.test_course_bulk_import import setup_faculty_head


def test_tree_returns_all_classes_with_track(client, auth_headers):
    ctx = setup_faculty_head(client, auth_headers)  # uni + FET + Computer Engineering + level 400

    lid = next(
        l["id"] for l in client.get("/levels/", headers=ctx["headers"]).json()
        if l["department_id"] == ctx["dept"]["id"] and l["number"] == 400
    )
    client.post("/classes/", json={
        "name": "CE400 Software", "population": 120, "level_id": lid, "track": "Software",
    }, headers=ctx["headers"])
    client.post("/classes/", json={
        "name": "CE400 Networking", "population": 80, "level_id": lid, "track": "Networking",
    }, headers=ctx["headers"])

    tree = client.get("/faculty-setup/tree", headers=ctx["headers"]).json()
    dept_node = next(d for d in tree["departments"] if d["id"] == ctx["dept"]["id"])
    level_node = next(l for l in dept_node["levels"] if l["number"] == 400)

    classes = level_node["classes"]
    by_track = {c["track"]: c for c in classes}
    assert "Software" in by_track and by_track["Software"]["population"] == 120
    assert "Networking" in by_track and by_track["Networking"]["population"] == 80
