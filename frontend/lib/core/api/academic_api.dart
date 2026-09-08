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

  Future<Semester> createSemester(Map<String, dynamic> data) async {
    final response = await _client.post('/semesters/', data: data);
    return Semester.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteSemester(int id) async {
    await _client.delete('/semesters/$id');
  }

  Future<List<TimeSlot>> getTimeSlots(int semesterId) async {
    final response = await _client.get('/semesters/$semesterId/timeslots');
    return (response.data as List)
        .map((e) => TimeSlot.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TimeSlot> createTimeSlot(Map<String, dynamic> data) async {
    final response = await _client.post('/semesters/timeslots/', data: data);
    return TimeSlot.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteTimeSlot(int id) async {
    await _client.delete('/semesters/timeslots/$id');
  }

  Future<List<Level>> getLevels() async {
    final response = await _client.get('/levels/');
    return (response.data as List)
        .map((e) => Level.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<StudyClass>> getClasses(int departmentId) async {
    final response = await _client.get('/departments/$departmentId/classes');
    return (response.data as List)
        .map((e) => StudyClass.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateClassPopulation(int classId, int population) async {
    await _client.put('/classes/$classId', data: {'population': population});
  }

  /// Create a class under a level. Pass [track] to make it a specialization
  /// track (e.g. "Software"); leave null for an ordinary single class.
  Future<StudyClass> createClass({
    required int levelId,
    required String name,
    required int population,
    String? track,
  }) async {
    final response = await _client.post('/classes/', data: {
      'name': name,
      'population': population,
      'level_id': levelId,
      if (track != null && track.isNotEmpty) 'track': track,
    });
    return StudyClass.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteClass(int classId) async {
    await _client.delete('/classes/$classId');
  }

  Future<List<Map<String, dynamic>>> getGroups(int classId) async {
    final response = await _client.get('/groups/');
    return (response.data as List)
        .cast<Map<String, dynamic>>()
        .where((g) => g['class_id'] == classId)
        .toList();
  }

  Future<Map<String, dynamic>> createGroup(String name, int classId) async {
    final response = await _client.post('/groups/', data: {
      'name': name,
      'class_id': classId,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteGroup(int groupId) async {
    await _client.delete('/groups/$groupId');
  }
}
