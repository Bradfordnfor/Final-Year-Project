import io
from app.routers.export import _load_faded_logo, _pdf_title, _StampCanvas
from app.models.timetable import (
    TimetableRun, TimetableEntry, TimetableEntryClass,
)


def _run_with_two_classes(db, creator_id):
    run = TimetableRun(name="R", semester_id=1, created_by=creator_id,
                       status="draft")
    db.add(run); db.flush()
    e1 = TimetableEntry(run_id=run.id, course_id=1, lecturer_id=1, room_id=1,
                        time_slot_id=1, week_pattern="every_week")
    e2 = TimetableEntry(run_id=run.id, course_id=1, lecturer_id=1, room_id=1,
                        time_slot_id=1, week_pattern="every_week")
    db.add_all([e1, e2]); db.flush()
    db.add(TimetableEntryClass(entry_id=e1.id, class_id=101))
    db.add(TimetableEntryClass(entry_id=e2.id, class_id=202))
    db.commit()
    return run


def test_grid_pdf_endpoint_returns_pdf(client, auth_headers, db, admin_user):
    run = _run_with_two_classes(db, admin_user.id)
    r = client.get(f"/export/runs/{run.id}/pdf", headers=auth_headers)
    assert r.status_code == 200
    assert r.headers["content-type"] == "application/pdf"
    assert r.content[:4] == b"%PDF"


def test_grid_pdf_filtered_returns_pdf(client, auth_headers, db, admin_user):
    run = _run_with_two_classes(db, admin_user.id)
    r = client.get(f"/export/runs/{run.id}/pdf?class_ids=101", headers=auth_headers)
    assert r.status_code == 200
    assert r.content[:4] == b"%PDF"


def test_public_grid_pdf_requires_published(client, db, admin_user):
    run = _run_with_two_classes(db, admin_user.id)  # draft
    assert client.get(f"/export/public/runs/{run.id}/pdf").status_code == 404
    run.status = "published"; db.commit()
    r = client.get(f"/export/public/runs/{run.id}/pdf")
    assert r.status_code == 200 and r.content[:4] == b"%PDF"


def test_missing_logo_asset_is_not_fatal():
    assert _load_faded_logo("/no/such/logo.png") is None


def test_pdf_title_escapes_ampersand_and_angle_brackets():
    t = _pdf_title("Electrical & Electronic Engineering <X>", filtered=False)
    assert "&amp;" in t and "&lt;X&gt;" in t
    assert "& " not in t  # raw ampersand must not survive


def test_pdf_title_filtered_suffix():
    assert _pdf_title("R", filtered=True).endswith("(filtered)")
    assert not _pdf_title("R", filtered=False).endswith("(filtered)")


def test_stamp_canvas_identity_is_per_instance_not_shared():
    # Two canvases with different identities must not clobber each other
    # (the endpoints are sync def -> threadpool-concurrent).
    c1 = _StampCanvas(io.BytesIO(), identity="University A")
    c2 = _StampCanvas(io.BytesIO(), identity="University B")
    assert c1.identity == "University A"
    assert c2.identity == "University B"


def test_csv_columns_unchanged(client, auth_headers, db, admin_user):
    run = _run_with_two_classes(db, admin_user.id)
    r = client.get(f"/export/runs/{run.id}/csv", headers=auth_headers)
    assert r.status_code == 200
    header = r.text.strip().splitlines()[0]
    assert header == ("Day,Time,Course,Classes,Lecturer,Room,Capacity,"
                      "Overcapacity,Week Pattern")
