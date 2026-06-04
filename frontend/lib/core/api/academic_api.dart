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
}
