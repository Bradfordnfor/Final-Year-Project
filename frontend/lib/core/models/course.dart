class Course {
  final int id;
  final String code;
  final String name;
  final String roomTypeRequired;
  final int levelId;
  final int departmentId;
  final int? lecturerId;
  final int weeklyHours;

  const Course({
    required this.id, required this.code, required this.name,
    required this.roomTypeRequired, required this.levelId,
    required this.departmentId, this.lecturerId,
    this.weeklyHours = 2,
  });

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        id: json['id'] as int,
        code: json['code'] as String,
        name: json['name'] as String,
        roomTypeRequired: json['room_type_required'] as String,
        levelId: json['level_id'] as int,
        departmentId: json['department_id'] as int,
        lecturerId: json['lecturer_id'] as int?,
        weeklyHours: (json['weekly_hours'] as int?) ?? 2,
      );
}
