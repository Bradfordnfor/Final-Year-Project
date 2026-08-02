import io
from openpyxl import Workbook
from app.services.course_import import read_rows, parse_int


def _xlsx_bytes(rows):
    """rows: list of lists; first list is the header. Returns .xlsx bytes."""
    wb = Workbook()
    ws = wb.active
    for r in rows:
        ws.append(r)
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def test_read_rows_csv_lowercases_header_and_strips():
    content = b"Code,Name,Level\nCEF440, Internet Programming ,400\n"
    header, rows = read_rows("courses.csv", content)
    assert header == ["code", "name", "level"]
    assert rows == [{"code": "CEF440", "name": "Internet Programming", "level": "400"}]


def test_read_rows_csv_utf8_bom():
    content = "﻿code,name\nCEF440,Internet\n".encode("utf-8")
    header, rows = read_rows("c.csv", content)
    assert header == ["code", "name"]
    assert rows[0]["code"] == "CEF440"


def test_read_rows_xlsx():
    content = _xlsx_bytes([["code", "name", "level"], ["CEF440", "Internet Programming", 400]])
    header, rows = read_rows("courses.xlsx", content)
    assert header == ["code", "name", "level"]
    # numbers from Excel are stringified
    assert rows[0] == {"code": "CEF440", "name": "Internet Programming", "level": "400"}


def test_read_rows_csv_skips_blank_rows():
    content = b"code,name\nCEF440,Internet\n,,\nCEF441,Networks\n"
    header, rows = read_rows("c.csv", content)
    assert header == ["code", "name"]
    assert len(rows) == 2
    assert rows[0]["code"] == "CEF440"
    assert rows[1]["code"] == "CEF441"


def test_read_rows_csv_undecodable_raises():
    import pytest
    with pytest.raises(ValueError):
        read_rows("x.csv", b"\xff\xfe\x00bad")


def test_read_rows_xlsx_skips_blank_rows():
    content = _xlsx_bytes([["code", "name"], [None, None], ["CEF440", "Internet"]])
    _, rows = read_rows("c.xlsx", content)
    assert len(rows) == 1
    assert rows[0]["code"] == "CEF440"


def test_read_rows_header_only_returns_no_rows():
    header, rows = read_rows("c.csv", b"code,name\n")
    assert header == ["code", "name"]
    assert rows == []


def test_read_rows_unreadable_raises():
    import pytest
    with pytest.raises(ValueError):
        read_rows("c.xlsx", b"this is not a real xlsx file")


def test_parse_int():
    assert parse_int("3", 2) == 3
    assert parse_int("3.0", 2) == 3
    assert parse_int("", 2) == 2
    assert parse_int(None, 2) == 2
    assert parse_int("abc", 2) == 2
    assert parse_int(4, 2) == 4
