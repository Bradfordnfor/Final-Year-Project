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

class Building {
  final int id;
  final String name;
  final String? description;
  final int universityId;

  const Building({
    required this.id, required this.name,
    this.description, required this.universityId,
  });

  factory Building.fromJson(Map<String, dynamic> json) => Building(
        id: json['id'] as int,
        name: json['name'] as String,
        description: json['description'] as String?,
        universityId: json['university_id'] as int,
      );
}
