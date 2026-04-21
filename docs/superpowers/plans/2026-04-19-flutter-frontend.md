# Flutter Frontend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete Flutter frontend — a web-first, mobile-friendly app with role-based navigation, timetable grid views, generation UI, conflict resolution, analytics, notifications, and export.

**Architecture:** Single Flutter app using GetX for state management, dependency injection, and navigation. Each feature lives in its own folder under `lib/features/`. The API layer is fully separated from UI — GetX controllers call API classes, screens only read observable state with `Obx`. Controllers are registered once in `app.dart` via `Get.put`.

**Tech Stack:** Flutter 3.22+, get 4.6.6, dio 5.4, flutter_secure_storage 9.2, fl_chart 0.68, path_provider 2.1, open_filex 4.5, google_fonts 6.2, flutter_animate 4.5, mocktail 1.0 (tests)

**UI Design Decisions:**
- **Color:** Royal Blue `#1565C0` primary, Amber `#F57F17` for warnings/status
- **Layout:** Adaptive Rail — full sidebar (>1200px), NavigationRail icon-only (800–1200px), BottomNavigationBar (<800px)
- **Font:** Inter (via google_fonts)
- **Animation:** Smooth & flowing — 300ms `easeInOut`, staggered list fade-ins, shimmer loading, subtle card scale on tap. No looping animations.
- **Theme:** Light mode default, dark mode follows system setting

> **Note:** This is Plan 3 of 3. Requires Plan 1 (Backend Foundation) and Plan 2 (Timetable Generation Engine) running and accessible before implementing screens.

> **Git workflow:** All frontend work lives on the `frontend` branch. Create it once before Task 1:
> ```bash
> git checkout -b frontend
> ```
> Commit steps in this plan are **proposals only** — I will tell you when I think it's a good time to commit and suggest the message. You run `git add` and `git commit` yourself. You also decide when to push.

---

## Screen Design Process

Every screen follows this two-step pattern:

1. **Design first** — invoke the `frontend-design` skill with a detailed prompt. The skill returns production-quality Flutter widget code.
2. **Wire up** — replace placeholder data with GetX controllers and real API calls.

---

## File Structure

```
frontend/
├── lib/
│   ├── main.dart                         # Entry point
│   ├── app.dart                          # GetMaterialApp, registers controllers, defines routes
│   ├── core/
│   │   ├── constants.dart                # API base URL, shared constants
│   │   ├── theme.dart                    # Light + dark theme
│   │   ├── routes.dart                   # AppRoutes constants, GetPages list, AuthMiddleware
│   │   ├── api/
│   │   │   ├── api_client.dart           # Dio instance with auth interceptor
│   │   │   ├── auth_api.dart             # login, /me
│   │   │   ├── university_api.dart       # universities, faculties, departments, rooms
│   │   │   ├── academic_api.dart         # semesters, timeslots, levels, classes, groups
│   │   │   ├── course_api.dart           # courses
│   │   │   ├── user_api.dart             # lecturers, students, availability
│   │   │   └── timetable_api.dart        # timetables, generation, conflicts, export
│   │   ├── models/
│   │   │   ├── user.dart                 # UserModel, TokenResponse
│   │   │   ├── university.dart           # University, Faculty, Department
│   │   │   ├── academic.dart             # Semester, TimeSlot, StudyClass
│   │   │   ├── course.dart               # Course
│   │   │   ├── room.dart                 # Room
│   │   │   └── timetable.dart            # TimetableModel, TimetableEntry, TimetableConflict, AppNotification
│   │   └── controllers/
│   │       ├── auth_controller.dart      # login, logout, current user, token storage
│   │       ├── timetable_controller.dart # timetables, entries, conflicts, job status
│   │       └── notification_controller.dart
│   └── features/
│       ├── auth/login_screen.dart
│       ├── dashboard/dashboard_screen.dart
│       ├── timetable/
│       │   ├── timetable_screen.dart
│       │   └── timetable_grid.dart
│       ├── generation/generation_screen.dart
│       ├── conflicts/conflicts_screen.dart
│       ├── management/
│       │   ├── rooms_screen.dart
│       │   ├── courses_screen.dart
│       │   ├── users_screen.dart
│       │   └── availability_screen.dart
│       ├── analytics/analytics_screen.dart
│       └── notifications/notifications_screen.dart
├── test/
│   ├── models_test.dart
│   ├── auth_controller_test.dart
│   └── widget/
│       ├── login_test.dart
│       └── timetable_grid_test.dart
└── pubspec.yaml
```

---

## Task 1: Flutter Project Setup

**Files:**
- Create: `frontend/pubspec.yaml`
- Create: `frontend/lib/main.dart`
- Create: `frontend/lib/core/constants.dart`

- [ ] **Step 1: Create the Flutter project**

```bash
flutter create frontend --platforms=web,android,ios
cd frontend
```

Expected: Flutter project scaffolded with `lib/main.dart`, `pubspec.yaml`.

- [ ] **Step 2: Replace `pubspec.yaml`**

```yaml
name: university_timetabling
description: University Timetabling System
publish_to: none
version: 1.0.0+1

environment:
  sdk: ">=3.3.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  get: ^4.6.6
  dio: ^5.4.3+1
  flutter_secure_storage: ^9.2.2
  intl: ^0.19.0
  fl_chart: ^0.68.0
  path_provider: ^2.1.3
  open_filex: ^4.5.0
  google_fonts: ^6.2.1
  flutter_animate: ^4.5.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  mocktail: ^1.0.3

flutter:
  uses-material-design: true
```

- [ ] **Step 3: Install dependencies**

```bash
flutter pub get
```

Expected: completes without errors.

- [ ] **Step 4: Create `lib/core/constants.dart`**

```dart
class AppConstants {
  static const String baseUrl = 'http://localhost:8000';

  static const List<String> daysOfWeek = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
  ];

  static const Map<String, String> roleLabels = {
    'super_admin': 'Super Admin',
    'university_admin': 'University Admin',
    'department_head': 'Department Head',
    'timetable_officer': 'Timetable Officer',
    'lecturer': 'Lecturer',
    'student': 'Student',
  };
}
```

- [ ] **Step 5: Replace `lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'app.dart';

void main() {
  runApp(const App());
}
```

- [ ] **Step 6: Run the app to confirm it starts**

```bash
flutter run -d chrome
```

Expected: Flutter app launches in Chrome without errors.

- [ ] **Step 7: Commit checkpoint**

> **Suggested commit message:** "feat: initialize Flutter project with GetX dependencies"

```bash
git add frontend/
```

---

## Task 2: Dart API Models

**Files:**
- Create: `frontend/lib/core/models/user.dart`
- Create: `frontend/lib/core/models/university.dart`
- Create: `frontend/lib/core/models/academic.dart`
- Create: `frontend/lib/core/models/course.dart`
- Create: `frontend/lib/core/models/room.dart`
- Create: `frontend/lib/core/models/timetable.dart`
- Create: `frontend/test/models_test.dart`

- [ ] **Step 1: Write `test/models_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetabling/core/models/user.dart';
import 'package:university_timetabling/core/models/timetable.dart';

void main() {
  group('User model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1, 'email': 'admin@ub.cm', 'full_name': 'Admin',
        'role': 'super_admin', 'is_active': true,
        'university_id': null, 'department_id': null,
      };
      final user = UserModel.fromJson(json);
      expect(user.id, 1);
      expect(user.role, 'super_admin');
      expect(user.isSuperAdmin, isTrue);
      expect(user.canManageTimetable, isTrue);
    });

    test('student role helpers return correct values', () {
      final user = UserModel(
        id: 2, email: 'stu@ub.cm', fullName: 'Student',
        role: 'student', isActive: true,
      );
      expect(user.isSuperAdmin, isFalse);
      expect(user.canManageTimetable, isFalse);
      expect(user.isStudent, isTrue);
    });
  });

  group('TimetableEntry model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 10, 'timetable_id': 1, 'course_id': 2, 'lecturer_id': 3,
        'room_id': 4, 'time_slot_id': 5, 'group_id': null,
        'week_pattern': 'every_week', 'rotation_sequence': null,
        'is_overcapacity': false, 'is_merged': false,
        'class_ids': [1, 2],
      };
      final entry = TimetableEntry.fromJson(json);
      expect(entry.classIds, [1, 2]);
      expect(entry.isOvercapacity, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run to confirm failures**

```bash
flutter test test/models_test.dart
```

Expected: errors — model classes don't exist yet.

- [ ] **Step 3: Create `lib/core/models/user.dart`**

```dart
class UserModel {
  final int id;
  final String email;
  final String fullName;
  final String role;
  final bool isActive;
  final int? universityId;
  final int? departmentId;

  const UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
    this.universityId,
    this.departmentId,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as int,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        role: json['role'] as String,
        isActive: json['is_active'] as bool,
        universityId: json['university_id'] as int?,
        departmentId: json['department_id'] as int?,
      );

  bool get isSuperAdmin => role == 'super_admin';
  bool get isUniversityAdmin => role == 'university_admin' || isSuperAdmin;
  bool get isDepartmentHead => role == 'department_head' || isUniversityAdmin;
  bool get isTimetableOfficer => role == 'timetable_officer' || isDepartmentHead;
  bool get isLecturer => role == 'lecturer';
  bool get isStudent => role == 'student';
  bool get canManageTimetable => isTimetableOfficer;
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
```

- [ ] **Step 4: Create `lib/core/models/university.dart`**

```dart
class University {
  final int id;
  final String name;
  final String slug;
  final double overflowThreshold;

  const University({
    required this.id, required this.name,
    required this.slug, required this.overflowThreshold,
  });

  factory University.fromJson(Map<String, dynamic> json) => University(
        id: json['id'] as int,
        name: json['name'] as String,
        slug: json['slug'] as String,
        overflowThreshold: (json['overflow_threshold'] as num).toDouble(),
      );
}

class Faculty {
  final int id;
  final String name;
  // Short abbreviation, e.g. "FET" for Faculty of Engineering and Technology
  final String code;
  final int sessionsPerWeek;
  final int sessionDurationHours;
  final int universityId;

  const Faculty({
    required this.id, required this.name, required this.code,
    required this.sessionsPerWeek, required this.sessionDurationHours,
    required this.universityId,
  });

  factory Faculty.fromJson(Map<String, dynamic> json) => Faculty(
        id: json['id'] as int,
        name: json['name'] as String,
        code: json['code'] as String,
        sessionsPerWeek: json['sessions_per_week'] as int,
        sessionDurationHours: json['session_duration_hours'] as int,
        universityId: json['university_id'] as int,
      );
}

class Department {
  final int id;
  final String name;
  // Short abbreviation, e.g. "EE" for Electrical Engineering
  final String code;
  final int facultyId;

  const Department({
    required this.id, required this.name,
    required this.code, required this.facultyId,
  });

  factory Department.fromJson(Map<String, dynamic> json) => Department(
        id: json['id'] as int,
        name: json['name'] as String,
        code: json['code'] as String,
        facultyId: json['faculty_id'] as int,
      );
}
```

- [ ] **Step 5: Create `lib/core/models/academic.dart`**

```dart
class Semester {
  final int id;
  final String name;
  final String startDate;
  final String endDate;
  final bool isActive;
  final int universityId;

  const Semester({
    required this.id, required this.name, required this.startDate,
    required this.endDate, required this.isActive, required this.universityId,
  });

  factory Semester.fromJson(Map<String, dynamic> json) => Semester(
        id: json['id'] as int,
        name: json['name'] as String,
        startDate: json['start_date'] as String,
        endDate: json['end_date'] as String,
        isActive: json['is_active'] as bool,
        universityId: json['university_id'] as int,
      );
}

class TimeSlot {
  final int id;
  final String dayOfWeek;
  final String startTime;
  final String endTime;
  final int semesterId;

  const TimeSlot({
    required this.id, required this.dayOfWeek, required this.startTime,
    required this.endTime, required this.semesterId,
  });

  factory TimeSlot.fromJson(Map<String, dynamic> json) => TimeSlot(
        id: json['id'] as int,
        dayOfWeek: json['day_of_week'] as String,
        startTime: json['start_time'] as String,
        endTime: json['end_time'] as String,
        semesterId: json['semester_id'] as int,
      );

  String get label => '$startTime – $endTime';
}

class StudyClass {
  final int id;
  // Name like "EE300" — combines department code + level number
  final String name;
  final int population;
  final int levelId;

  const StudyClass({
    required this.id, required this.name,
    required this.population, required this.levelId,
  });

  factory StudyClass.fromJson(Map<String, dynamic> json) => StudyClass(
        id: json['id'] as int,
        name: json['name'] as String,
        population: json['population'] as int,
        levelId: json['level_id'] as int,
      );
}
```

- [ ] **Step 6: Create `lib/core/models/course.dart`**

```dart
class Course {
  final int id;
  // Formal academic course code, e.g. "ENG 116", "CSC 201"
  final String code;
  final String name;
  final String roomTypeRequired;
  final int departmentId;
  final int? lecturerId;

  const Course({
    required this.id, required this.code, required this.name,
    required this.roomTypeRequired, required this.departmentId,
    this.lecturerId,
  });

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        id: json['id'] as int,
        code: json['code'] as String,
        name: json['name'] as String,
        roomTypeRequired: json['room_type_required'] as String,
        departmentId: json['department_id'] as int,
        lecturerId: json['lecturer_id'] as int?,
      );
}
```

- [ ] **Step 7: Create `lib/core/models/room.dart`**

```dart
class Room {
  final int id;
  final String name;
  final int capacity;
  final String roomType;
  final int universityId;

  const Room({
    required this.id, required this.name, required this.capacity,
    required this.roomType, required this.universityId,
  });

  factory Room.fromJson(Map<String, dynamic> json) => Room(
        id: json['id'] as int,
        name: json['name'] as String,
        capacity: json['capacity'] as int,
        roomType: json['room_type'] as String,
        universityId: json['university_id'] as int,
      );
}
```

- [ ] **Step 8: Create `lib/core/models/timetable.dart`**

```dart
class TimetableModel {
  final int id;
  final String status;
  final int semesterId;
  final int departmentId;
  final String? generatedAt;
  final String createdAt;

  const TimetableModel({
    required this.id, required this.status, required this.semesterId,
    required this.departmentId, this.generatedAt, required this.createdAt,
  });

  factory TimetableModel.fromJson(Map<String, dynamic> json) => TimetableModel(
        id: json['id'] as int,
        status: json['status'] as String,
        semesterId: json['semester_id'] as int,
        departmentId: json['department_id'] as int,
        generatedAt: json['generated_at'] as String?,
        createdAt: json['created_at'] as String,
      );

  bool get isPublished => status == 'published';
  bool get isDraft => status == 'draft';
}

class TimetableEntry {
  final int id;
  final int timetableId;
  final int courseId;
  final int lecturerId;
  final int roomId;
  final int timeSlotId;
  final int? groupId;
  final String weekPattern;
  final String? rotationSequence;
  final bool isOvercapacity;
  final bool isMerged;
  final List<int> classIds;

  const TimetableEntry({
    required this.id, required this.timetableId, required this.courseId,
    required this.lecturerId, required this.roomId, required this.timeSlotId,
    this.groupId, required this.weekPattern, this.rotationSequence,
    required this.isOvercapacity, required this.isMerged, required this.classIds,
  });

  factory TimetableEntry.fromJson(Map<String, dynamic> json) => TimetableEntry(
        id: json['id'] as int,
        timetableId: json['timetable_id'] as int,
        courseId: json['course_id'] as int,
        lecturerId: json['lecturer_id'] as int,
        roomId: json['room_id'] as int,
        timeSlotId: json['time_slot_id'] as int,
        groupId: json['group_id'] as int?,
        weekPattern: json['week_pattern'] as String,
        rotationSequence: json['rotation_sequence'] as String?,
        isOvercapacity: json['is_overcapacity'] as bool,
        isMerged: json['is_merged'] as bool,
        classIds: List<int>.from(json['class_ids'] as List),
      );
}

class TimetableConflict {
  final int id;
  final int timetableId;
  final String conflictType;
  final int? courseId;
  final int? classId;
  final String details;
  final bool resolved;
  final String? resolution;

  const TimetableConflict({
    required this.id, required this.timetableId, required this.conflictType,
    this.courseId, this.classId, required this.details,
    required this.resolved, this.resolution,
  });

  factory TimetableConflict.fromJson(Map<String, dynamic> json) => TimetableConflict(
        id: json['id'] as int,
        timetableId: json['timetable_id'] as int,
        conflictType: json['conflict_type'] as String,
        courseId: json['course_id'] as int?,
        classId: json['class_id'] as int?,
        details: json['details'] as String,
        resolved: json['resolved'] as bool,
        resolution: json['resolution'] as String?,
      );
}

class AppNotification {
  final int id;
  final String message;
  final String notificationType;
  final bool isRead;
  final String createdAt;

  const AppNotification({
    required this.id, required this.message, required this.notificationType,
    required this.isRead, required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as int,
        message: json['message'] as String,
        notificationType: json['notification_type'] as String,
        isRead: json['is_read'] as bool,
        createdAt: json['created_at'] as String,
      );
}
```

- [ ] **Step 9: Run model tests**

```bash
flutter test test/models_test.dart
```

Expected: all tests pass.

- [ ] **Step 10: Commit checkpoint**

> **Suggested commit message:** "feat: add Dart API models with JSON parsing"

```bash
git add frontend/lib/core/models/ frontend/test/models_test.dart
```

---

## Task 3: Dio API Client & API Services

**Files:**
- Create: `frontend/lib/core/api/api_client.dart`
- Create: `frontend/lib/core/api/auth_api.dart`
- Create: `frontend/lib/core/api/university_api.dart`
- Create: `frontend/lib/core/api/timetable_api.dart`

- [ ] **Step 1: Create `lib/core/api/api_client.dart`**

```dart
import 'package:dio/dio.dart';
import '../constants.dart';

class ApiClient {
  late final Dio _dio;

  ApiClient({String? token}) {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    if (token != null) {
      _dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
      ));
    }

    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      error: true,
    ));
  }

  Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      _dio.get(path, queryParameters: params);

  Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> put(String path, {dynamic data}) =>
      _dio.put(path, data: data);

  Future<Response> delete(String path) => _dio.delete(path);

  Future<Response> downloadFile(String path) =>
      _dio.get(path, options: Options(responseType: ResponseType.bytes));
}
```

- [ ] **Step 2: Create `lib/core/api/auth_api.dart`**

```dart
import '../models/user.dart';
import 'api_client.dart';

class AuthApi {
  final ApiClient _client;
  AuthApi(this._client);

  Future<TokenResponse> login(String email, String password) async {
    final response = await _client.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    return TokenResponse.fromJson(response.data as Map<String, dynamic>);
  }

  Future<UserModel> getMe() async {
    final response = await _client.get('/auth/me');
    return UserModel.fromJson(response.data as Map<String, dynamic>);
  }
}
```

- [ ] **Step 3: Create `lib/core/api/university_api.dart`**

```dart
import '../models/university.dart';
import '../models/room.dart';
import 'api_client.dart';

class UniversityApi {
  final ApiClient _client;
  UniversityApi(this._client);

  Future<List<University>> getUniversities() async {
    final response = await _client.get('/universities/');
    return (response.data as List)
        .map((e) => University.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Faculty>> getFaculties() async {
    final response = await _client.get('/faculties/');
    return (response.data as List)
        .map((e) => Faculty.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Department>> getDepartments() async {
    final response = await _client.get('/departments/');
    return (response.data as List)
        .map((e) => Department.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Room>> getRooms() async {
    final response = await _client.get('/rooms/');
    return (response.data as List)
        .map((e) => Room.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Room> createRoom(Map<String, dynamic> data) async {
    final response = await _client.post('/rooms/', data: data);
    return Room.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteRoom(int id) async {
    await _client.delete('/rooms/$id');
  }
}
```

- [ ] **Step 4: Create `lib/core/api/timetable_api.dart`**

```dart
import '../models/timetable.dart';
import 'api_client.dart';

class TimetableApi {
  final ApiClient _client;
  TimetableApi(this._client);

  Future<List<TimetableModel>> getTimetables() async {
    final response = await _client.get('/timetables/');
    return (response.data as List)
        .map((e) => TimetableModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TimetableModel> getTimetable(int id) async {
    final response = await _client.get('/timetables/$id');
    return TimetableModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<TimetableEntry>> getEntries(int timetableId) async {
    final response = await _client.get('/timetables/$timetableId/entries');
    return (response.data as List)
        .map((e) => TimetableEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TimetableConflict>> getConflicts(int timetableId) async {
    final response = await _client.get('/timetables/$timetableId/conflicts');
    return (response.data as List)
        .map((e) => TimetableConflict.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> triggerGeneration(int timetableId) async {
    final response = await _client.post('/timetables/$timetableId/generate');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getJobStatus(int timetableId) async {
    final response = await _client.get('/timetables/$timetableId/job-status');
    return response.data as Map<String, dynamic>;
  }

  Future<TimetableModel> advanceStatus(int timetableId) async {
    final response = await _client.post('/timetables/$timetableId/advance-status');
    return TimetableModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TimetableModel> publish(int timetableId) async {
    final response = await _client.post('/timetables/$timetableId/publish');
    return TimetableModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TimetableConflict> resolveConflict(
      int timetableId, int conflictId, String resolution) async {
    final response = await _client.post(
      '/timetables/$timetableId/conflicts/$conflictId/resolve',
      data: {'resolution': resolution},
    );
    return TimetableConflict.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getAnalytics(int timetableId) async {
    final response = await _client.get('/timetables/$timetableId/analytics');
    return response.data as Map<String, dynamic>;
  }

  Future<List<AppNotification>> getMyNotifications() async {
    final response = await _client.get('/timetables/notifications/mine');
    return (response.data as List)
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markNotificationRead(int notificationId) async {
    await _client.post('/timetables/notifications/$notificationId/read');
  }

  Future<List<int>> downloadExport(int timetableId, String format) async {
    final response = await _client.downloadFile(
      '/export/timetables/$timetableId/$format',
    );
    return List<int>.from(response.data as List);
  }
}
```

- [ ] **Step 5: Create `lib/core/api/academic_api.dart`**

```dart
import '../models/academic.dart';
import 'api_client.dart';

class AcademicApi {
  final ApiClient _client;
  AcademicApi(this._client);

  Future<List<Semester>> getSemesters() async {
    final response = await _client.get('/semesters/');
    return (response.data as List)
        .map((e) => Semester.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TimeSlot>> getTimeSlots(int semesterId) async {
    final response = await _client.get('/semesters/$semesterId/timeslots');
    return (response.data as List)
        .map((e) => TimeSlot.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<StudyClass>> getClasses(int departmentId) async {
    final response = await _client.get('/departments/$departmentId/classes');
    return (response.data as List)
        .map((e) => StudyClass.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
```

- [ ] **Step 6: Create `lib/core/api/user_api.dart`**

```dart
import '../models/user.dart';
import 'api_client.dart';

class UserApi {
  final ApiClient _client;
  UserApi(this._client);

  Future<List<UserModel>> getUsers() async {
    final response = await _client.get('/users/');
    return (response.data as List)
        .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<UserModel> createUser(Map<String, dynamic> data) async {
    final response = await _client.post('/users/', data: data);
    return UserModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> setAvailability(int lecturerId, List<int> unavailableSlotIds) async {
    await _client.post('/lecturers/$lecturerId/availability', data: {
      'unavailable_slot_ids': unavailableSlotIds,
    });
  }

  Future<Map<String, dynamic>> getAvailability(int lecturerId) async {
    final response = await _client.get('/lecturers/$lecturerId/availability');
    return response.data as Map<String, dynamic>;
  }
}
```

- [ ] **Step 7: Commit checkpoint**

> **Suggested commit message:** "feat: add Dio API client and all API service classes"

```bash
git add frontend/lib/core/api/
```

---

## Task 4: GetX Controllers

**Files:**
- Create: `frontend/lib/core/controllers/auth_controller.dart`
- Create: `frontend/lib/core/controllers/timetable_controller.dart`
- Create: `frontend/lib/core/controllers/notification_controller.dart`
- Create: `frontend/test/auth_controller_test.dart`

> **GetX state management primer:** `GetxController` replaces Riverpod's `StateNotifier`. Mark fields with `.obs` to make them reactive — e.g. `final isLoading = false.obs`. In screens, wrap rebuilding parts with `Obx(() => ...)`. Access any controller from anywhere with `Get.find<AuthController>()`. Register controllers once with `Get.put(AuthController())` in `app.dart`.

- [ ] **Step 1: Create `lib/core/controllers/auth_controller.dart`**

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import '../api/api_client.dart';
import '../api/auth_api.dart';
import '../models/user.dart';

class AuthController extends GetxController {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'jwt_token';

  final user = Rxn<UserModel>();
  final token = RxnString();
  final isLoading = false.obs;
  final error = RxnString();

  bool get isLoggedIn => user.value != null && token.value != null;

  @override
  void onInit() {
    super.onInit();
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    final stored = await _storage.read(key: _tokenKey);
    if (stored == null) return;
    try {
      final u = await AuthApi(ApiClient(token: stored)).getMe();
      token.value = stored;
      user.value = u;
    } catch (_) {
      await _storage.delete(key: _tokenKey);
    }
  }

  Future<void> login(String email, String password) async {
    isLoading.value = true;
    error.value = null;
    try {
      final result = await AuthApi(ApiClient()).login(email, password);
      await _storage.write(key: _tokenKey, value: result.accessToken);
      token.value = result.accessToken;
      user.value = result.user;
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    token.value = null;
    user.value = null;
    Get.offAllNamed('/login');
  }
}
```

- [ ] **Step 2: Create `lib/core/controllers/timetable_controller.dart`**

```dart
import 'package:get/get.dart';
import '../api/timetable_api.dart';
import '../api/academic_api.dart';
import '../api/api_client.dart';
import '../models/timetable.dart';
import '../models/academic.dart';
import 'auth_controller.dart';

class TimetableController extends GetxController {
  TimetableApi get _api =>
      TimetableApi(ApiClient(token: Get.find<AuthController>().token.value));

  AcademicApi get _academicApi =>
      AcademicApi(ApiClient(token: Get.find<AuthController>().token.value));

  final timetables = <TimetableModel>[].obs;
  final currentTimetable = Rxn<TimetableModel>();
  final entries = <TimetableEntry>[].obs;
  final slots = <TimeSlot>[].obs;
  final conflicts = <TimetableConflict>[].obs;
  final jobStatus = Rxn<Map<String, dynamic>>();
  final isLoading = false.obs;
  final error = RxnString();

  Future<void> loadTimetables() async {
    isLoading.value = true;
    error.value = null;
    try {
      timetables.value = await _api.getTimetables();
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadEntries(int timetableId) async {
    isLoading.value = true;
    error.value = null;
    try {
      entries.value = await _api.getEntries(timetableId);
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  /// Fetches the timetable record, then loads the time slots for its semester.
  /// Call this alongside loadEntries() in TimetableScreen.initState().
  Future<void> loadTimetableWithSlots(int timetableId) async {
    try {
      final timetable = await _api.getTimetable(timetableId);
      currentTimetable.value = timetable;
      slots.value = await _academicApi.getTimeSlots(timetable.semesterId);
    } catch (_) {}
  }

  Future<void> loadConflicts(int timetableId) async {
    isLoading.value = true;
    error.value = null;
    try {
      conflicts.value = await _api.getConflicts(timetableId);
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadJobStatus(int timetableId) async {
    try {
      jobStatus.value = await _api.getJobStatus(timetableId);
    } catch (_) {}
  }

  Future<void> triggerGeneration(int timetableId) async {
    await _api.triggerGeneration(timetableId);
    await loadJobStatus(timetableId);
  }

  Future<void> resolveConflict(
      int timetableId, int conflictId, String resolution) async {
    await _api.resolveConflict(timetableId, conflictId, resolution);
    await loadConflicts(timetableId);
  }

  Future<List<int>> downloadExport(int timetableId, String format) =>
      _api.downloadExport(timetableId, format);
}
```

- [ ] **Step 3: Create `lib/core/controllers/notification_controller.dart`**

```dart
import 'package:get/get.dart';
import '../api/timetable_api.dart';
import '../api/api_client.dart';
import '../models/timetable.dart';
import 'auth_controller.dart';

class NotificationController extends GetxController {
  TimetableApi get _api =>
      TimetableApi(ApiClient(token: Get.find<AuthController>().token.value));

  final notifications = <AppNotification>[].obs;

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  Future<void> load() async {
    try {
      notifications.value = await _api.getMyNotifications();
    } catch (_) {}
  }

  Future<void> markRead(int notificationId) async {
    await _api.markNotificationRead(notificationId);
    await load();
  }
}
```

- [ ] **Step 4: Write `test/auth_controller_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetabling/core/models/user.dart';

void main() {
  group('UserModel role helpers', () {
    test('super_admin has all access', () {
      final user = UserModel(
        id: 1, email: 'a@b.com', fullName: 'Admin',
        role: 'super_admin', isActive: true,
      );
      expect(user.isSuperAdmin, isTrue);
      expect(user.isUniversityAdmin, isTrue);
      expect(user.isDepartmentHead, isTrue);
      expect(user.isTimetableOfficer, isTrue);
      expect(user.canManageTimetable, isTrue);
    });

    test('student has no management access', () {
      final user = UserModel(
        id: 2, email: 'stu@ub.cm', fullName: 'Student',
        role: 'student', isActive: true,
      );
      expect(user.isSuperAdmin, isFalse);
      expect(user.canManageTimetable, isFalse);
      expect(user.isStudent, isTrue);
    });
  });
}
```

- [ ] **Step 5: Run tests**

```bash
flutter test test/auth_controller_test.dart test/models_test.dart
```

Expected: all tests pass.

- [ ] **Step 6: Commit checkpoint**

> **Suggested commit message:** "feat: add GetX auth, timetable, and notification controllers"

```bash
git add frontend/lib/core/controllers/ frontend/test/auth_controller_test.dart
```

---

## Task 5: GetX Routes & App Shell

**Files:**
- Create: `frontend/lib/core/routes.dart`
- Create: `frontend/lib/core/theme.dart`
- Create: `frontend/lib/app.dart`

> **GetX navigation primer:** Use named routes instead of GoRouter. Define name constants in `AppRoutes`. Navigate with `Get.toNamed('/dashboard')` or `Get.offAllNamed('/login')`. Pass route parameters with `Get.toNamed('/timetable', parameters: {'id': '5'})` and read them with `Get.parameters['id']`. Guard routes by implementing `GetMiddleware` — return a new `RouteSettings` to redirect, or `null` to allow through.

- [ ] **Step 1: Create `lib/core/theme.dart`**

> **Note (web only):** `google_fonts` downloads fonts from Google's CDN at runtime. When running on Flutter Web with `flutter run -d chrome`, the device needs internet access for fonts to load. In production, the app works normally. In offline development, fall back to a system sans-serif font by omitting the `google_fonts` line if you see font-load errors.

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const _primaryColor = Color(0xFF1565C0);
  static const _warningColor = Color(0xFFF57F17);

  static final light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _primaryColor,
      brightness: Brightness.light,
    ),
    textTheme: GoogleFonts.interTextTheme(),
    appBarTheme: const AppBarTheme(
      backgroundColor: _primaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: CardTheme(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );

  static final dark = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _primaryColor,
      brightness: Brightness.dark,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.grey[900],
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: CardTheme(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  static const warningColor = _warningColor;
}
```

- [ ] **Step 2: Create placeholder screens so routes can compile**

Create each file below with a minimal scaffold. These will be replaced in later tasks.

`lib/features/auth/login_screen.dart`:
```dart
import 'package:flutter/material.dart';
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Login')));
}
```

`lib/features/dashboard/dashboard_screen.dart`:
```dart
import 'package:flutter/material.dart';
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Dashboard')));
}
```

`lib/features/timetable/timetable_screen.dart`:
```dart
import 'package:flutter/material.dart';
class TimetableScreen extends StatelessWidget {
  final int timetableId;
  const TimetableScreen({super.key, required this.timetableId});
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text('Timetable $timetableId')));
}
```

`lib/features/timetable/timetable_grid.dart`:
```dart
import 'package:flutter/material.dart';
import '../../core/models/timetable.dart';
import '../../core/models/academic.dart';
class TimetableGrid extends StatelessWidget {
  final List<TimetableEntry> entries;
  final List<TimeSlot> slots;
  final Map<int, String> courseNames;
  final Map<int, String> roomNames;
  final Map<int, String> lecturerNames;
  const TimetableGrid({super.key, required this.entries, required this.slots,
    required this.courseNames, required this.roomNames, required this.lecturerNames});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
```

`lib/features/generation/generation_screen.dart`:
```dart
import 'package:flutter/material.dart';
class GenerationScreen extends StatelessWidget {
  final int timetableId;
  const GenerationScreen({super.key, required this.timetableId});
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text('Generate $timetableId')));
}
```

`lib/features/conflicts/conflicts_screen.dart`:
```dart
import 'package:flutter/material.dart';
class ConflictsScreen extends StatelessWidget {
  final int timetableId;
  const ConflictsScreen({super.key, required this.timetableId});
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text('Conflicts $timetableId')));
}
```

`lib/features/management/rooms_screen.dart`:
```dart
import 'package:flutter/material.dart';
class RoomsScreen extends StatelessWidget {
  const RoomsScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Rooms')));
}
```

`lib/features/management/courses_screen.dart`:
```dart
import 'package:flutter/material.dart';
class CoursesScreen extends StatelessWidget {
  const CoursesScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Courses')));
}
```

`lib/features/management/users_screen.dart`:
```dart
import 'package:flutter/material.dart';
class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Users')));
}
```

`lib/features/management/availability_screen.dart`:
```dart
import 'package:flutter/material.dart';
class AvailabilityScreen extends StatelessWidget {
  const AvailabilityScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Availability')));
}
```

`lib/features/analytics/analytics_screen.dart`:
```dart
import 'package:flutter/material.dart';
class AnalyticsScreen extends StatelessWidget {
  final int timetableId;
  const AnalyticsScreen({super.key, required this.timetableId});
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text('Analytics $timetableId')));
}
```

`lib/features/notifications/notifications_screen.dart`:
```dart
import 'package:flutter/material.dart';
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Notifications')));
}
```

- [ ] **Step 3: Create `lib/core/routes.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/timetable/timetable_screen.dart';
import '../features/generation/generation_screen.dart';
import '../features/conflicts/conflicts_screen.dart';
import '../features/management/rooms_screen.dart';
import '../features/management/courses_screen.dart';
import '../features/management/users_screen.dart';
import '../features/management/availability_screen.dart';
import '../features/analytics/analytics_screen.dart';
import '../features/notifications/notifications_screen.dart';
import 'controllers/auth_controller.dart';

class AppRoutes {
  static const login = '/login';
  static const dashboard = '/dashboard';
  static const timetable = '/timetable';
  static const generate = '/generate';
  static const conflicts = '/conflicts';
  static const rooms = '/rooms';
  static const courses = '/courses';
  static const users = '/users';
  static const availability = '/availability';
  static const analytics = '/analytics';
  static const notifications = '/notifications';
}

class AuthMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    if (!Get.find<AuthController>().isLoggedIn) {
      return const RouteSettings(name: AppRoutes.login);
    }
    return null;
  }
}

List<GetPage> get appPages => [
      GetPage(name: AppRoutes.login, page: () => const LoginScreen()),
      GetPage(
        name: AppRoutes.dashboard,
        page: () => const DashboardScreen(),
        middlewares: [AuthMiddleware()],
      ),
      GetPage(
        name: AppRoutes.timetable,
        page: () => TimetableScreen(
          timetableId: int.parse(Get.parameters['id'] ?? '0'),
        ),
        middlewares: [AuthMiddleware()],
      ),
      GetPage(
        name: AppRoutes.generate,
        page: () => GenerationScreen(
          timetableId: int.parse(Get.parameters['id'] ?? '0'),
        ),
        middlewares: [AuthMiddleware()],
      ),
      GetPage(
        name: AppRoutes.conflicts,
        page: () => ConflictsScreen(
          timetableId: int.parse(Get.parameters['id'] ?? '0'),
        ),
        middlewares: [AuthMiddleware()],
      ),
      GetPage(
        name: AppRoutes.rooms,
        page: () => const RoomsScreen(),
        middlewares: [AuthMiddleware()],
      ),
      GetPage(
        name: AppRoutes.courses,
        page: () => const CoursesScreen(),
        middlewares: [AuthMiddleware()],
      ),
      GetPage(
        name: AppRoutes.users,
        page: () => const UsersScreen(),
        middlewares: [AuthMiddleware()],
      ),
      GetPage(
        name: AppRoutes.availability,
        page: () => const AvailabilityScreen(),
        middlewares: [AuthMiddleware()],
      ),
      GetPage(
        name: AppRoutes.analytics,
        page: () => AnalyticsScreen(
          timetableId: int.parse(Get.parameters['id'] ?? '0'),
        ),
        middlewares: [AuthMiddleware()],
      ),
      GetPage(
        name: AppRoutes.notifications,
        page: () => const NotificationsScreen(),
        middlewares: [AuthMiddleware()],
      ),
    ];
```

- [ ] **Step 4: Create `lib/app.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'core/routes.dart';
import 'core/theme.dart';
import 'core/controllers/auth_controller.dart';
import 'core/controllers/timetable_controller.dart';
import 'core/controllers/notification_controller.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    Get.put(AuthController());
    Get.put(TimetableController());
    Get.put(NotificationController());

    return GetMaterialApp(
      title: 'UniTime',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      initialRoute: AppRoutes.login,
      getPages: appPages,
      debugShowCheckedModeBanner: false,
    );
  }
}
```

- [ ] **Step 5: Verify the app compiles**

```bash
flutter run -d chrome
```

Expected: app launches showing "Login" text. No compile errors.

- [ ] **Step 6: Commit checkpoint**

> **Suggested commit message:** "feat: add GetX routing with auth middleware and placeholder screens"

```bash
git add frontend/lib/
```

---

## Task 6: Login Screen

- [ ] **Step 1: Invoke the `frontend-design` skill**

> "Design a login screen for a university timetabling system. It should feel professional and academic — royal blue primary color (#1565C0). The screen has: a centered card (max width 420px on web, full width on mobile), a university crest/icon placeholder at the top, an 'Email' TextField, a 'Password' TextField with show/hide toggle, a 'Login' primary button (full width), a loading state (button shows spinner), and an error message area below the button that shows in red. Use Material 3. The app name is 'UniTime'. No registration link — accounts are created by admins."

Use the output as the implementation guide for the next step.

- [ ] **Step 2: Write `test/widget/login_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:university_timetabling/features/auth/login_screen.dart';
import 'package:university_timetabling/core/controllers/auth_controller.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put(AuthController());
  });

  tearDown(() => Get.reset());

  testWidgets('Login screen has email and password fields and login button', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(home: const LoginScreen()),
    );
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });

  testWidgets('Login button is disabled when fields are empty', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(home: const LoginScreen()),
    );
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });
}
```

- [ ] **Step 3: Run to confirm test failures**

```bash
flutter test test/widget/login_test.dart
```

Expected: failures — `LoginScreen` is a placeholder.

- [ ] **Step 4: Implement `lib/features/auth/login_screen.dart`** using the frontend-design skill output

Replace the placeholder with the design skill output, wiring up `AuthController`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/controllers/auth_controller.dart';
import '../../core/routes.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  final _auth = Get.find<AuthController>();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    await _auth.login(_emailCtrl.text.trim(), _passwordCtrl.text);
    if (_auth.isLoggedIn) {
      Get.offAllNamed(AppRoutes.dashboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.school, size: 64, color: theme.colorScheme.primary),
                      const SizedBox(height: 8),
                      Text('UniTime', style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      )),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outlined),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () =>
                                setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Password is required' : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      Obx(() {
                        if (_auth.error.value == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _auth.error.value!.contains('401')
                                ? 'Invalid email or password'
                                : 'Login failed. Check your connection.',
                            style: TextStyle(color: theme.colorScheme.error),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }),
                      const SizedBox(height: 24),
                      Obx(() => SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (_emailCtrl.text.isNotEmpty &&
                                  _passwordCtrl.text.isNotEmpty &&
                                  !_auth.isLoading.value)
                              ? _login
                              : null,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: _auth.isLoading.value
                              ? const SizedBox(
                                  height: 20, width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2,
                                  ),
                                )
                              : const Text('Login', style: TextStyle(fontSize: 16)),
                        ),
                      )),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run tests**

```bash
flutter test test/widget/login_test.dart
```

Expected: both tests pass.

- [ ] **Step 6: Commit checkpoint**

> **Suggested commit message:** "feat: implement login screen with GetX auth controller"

```bash
git add frontend/lib/features/auth/ frontend/test/widget/login_test.dart
```

---

## Task 7: Dashboard Screen (Role-Adaptive)

- [ ] **Step 1: Invoke the `frontend-design` skill**

> "Design a role-adaptive dashboard for a university timetabling system. The layout is a sidebar navigation (on web, screen width > 800px) or bottom nav (on mobile). The sidebar has: the app logo 'UniTime' at top, user name + role chip below it, and navigation items. Navigation items vary by role: Super Admin sees [Universities, System Settings]; University Admin sees [Semesters, Faculties, Rooms, Users]; Department Head sees [Timetables, Conflicts, Analytics, Session Rules]; Timetable Officer sees [Timetables, Courses, Lecturers, Generate]; Lecturer sees [My Schedule, Availability]; Student sees [My Timetable]. All roles see a Notifications item with a badge count. The main content area shows a welcome card with the user's name, role, and 3-4 quick-action cards relevant to their role. Royal blue primary color (#1565C0), Material 3, clean academic feel."

- [ ] **Step 2: Implement `lib/features/dashboard/dashboard_screen.dart`** using design skill output

```dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../../core/controllers/auth_controller.dart';
import '../../core/controllers/notification_controller.dart';
import '../../core/models/user.dart';
import '../../core/routes.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final notif = Get.find<NotificationController>();

    return Obx(() {
      final user = auth.user.value;
      if (user == null) return const SizedBox.shrink();

      final navItems = _navItemsForRole(user);
      final width = MediaQuery.of(context).size.width;

      // >1200px: full sidebar with labels
      if (width > 1200) {
        return Scaffold(
          body: Row(
            children: [
              _Sidebar(user: user, items: navItems, notif: notif),
              const VerticalDivider(width: 1),
              Expanded(child: _WelcomeContent(user: user, items: navItems)),
            ],
          ),
        );
      }

      // 800–1200px: icon-only NavigationRail
      if (width > 800) {
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                labelType: NavigationRailLabelType.none,
                destinations: navItems.map((item) => NavigationRailDestination(
                  icon: Stack(children: [
                    Icon(item.icon),
                    if (item.label == 'Notifications')
                      Obx(() {
                        if (notif.unreadCount == 0) return const SizedBox.shrink();
                        return Positioned(
                          right: 0, top: 0,
                          child: CircleAvatar(
                            radius: 7, backgroundColor: Colors.red,
                            child: Text('${notif.unreadCount}',
                                style: const TextStyle(fontSize: 9, color: Colors.white)),
                          ),
                        );
                      }),
                  ]),
                  label: Text(item.label),
                )).toList(),
                selectedIndex: 0,
                onDestinationSelected: (i) => Get.toNamed(navItems[i].route),
                leading: Column(children: [
                  const SizedBox(height: 8),
                  const Icon(Icons.school, size: 28),
                  const SizedBox(height: 8),
                  IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Logout',
                    onPressed: auth.logout,
                  ),
                ]),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(child: _WelcomeContent(user: user, items: navItems)),
            ],
          ),
        );
      }

      // <800px: BottomNavigationBar for mobile
      return Scaffold(
        appBar: AppBar(
          title: const Text('UniTime'),
          actions: [
            Stack(children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => Get.toNamed(AppRoutes.notifications),
              ),
              Obx(() {
                if (notif.unreadCount == 0) return const SizedBox.shrink();
                return Positioned(
                  right: 8, top: 8,
                  child: CircleAvatar(
                    radius: 8, backgroundColor: Colors.red,
                    child: Text('${notif.unreadCount}',
                        style: const TextStyle(fontSize: 10, color: Colors.white)),
                  ),
                );
              }),
            ]),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: auth.logout,
            ),
          ],
        ),
        body: _WelcomeContent(user: user, items: navItems),
        bottomNavigationBar: NavigationBar(
          destinations: navItems
              .take(5)
              .map((item) => NavigationDestination(
                    icon: Icon(item.icon), label: item.label))
              .toList(),
          onDestinationSelected: (i) => Get.toNamed(navItems[i].route),
        ),
      );
    });
  }

  List<_NavItem> _navItemsForRole(UserModel user) {
    if (user.isSuperAdmin) {
      return [
        _NavItem('Dashboard', Icons.dashboard, AppRoutes.dashboard),
        _NavItem('Rooms', Icons.meeting_room, AppRoutes.rooms),
        _NavItem('Notifications', Icons.notifications_outlined, AppRoutes.notifications),
      ];
    }
    if (user.isUniversityAdmin) {
      return [
        _NavItem('Dashboard', Icons.dashboard, AppRoutes.dashboard),
        _NavItem('Rooms', Icons.meeting_room, AppRoutes.rooms),
        _NavItem('Courses', Icons.book, AppRoutes.courses),
        _NavItem('Users', Icons.people, AppRoutes.users),
        _NavItem('Notifications', Icons.notifications_outlined, AppRoutes.notifications),
      ];
    }
    if (user.isDepartmentHead) {
      return [
        _NavItem('Dashboard', Icons.dashboard, AppRoutes.dashboard),
        _NavItem('Courses', Icons.book, AppRoutes.courses),
        _NavItem('Analytics', Icons.bar_chart, AppRoutes.analytics),
        _NavItem('Notifications', Icons.notifications_outlined, AppRoutes.notifications),
      ];
    }
    if (user.isTimetableOfficer) {
      return [
        _NavItem('Dashboard', Icons.dashboard, AppRoutes.dashboard),
        _NavItem('Courses', Icons.book, AppRoutes.courses),
        _NavItem('Users', Icons.person, AppRoutes.users),
        _NavItem('Notifications', Icons.notifications_outlined, AppRoutes.notifications),
      ];
    }
    if (user.isLecturer) {
      return [
        _NavItem('My Schedule', Icons.calendar_today, AppRoutes.dashboard),
        _NavItem('Availability', Icons.event_available, AppRoutes.availability),
        _NavItem('Notifications', Icons.notifications_outlined, AppRoutes.notifications),
      ];
    }
    return [
      _NavItem('My Timetable', Icons.calendar_today, AppRoutes.dashboard),
      _NavItem('Notifications', Icons.notifications_outlined, AppRoutes.notifications),
    ];
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  const _NavItem(this.label, this.icon, this.route);
}

class _Sidebar extends StatelessWidget {
  final UserModel user;
  final List<_NavItem> items;
  final NotificationController notif;

  const _Sidebar({required this.user, required this.items, required this.notif});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 240,
      child: Column(
        children: [
          Container(
            color: theme.colorScheme.primary,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.school, color: Colors.white, size: 36),
                const SizedBox(height: 8),
                Text('UniTime',
                    style: theme.textTheme.titleLarge?.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text(user.fullName,
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                Chip(
                  label: Text(user.role.replaceAll('_', ' '),
                      style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.white24,
                  labelStyle: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: items.map((item) => ListTile(
                leading: Stack(children: [
                  Icon(item.icon),
                  if (item.label == 'Notifications')
                    Obx(() {
                      if (notif.unreadCount == 0) return const SizedBox.shrink();
                      return Positioned(
                        right: 0, top: 0,
                        child: CircleAvatar(
                          radius: 7, backgroundColor: Colors.red,
                          child: Text('${notif.unreadCount}',
                              style: const TextStyle(fontSize: 9, color: Colors.white)),
                        ),
                      );
                    }),
                ]),
                title: Text(item.label),
                onTap: () => Get.toNamed(item.route),
              )).toList(),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: Get.find<AuthController>().logout,
          ),
        ],
      ),
    );
  }
}

class _WelcomeContent extends StatelessWidget {
  final UserModel user;
  final List<_NavItem> items;
  const _WelcomeContent({required this.user, required this.items});

  @override
  Widget build(BuildContext context) {
    final cards = items.skip(1).toList();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome back, ${user.fullName.split(' ').first}!',
              style: Theme.of(context).textTheme.headlineMedium)
              .animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16, runSpacing: 16,
            children: cards.indexed.map((e) =>
              _QuickActionCard(item: e.$2)
                .animate(delay: Duration(milliseconds: e.$1 * 60))
                .fadeIn(duration: 250.ms)
                .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),
            ).toList(),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final _NavItem item;
  const _QuickActionCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Get.toNamed(item.route),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        child: SizedBox(
          width: 160, height: 120,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, size: 36, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(item.label, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ).animate(onPlay: (c) => c.forward())
        .scale(begin: const Offset(1, 1), end: const Offset(1, 1));
  }
}
```

- [ ] **Step 3: Run app and verify dashboard**

```bash
flutter run -d chrome
```

Log in with a test account. Expected: sidebar on web, bottom nav on mobile, role-based menu items.

- [ ] **Step 4: Commit checkpoint**

> **Suggested commit message:** "feat: implement role-adaptive dashboard with GetX navigation"

```bash
git add frontend/lib/features/dashboard/
```

---

## Task 8: Timetable Grid Screen

- [ ] **Step 1: Invoke the `frontend-design` skill**

> "Design a weekly timetable grid screen for a university. The grid has days as columns (Monday to Friday) and time slots as rows (e.g. 7:00-9:00, 9:00-11:00, etc.). Each cell can contain a course entry card showing: course code (bold), lecturer name, room name, and a small badge for merged/overcapacity sessions. Overcapacity entries have an amber background. Merged entries have a subtle blue border. The screen has: a top bar with the timetable name and status chip (Draft/Published/etc.), an Export button (PDF/CSV dropdown), and a filter chip row to show all classes or filter by class name. Use Material 3, deep indigo primary color. The grid is scrollable both horizontally and vertically for many slots."

- [ ] **Step 2: Write `test/widget/timetable_grid_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetabling/features/timetable/timetable_grid.dart';
import 'package:university_timetabling/core/models/timetable.dart';
import 'package:university_timetabling/core/models/academic.dart';

void main() {
  testWidgets('TimetableGrid renders day headers', (tester) async {
    final slots = [
      TimeSlot(id: 1, dayOfWeek: 'Monday', startTime: '07:00', endTime: '09:00', semesterId: 1),
      TimeSlot(id: 2, dayOfWeek: 'Wednesday', startTime: '07:00', endTime: '09:00', semesterId: 1),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TimetableGrid(
        entries: const [], slots: slots,
        courseNames: const {}, roomNames: const {}, lecturerNames: const {},
      )),
    ));
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Wednesday'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run to confirm failure**

```bash
flutter test test/widget/timetable_grid_test.dart
```

Expected: fails because `TimetableGrid` is a stub that returns `SizedBox.shrink()`.

- [ ] **Step 4: Implement `lib/features/timetable/timetable_grid.dart`** using design skill output

```dart
import 'package:flutter/material.dart';
import '../../core/models/timetable.dart';
import '../../core/models/academic.dart';

class TimetableGrid extends StatelessWidget {
  final List<TimetableEntry> entries;
  final List<TimeSlot> slots;
  final Map<int, String> courseNames;
  final Map<int, String> roomNames;
  final Map<int, String> lecturerNames;

  const TimetableGrid({
    super.key,
    required this.entries,
    required this.slots,
    required this.courseNames,
    required this.roomNames,
    required this.lecturerNames,
  });

  @override
  Widget build(BuildContext context) {
    final days = slots.map((s) => s.dayOfWeek).toSet().toList();
    final slotLabels = slots.map((s) => s.label).toSet().toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Table(
          border: TableBorder.all(color: Colors.grey.shade300),
          defaultColumnWidth: const FixedColumnWidth(160),
          children: [
            TableRow(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
              children: [
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Time',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                ...days.map((d) => Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(d,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                    )),
              ],
            ),
            ...slotLabels.map((label) {
              final rowSlots = slots.where((s) => s.label == label).toList();
              return TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(label,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  ),
                  ...days.map((day) {
                    final slot = rowSlots.firstWhere(
                        (s) => s.dayOfWeek == day,
                        orElse: () => TimeSlot(
                            id: -1,
                            dayOfWeek: day,
                            startTime: '',
                            endTime: '',
                            semesterId: -1));
                    if (slot.id == -1) return const SizedBox(height: 60);
                    final entry =
                        entries.where((e) => e.timeSlotId == slot.id).firstOrNull;
                    return _EntryCell(
                      entry: entry,
                      courseNames: courseNames,
                      roomNames: roomNames,
                      lecturerNames: lecturerNames,
                    );
                  }),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _EntryCell extends StatelessWidget {
  final TimetableEntry? entry;
  final Map<int, String> courseNames;
  final Map<int, String> roomNames;
  final Map<int, String> lecturerNames;

  const _EntryCell({
    this.entry,
    required this.courseNames,
    required this.roomNames,
    required this.lecturerNames,
  });

  @override
  Widget build(BuildContext context) {
    if (entry == null) return Container(height: 80, color: Colors.grey.shade50);

    final bg = entry!.isOvercapacity
        ? Colors.amber.shade50
        : entry!.isMerged
            ? Colors.blue.shade50
            : Colors.white;

    return Container(
      height: 80,
      color: bg,
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            courseNames[entry!.courseId] ?? 'Course ${entry!.courseId}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
          Text(lecturerNames[entry!.lecturerId] ?? '',
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
          Text(roomNames[entry!.roomId] ?? '',
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
          if (entry!.isOvercapacity)
            const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Implement `lib/features/timetable/timetable_screen.dart`** using design skill output

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../core/controllers/timetable_controller.dart';
import 'timetable_grid.dart';

class TimetableScreen extends StatefulWidget {
  final int timetableId;
  const TimetableScreen({super.key, required this.timetableId});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  final _ctrl = Get.find<TimetableController>();

  @override
  void initState() {
    super.initState();
    _ctrl.loadEntries(widget.timetableId);
    _ctrl.loadTimetableWithSlots(widget.timetableId);
  }

  Future<void> _download(String format) async {
    try {
      final bytes = await _ctrl.downloadExport(widget.timetableId, format);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/timetable_${widget.timetableId}.$format');
      await file.writeAsBytes(bytes);
      await OpenFilex.open(file.path);
    } catch (e) {
      Get.snackbar('Export failed', e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timetable'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.download),
            onSelected: _download,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
              const PopupMenuItem(value: 'csv', child: Text('Export CSV')),
            ],
          ),
        ],
      ),
      body: Obx(() {
        if (_ctrl.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_ctrl.error.value != null) {
          return Center(child: Text('Error: ${_ctrl.error.value}'));
        }
        return TimetableGrid(
          entries: _ctrl.entries,
          slots: _ctrl.slots,
          courseNames: const {},
          roomNames: const {},
          lecturerNames: const {},
        );
      }),
    );
  }
}
```

- [ ] **Step 6: Run grid tests**

```bash
flutter test test/widget/timetable_grid_test.dart
```

Expected: test passes.

- [ ] **Step 7: Commit checkpoint**

> **Suggested commit message:** "feat: implement timetable grid view and timetable screen with export"

```bash
git add frontend/lib/features/timetable/ frontend/test/widget/timetable_grid_test.dart
```

---

## Task 9: Generation, Conflicts & Notifications Screens

---

### Generation Screen

- [ ] **Step 1: Invoke `frontend-design` skill**

> "Design a timetable generation screen for a university timetabling system. It has: a top section showing timetable info (semester, department, status chip). A large 'Generate Timetable' button (disabled if a job is already running). A job status card that shows: status (pending/running/completed/failed), elapsed time, a spinner when running. If completed: a green success banner with 'View Timetable' button. If failed: a red error card with the error message and a Retry button. If there are unresolved conflicts: an amber card with 'X conflicts need your attention' and a 'Resolve Conflicts' button. Material 3, royal blue (#1565C0)."

- [ ] **Step 2: Implement `lib/features/generation/generation_screen.dart`**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/controllers/timetable_controller.dart';
import '../../core/routes.dart';

class GenerationScreen extends StatefulWidget {
  final int timetableId;
  const GenerationScreen({super.key, required this.timetableId});

  @override
  State<GenerationScreen> createState() => _GenerationScreenState();
}

class _GenerationScreenState extends State<GenerationScreen> {
  final _ctrl = Get.find<TimetableController>();
  bool _isTriggering = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _ctrl.loadJobStatus(widget.timetableId);
    _ctrl.loadConflicts(widget.timetableId);
    // Poll every 4 seconds while a job is running or pending.
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      final status = _ctrl.jobStatus.value?['status'] as String?;
      if (status == 'running' || status == 'pending') {
        _ctrl.loadJobStatus(widget.timetableId);
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _trigger() async {
    setState(() => _isTriggering = true);
    try {
      await _ctrl.triggerGeneration(widget.timetableId);
    } catch (e) {
      Get.snackbar('Error', 'Failed to start generation: $e');
    } finally {
      if (mounted) setState(() => _isTriggering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generate Timetable')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Obx(() {
              final job = _ctrl.jobStatus.value;
              if (job == null) return const SizedBox.shrink();
              return _JobStatusCard(job: job, timetableId: widget.timetableId);
            }),
            const SizedBox(height: 24),
            Obx(() {
              if (_ctrl.conflicts.isEmpty) return const SizedBox.shrink();
              return Card(
                color: Colors.amber.shade50,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber, color: Colors.orange),
                  title: Text('${_ctrl.conflicts.length} conflict(s) need attention'),
                  trailing: TextButton(
                    onPressed: () => Get.toNamed(
                      AppRoutes.conflicts,
                      parameters: {'id': widget.timetableId.toString()},
                    ),
                    child: const Text('Resolve'),
                  ),
                ),
              );
            }),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _isTriggering ? null : _trigger,
              icon: _isTriggering
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.play_arrow),
              label: const Text('Generate Timetable'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobStatusCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final int timetableId;
  const _JobStatusCard({required this.job, required this.timetableId});

  @override
  Widget build(BuildContext context) {
    final status = job['status'] as String? ?? 'no_job';
    Color color;
    IconData icon;
    switch (status) {
      case 'completed':
        color = Colors.green.shade50;
        icon = Icons.check_circle;
        break;
      case 'failed':
        color = Colors.red.shade50;
        icon = Icons.error;
        break;
      case 'running':
        color = Colors.blue.shade50;
        icon = Icons.hourglass_top;
        break;
      default:
        color = Colors.grey.shade100;
        icon = Icons.info_outline;
    }
    return Card(
      color: color,
      child: ListTile(
        leading: status == 'running' ? const CircularProgressIndicator() : Icon(icon),
        title: Text('Status: ${status.replaceAll('_', ' ').toUpperCase()}'),
        subtitle: job['error_message'] != null
            ? Text(job['error_message'] as String,
                style: const TextStyle(color: Colors.red))
            : null,
        trailing: status == 'completed'
            ? TextButton(
                onPressed: () => Get.toNamed(
                  AppRoutes.timetable,
                  parameters: {'id': timetableId.toString()},
                ),
                child: const Text('View'),
              )
            : null,
      ),
    );
  }
}
```

---

### Conflicts Screen

- [ ] **Step 3: Invoke `frontend-design` skill for conflicts**

> "Design a conflict resolution screen for a department head in a university timetabling system. It shows a list of unresolved conflicts. Each conflict card shows: conflict type (e.g. 'Lab Split Conflict'), course code, the problem description (e.g. '130 students need 4 groups but only 2 weekly slots'), and two action buttons: 'Add Session This Week' and 'Rotate Groups Weekly'. Resolved conflicts are shown in a separate collapsed section. Material 3, amber warning color accents."

- [ ] **Step 4: Implement `lib/features/conflicts/conflicts_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:convert';
import '../../core/controllers/timetable_controller.dart';
import '../../core/models/timetable.dart';

class ConflictsScreen extends StatefulWidget {
  final int timetableId;
  const ConflictsScreen({super.key, required this.timetableId});

  @override
  State<ConflictsScreen> createState() => _ConflictsScreenState();
}

class _ConflictsScreenState extends State<ConflictsScreen> {
  final _ctrl = Get.find<TimetableController>();

  @override
  void initState() {
    super.initState();
    _ctrl.loadConflicts(widget.timetableId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resolve Conflicts')),
      body: Obx(() {
        if (_ctrl.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_ctrl.conflicts.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 64, color: Colors.green),
                SizedBox(height: 16),
                Text('No unresolved conflicts'),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _ctrl.conflicts.length,
          itemBuilder: (_, i) => _ConflictCard(
            conflict: _ctrl.conflicts[i],
            timetableId: widget.timetableId,
          ),
        );
      }),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  final TimetableConflict conflict;
  final int timetableId;
  const _ConflictCard({required this.conflict, required this.timetableId});

  Map<String, dynamic> _parseDetails(String details) {
    try {
      return jsonDecode(details) as Map<String, dynamic>;
    } catch (_) {
      return {'message': details};
    }
  }

  Future<void> _resolve(String resolution) async {
    try {
      await Get.find<TimetableController>()
          .resolveConflict(timetableId, conflict.id, resolution);
    } catch (e) {
      Get.snackbar('Error', 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = _parseDetails(conflict.details);
    return Card(
      color: Colors.amber.shade50,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.warning_amber, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                conflict.conflictType.replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ]),
            const SizedBox(height: 8),
            Text(details['message']?.toString() ?? conflict.details),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _resolve('add_session'),
                  child: const Text('Add Session'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _resolve('rotate_groups'),
                  child: const Text('Rotate Groups'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
```

---

### Notifications Screen

- [ ] **Step 5: Implement `lib/features/notifications/notifications_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../../core/controllers/notification_controller.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _ctrl = Get.find<NotificationController>();

  @override
  void initState() {
    super.initState();
    _ctrl.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: Obx(() {
        if (_ctrl.notifications.isEmpty) {
          return const Center(child: Text('No notifications yet'));
        }
        return ListView.builder(
          itemCount: _ctrl.notifications.length,
          itemBuilder: (_, i) {
            final n = _ctrl.notifications[i];
            return ListTile(
              leading: Icon(
                n.isRead ? Icons.notifications_none : Icons.notifications,
                color: n.isRead ? Colors.grey : Theme.of(context).colorScheme.primary,
              ),
              title: Text(n.message,
                  style: TextStyle(
                      fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold)),
              subtitle: Text(n.createdAt),
              tileColor: n.isRead ? null : Colors.blue.shade50,
              onTap: () { if (!n.isRead) _ctrl.markRead(n.id); },
            ).animate(delay: Duration(milliseconds: i * 40))
                .fadeIn(duration: 250.ms)
                .slideX(begin: 0.05, end: 0, curve: Curves.easeOut);
          },
        );
      }),
    );
  }
}
```

- [ ] **Step 6: Commit checkpoint**

> **Suggested commit message:** "feat: implement generation, conflicts, and notifications screens"

```bash
git add frontend/lib/features/
```

---

## Task 10: Analytics Screen

- [ ] **Step 1: Invoke `frontend-design` skill**

> "Design an analytics dashboard screen for a department head in a university timetabling app. It has: a summary row of 2 stat cards (Total Sessions, Overcapacity Sessions). Below that: a bar chart showing 'Sessions per Lecturer' (using fl_chart BarChart). An overcapacity warning card at the bottom. Material 3, royal blue (#1565C0), clean data visualization style."

- [ ] **Step 2: Implement `lib/features/analytics/analytics_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get/get.dart';
import '../../core/api/timetable_api.dart';
import '../../core/api/api_client.dart';
import '../../core/controllers/auth_controller.dart';

class AnalyticsScreen extends StatefulWidget {
  final int timetableId;
  const AnalyticsScreen({super.key, required this.timetableId});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = TimetableApi(
          ApiClient(token: Get.find<AuthController>().token.value));
      final data = await api.getAnalytics(widget.timetableId);
      setState(() { _data = data; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? const Center(child: Text('Failed to load analytics'))
              : _AnalyticsBody(data: _data!),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AnalyticsBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = data['total_entries'] as int? ?? 0;
    final overcapacity = data['overcapacity_count'] as int? ?? 0;
    final lecturerCounts = Map<String, int>.from(
      (data['lecturer_session_counts'] as Map? ?? {})
          .map((k, v) => MapEntry(k.toString(), v as int)),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _StatCard('Total Sessions', '$total', Icons.calendar_month, Colors.blue),
            const SizedBox(width: 12),
            _StatCard('Overcapacity', '$overcapacity', Icons.warning_amber, Colors.orange),
          ]),
          if (lecturerCounts.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Sessions per Lecturer',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: BarChart(BarChartData(
                barGroups: lecturerCounts.entries.indexed.map((e) {
                  return BarChartGroupData(x: e.$1, barRods: [
                    BarChartRodData(
                      toY: e.$2.value.toDouble(),
                      color: Theme.of(context).colorScheme.primary,
                      width: 20,
                    ),
                  ]);
                }).toList(),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, _) => Text(
                        'L${(val + 1).toInt()}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                ),
              )),
            ),
          ],
          if (overcapacity > 0) ...[
            const SizedBox(height: 24),
            Card(
              color: Colors.amber.shade50,
              child: ListTile(
                leading: const Icon(Icons.warning_amber, color: Colors.orange),
                title: Text('$overcapacity session(s) exceed room capacity'),
                subtitle: const Text('View timetable to see highlighted entries'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Commit checkpoint**

> **Suggested commit message:** "feat: implement analytics screen with bar charts"

```bash
git add frontend/lib/features/analytics/
```

---

## Task 11: Management Screens (Rooms, Courses, Users, Availability)

For each screen: invoke `frontend-design` first, then implement. Access the API via `ApiClient(token: Get.find<AuthController>().token.value)`.

- [ ] **Step 1: Invoke `frontend-design` for Rooms screen**

> "Design a room management screen for a university admin. It shows a searchable list of rooms with: room name, capacity badge, room type chip (Lecture Hall / Lab / Studio). A FAB opens an 'Add Room' bottom sheet with fields: Name, Capacity (number), Room Type (dropdown). Each list item has a trailing delete icon. Material 3."

- [ ] **Step 2: Implement `lib/features/management/rooms_screen.dart`** using design skill output

Wire to `UniversityApi(ApiClient(token: Get.find<AuthController>().token.value))`. Call `getRooms()` on init state, `createRoom(data)` on FAB save, `deleteRoom(id)` on delete.

- [ ] **Step 3: Invoke `frontend-design` for Courses screen**

> "Design a course management screen for a timetable officer. A searchable list showing: course code (bold), course name, room type chip, assigned lecturer name (or 'Unassigned'). A FAB opens 'Add Course' bottom sheet with: Code, Name, Room Type (dropdown), Department (dropdown), Lecturer (dropdown, optional). Edit and delete buttons on each item. Material 3."

- [ ] **Step 4: Create `lib/core/api/course_api.dart`**

```dart
import '../models/course.dart';
import 'api_client.dart';

class CourseApi {
  final ApiClient _client;
  CourseApi(this._client);

  Future<List<Course>> getCourses() async {
    final response = await _client.get('/courses/');
    return (response.data as List)
        .map((e) => Course.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Course> createCourse(Map<String, dynamic> data) async {
    final response = await _client.post('/courses/', data: data);
    return Course.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteCourse(int id) async {
    await _client.delete('/courses/$id');
  }
}
```

- [ ] **Step 5: Implement `lib/features/management/courses_screen.dart`** using design skill output

Wire to `CourseApi(ApiClient(token: Get.find<AuthController>().token.value))`.

- [ ] **Step 6: Invoke `frontend-design` for Users screen**

> "Design a user management screen for a university admin in a timetabling system. It shows a searchable list of users with: full name (bold), role chip (color-coded: Super Admin = purple, University Admin = blue, Department Head = teal, Timetable Officer = indigo, Lecturer = green, Student = grey), and email. A FAB opens 'Add User' bottom sheet with fields: Full Name, Email, Password, Role (dropdown). Each list item has a trailing delete icon with confirmation dialog. Material 3, royal blue (#1565C0)."

- [ ] **Step 7: Implement `lib/features/management/users_screen.dart`** using design skill output

Wire to `UserApi(ApiClient(token: Get.find<AuthController>().token.value))`. Call `getUsers()` on init state, `createUser(data)` on FAB save.

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/api/user_api.dart';
import '../../core/api/api_client.dart';
import '../../core/controllers/auth_controller.dart';
import '../../core/models/user.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late final UserApi _api;
  List<UserModel> _users = [];
  bool _loading = true;
  String _search = '';

  final _roles = const [
    'university_admin', 'department_head', 'timetable_officer', 'lecturer', 'student',
  ];

  static const _roleColors = {
    'super_admin': Colors.purple,
    'university_admin': Colors.blue,
    'department_head': Colors.teal,
    'timetable_officer': Colors.indigo,
    'lecturer': Colors.green,
    'student': Colors.grey,
  };

  @override
  void initState() {
    super.initState();
    _api = UserApi(ApiClient(token: Get.find<AuthController>().token.value));
    _load();
  }

  Future<void> _load() async {
    try {
      final users = await _api.getUsers();
      setState(() { _users = users; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _showAddSheet() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String selectedRole = _roles.first;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add User', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              TextField(controller: passCtrl,
                  decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                  obscureText: true),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                items: _roles.map((r) => DropdownMenuItem(
                  value: r,
                  child: Text(r.replaceAll('_', ' ')),
                )).toList(),
                onChanged: (v) => setSheetState(() => selectedRole = v!),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  try {
                    await _api.createUser({
                      'full_name': nameCtrl.text.trim(),
                      'email': emailCtrl.text.trim(),
                      'password': passCtrl.text,
                      'role': selectedRole,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _load();
                  } catch (e) {
                    Get.snackbar('Error', 'Failed: $e');
                  }
                },
                child: const Text('Create User'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _users.where((u) =>
        u.fullName.toLowerCase().contains(_search.toLowerCase()) ||
        u.email.toLowerCase().contains(_search.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        child: const Icon(Icons.person_add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search by name or email',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final u = filtered[i];
                      final roleColor = _roleColors[u.role] ?? Colors.grey;
                      return ListTile(
                        title: Text(u.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(u.email),
                        trailing: Chip(
                          label: Text(u.role.replaceAll('_', ' '),
                              style: const TextStyle(fontSize: 11, color: Colors.white)),
                          backgroundColor: roleColor,
                          padding: EdgeInsets.zero,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
```

- [ ] **Step 9: Invoke `frontend-design` for Availability screen**

> "Design a lecturer availability declaration screen. It shows a weekly grid (days as columns, time slots as rows). Each cell is a toggle — green means available, red means unavailable. A Save button at the bottom commits all changes. A notice at the top says 'Declare times you are NOT available. The system will avoid scheduling you during these periods.' Material 3."

- [ ] **Step 10: Implement `lib/features/management/availability_screen.dart`** using design skill output

Wire to `UserApi(ApiClient(token: Get.find<AuthController>().token.value))`. Use `getAvailability(id)` on init and `setAvailability(id, slotIds)` on save. Read the lecturer ID from `Get.find<AuthController>().user.value!.id`.

- [ ] **Step 11: Commit checkpoint all management screens**

> **Suggested commit message:** "feat: implement rooms, courses, users, and availability management screens"

```bash
git add frontend/lib/features/management/ frontend/lib/core/api/course_api.dart frontend/lib/core/api/user_api.dart
```

---

## Task 12: Final Verification

- [ ] **Step 1: Run all tests**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 2: Run the app on web and manually verify**

```bash
flutter run -d chrome
```

Verify these flows:
1. Login → redirects to dashboard
2. Wrong credentials → error message shown below button
3. Logout → redirects to login page
4. Dashboard sidebar shows role-specific nav items (login with different roles to verify)
5. Timetable grid renders day headers (Monday, Wednesday, etc.)
6. Notifications badge appears when there are unread notifications
7. Conflicts screen shows empty state when no conflicts

- [ ] **Step 3: Run on mobile (if a device is connected)**

```bash
flutter run
```

Expected: bottom nav appears instead of sidebar.

- [ ] **Step 4: Final commit checkpoint**

> **Suggested commit message:** "feat: complete Flutter frontend with GetX state management and routing"

```bash
git add .
```
