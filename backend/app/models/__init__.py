from app.models.university import University, Faculty, Department
from app.models.building import Building
from app.models.room import Room
from app.models.academic import Semester, TimeSlot, Level, Class, ClassGroup
from app.models.user import User, Lecturer, LecturerAvailability, Student
from app.models.course import Course, SharedCourse
from app.models.timetable import (
    TimetableRun, TimetableRunFaculty, TimetableRunBuilding,
    TimetableEntry, TimetableEntryClass,
    TimetableConflict, GenerationJob, Notification,
)
