class AppConstants {
  // Backend API URL. Defaults to local dev; override at build time with
  // --dart-define=API_BASE_URL=https://your-backend.example.com
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

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
