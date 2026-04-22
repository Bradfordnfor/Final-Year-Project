import 'package:flutter_test/flutter_test.dart';
import 'package:university_timetabling/core/models/user.dart';
import 'package:university_timetabling/core/models/timetable.dart';
import 'package:university_timetabling/core/models/university.dart';
import 'package:university_timetabling/core/models/room.dart';

void main() {
  group('UserModel', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1, 'email': 'admin@ub.cm', 'full_name': 'Admin',
        'role': 'super_admin', 'is_active': true,
        'university_id': null, 'department_id': null, 'faculty_id': null,
      };
      final user = UserModel.fromJson(json);
      expect(user.id, 1);
      expect(user.role, 'super_admin');
      expect(user.isSuperAdmin, isTrue);
      expect(user.canManageTimetable, isTrue);
    });

    test('faculty_head role helpers', () {
      const user = UserModel(
        id: 3, email: 'head@ub.cm', fullName: 'FET Head',
        role: 'faculty_head', isActive: true, facultyId: 1,
      );
      expect(user.isFacultyHead, isTrue);
      expect(user.isTimetableOfficer, isTrue);
      expect(user.isStudent, isFalse);
    });

    test('student role helpers', () {
      const user = UserModel(
        id: 2, email: 'stu@ub.cm', fullName: 'Student',
        role: 'student', isActive: true,
      );
      expect(user.isSuperAdmin, isFalse);
      expect(user.canManageTimetable, isFalse);
      expect(user.isStudent, isTrue);
    });

    test('parses facultyId from JSON', () {
      final json = {
        'id': 4, 'email': 'fh@ub.cm', 'full_name': 'FH',
        'role': 'faculty_head', 'is_active': true,
        'university_id': 1, 'department_id': null, 'faculty_id': 2,
      };
      final user = UserModel.fromJson(json);
      expect(user.facultyId, 2);
    });
  });

  group('TimetableEntry', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 10, 'run_id': 1, 'course_id': 2, 'lecturer_id': 3,
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

  group('Building', () {
    test('parses from JSON', () {
      final json = {
        'id': 1, 'name': 'FET Main Block',
        'description': null, 'university_id': 1,
      };
      final b = Building.fromJson(json);
      expect(b.name, 'FET Main Block');
      expect(b.description, isNull);
    });
  });

  group('Room', () {
    test('parses buildingId not universityId', () {
      final json = {
        'id': 1, 'name': 'Amphi 750', 'capacity': 750,
        'room_type': 'lecture_hall', 'is_active': true, 'building_id': 1,
      };
      final room = Room.fromJson(json);
      expect(room.buildingId, 1);
      expect(room.capacity, 750);
    });
  });
}
