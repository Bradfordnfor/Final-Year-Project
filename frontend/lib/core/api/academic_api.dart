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
