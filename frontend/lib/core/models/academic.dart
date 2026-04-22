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
