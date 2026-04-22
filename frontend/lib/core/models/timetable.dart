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
