class AppConstants {
  static const String baseUrl = 'http://localhost:8000';

  static const List<String> daysOfWeek = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
  ];

  static const Map<String, String> roleLabels = {
    'super_admin': 'Super Admin',
    'university_admin': 'University Admin',
    'faculty_head': 'Faculty Head',
    'timetable_officer': 'Timetable Officer',
    'lecturer': 'Lecturer',
    'student': 'Student',
  };
}
