class UserModel {
  final int id;
  final String email;
  final String fullName;
  final String role;
  final bool isActive;
  final int? universityId;
  final int? departmentId;
  final int? facultyId;

  const UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
    this.universityId,
    this.departmentId,
    this.facultyId,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as int,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        role: json['role'] as String,
        isActive: json['is_active'] as bool,
        universityId: json['university_id'] as int?,
        departmentId: json['department_id'] as int?,
        facultyId: json['faculty_id'] as int?,
      );

  // Exact role checks — flat, no cascading
  bool get isSuperAdmin => role == 'super_admin';
  bool get isUniversityAdmin => role == 'university_admin';
  bool get isFacultyHead => role == 'faculty_head';
  bool get isTimetableOfficer => role == 'timetable_officer';
  bool get isLecturer => role == 'lecturer';
  bool get isStudent => role == 'student';

  // System-level admin (no university_id — manages the platform itself)
  bool get isSystemAdmin => isSuperAdmin;

  // Permission groups — superadmin is system-level only, excluded here
  // University management: buildings, users, semesters, time slots
  bool get canManageUniversity => isUniversityAdmin;
  // Faculty academic data: departments, levels, courses
  bool get canSetupFaculty => isUniversityAdmin || isFacultyHead;
  // Timetable workflow: create runs, generate, resolve conflicts, publish
  bool get canManageTimetable => isTimetableOfficer;
  // Can view internal timetable grid (not public)
  bool get canViewTimetable => !isStudent && !isSuperAdmin;
  // Any internal user (not student)
  bool get isStaff => !isStudent;
}

class TokenResponse {
  final String accessToken;
  final UserModel user;

  const TokenResponse({required this.accessToken, required this.user});

  factory TokenResponse.fromJson(Map<String, dynamic> json) => TokenResponse(
        accessToken: json['access_token'] as String,
        user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      );
}
