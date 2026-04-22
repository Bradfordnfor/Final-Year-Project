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

  Future<Course> updateCourse(int id, Map<String, dynamic> data) async {
    final response = await _client.put('/courses/$id', data: data);
    return Course.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteCourse(int id) async {
    await _client.delete('/courses/$id');
  }
}
