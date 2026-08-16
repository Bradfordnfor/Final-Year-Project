"""Generate the rooms and courses Excel templates for the client intake.

Run from the backend dir so the venv's openpyxl resolves:
    cd backend && python ../docs/client_intake/generate_templates.py
The .xlsx files are written next to this script.
"""
import os
from openpyxl import Workbook

HERE = os.path.dirname(os.path.abspath(__file__))

ROOMS_HEADER = ["building", "room_name", "capacity", "room_type", "active"]
ROOMS_EXAMPLES = [
    ["Main Block", "LT1", 250, "lecture_hall", "yes"],
    ["Main Block", "Electronics Lab", 60, "lab", "yes"],
    ["Sports Complex", "Engineering Field", 400, "outdoor", "yes"],
]
ROOMS_NOTES = [
    ["Column", "Meaning / allowed values"],
    ["building", "Building name; repeat it on every room in that building."],
    ["room_name", "Unique room name or number, e.g. LT1, Room 204."],
    ["capacity", "Whole number of seats. Required — used against class size."],
    ["room_type", "One of: lecture_hall, lab, outdoor."],
    ["active", "yes or no. Use no for a room that must not be scheduled."],
]

COURSES_HEADER = ["code", "name", "level", "department", "semester",
                  "weekly_hours", "room_type", "lecturer"]
COURSES_EXAMPLES = [
    ["CEF440", "Internet Programming", 400, "Computer Engineering", 1, 3,
     "lecture_hall", "Dr. Ateba"],
    ["CEF201", "Circuits", 400,
     "Computer Engineering | Electrical & Electronic Engineering",
     1, 3, "lecture_hall", ""],
]
COURSES_NOTES = [
    ["Column", "Meaning / allowed values"],
    ["code", "Course code, e.g. CEF440. Required."],
    ["name", "Course title. Required."],
    ["level", "Year of study number: 100, 200, 300, 400, 500."],
    ["department", "Department name in this faculty. To share ONE course across "
                   "departments, list them separated by | (first owns it), e.g. "
                   "Computer Engineering | Electrical & Electronic Engineering."],
    ["semester", "1 (first) or 2 (second)."],
    ["weekly_hours", "Contact hours per week. Leave blank for the default (2)."],
    ["room_type", "One of: lecture_hall, lab, studio. Match a room type you have."],
    ["lecturer", "Lecturer full name (optional; auto-matched on import)."],
]


def _sheet(wb, title, header, examples):
    ws = wb.active if wb.active.max_row == 1 and wb.active.max_column == 1 else wb.create_sheet()
    ws.title = title
    ws.append(header)
    for row in examples:
        ws.append(row)
    return ws


def _instructions(wb, notes):
    ws = wb.create_sheet("Instructions")
    for row in notes:
        ws.append(row)
    return ws


def build_rooms(path):
    wb = Workbook()
    _sheet(wb, "Rooms", ROOMS_HEADER, ROOMS_EXAMPLES)
    _instructions(wb, ROOMS_NOTES)
    wb.save(path)


def build_courses(path):
    wb = Workbook()
    _sheet(wb, "Courses", COURSES_HEADER, COURSES_EXAMPLES)
    _instructions(wb, COURSES_NOTES)
    wb.save(path)


if __name__ == "__main__":
    build_rooms(os.path.join(HERE, "rooms_template.xlsx"))
    build_courses(os.path.join(HERE, "courses_template.xlsx"))
    print("Wrote rooms_template.xlsx and courses_template.xlsx to", HERE)
