from app.routers.export import build_grid, WEEKDAY_ORDER


def _row(day, time, course, lecturer, room):
    return {"Day": day, "Time": time, "Course": course,
            "Lecturer": lecturer, "Room": room}


def test_concurrent_sessions_share_a_cell():
    rows = [
        _row("Monday", "07:00-09:00", "CEF401 — Internet Programming", "Dr A", "Hall 1"),
        _row("Monday", "07:00-09:00", "EEF305 — Signals", "Dr B", "Hall 3"),
    ]
    grid = build_grid(rows)
    cell = grid["cells"][("Monday", "07:00-09:00")]
    codes = [c["code"] for c in cell]
    assert codes == ["CEF401", "EEF305"]  # sorted by code
    assert cell[0]["lecturer"] == "Dr A" and cell[0]["hall"] == "Hall 1"


def test_days_use_canonical_order_not_alphabetical():
    rows = [
        _row("Friday", "07:00-09:00", "X1 — A", "L", "H"),
        _row("Monday", "07:00-09:00", "X2 — B", "L", "H"),
    ]
    grid = build_grid(rows)
    assert grid["days"] == ["Monday", "Friday"]


def test_slots_ordered_by_start_time():
    rows = [
        _row("Monday", "13:00-15:00", "X1 — A", "L", "H"),
        _row("Monday", "07:00-09:00", "X2 — B", "L", "H"),
    ]
    grid = build_grid(rows)
    assert grid["slots"] == ["07:00-09:00", "13:00-15:00"]


def test_legend_lists_each_code_once_sorted():
    rows = [
        _row("Monday", "07:00-09:00", "EEF305 — Signals", "L", "H"),
        _row("Tuesday", "07:00-09:00", "EEF305 — Signals", "L", "H"),
        _row("Monday", "09:00-11:00", "CEF401 — Internet Programming", "L", "H"),
    ]
    grid = build_grid(rows)
    assert grid["legend"] == [
        ("CEF401", "Internet Programming"),
        ("EEF305", "Signals"),
    ]


def test_outdoor_session_hall_text():
    rows = [_row("Monday", "07:00-09:00", "AGF200 — Field Work", "Dr C",
                 "Outdoor / off-site")]
    grid = build_grid(rows)
    assert grid["cells"][("Monday", "07:00-09:00")][0]["hall"] == "Outdoor / off-site"


def test_weekday_order_constant():
    assert WEEKDAY_ORDER[:2] == ["Monday", "Tuesday"]
