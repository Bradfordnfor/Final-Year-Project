class Course {
  final int id;
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
