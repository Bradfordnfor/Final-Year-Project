"""CSV/PDF export can be narrowed to a single class via ?class_id=."""
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


def _data_rows(text):
    return [r for r in text.strip().splitlines() if r]


def test_csv_export_full_then_filtered(client, auth_headers, db, admin_user):
    run = _run_with_two_classes(db, admin_user.id)

    full = client.get(f"/export/runs/{run.id}/csv", headers=auth_headers)
    assert full.status_code == 200
    assert len(_data_rows(full.text)) == 3  # header + 2 sessions

    filtered = client.get(
        f"/export/runs/{run.id}/csv?class_id=101", headers=auth_headers)
    assert filtered.status_code == 200
    assert len(_data_rows(filtered.text)) == 2  # header + 1 session


def test_csv_export_multi_class_scope(client, auth_headers, db, admin_user):
    # class_ids covers a department/faculty scope (more than one class).
    run = _run_with_two_classes(db, admin_user.id)  # classes 101 and 202

    both = client.get(
        f"/export/runs/{run.id}/csv?class_ids=101,202", headers=auth_headers)
    assert both.status_code == 200
    assert len(_data_rows(both.text)) == 3  # header + both sessions

    one = client.get(
        f"/export/runs/{run.id}/csv?class_ids=101", headers=auth_headers)
    assert one.status_code == 200
    assert len(_data_rows(one.text)) == 2  # header + 1 session


def test_csv_export_filter_no_match_is_404(client, auth_headers, db, admin_user):
    run = _run_with_two_classes(db, admin_user.id)
    resp = client.get(
        f"/export/runs/{run.id}/csv?class_id=999", headers=auth_headers)
    assert resp.status_code == 404
