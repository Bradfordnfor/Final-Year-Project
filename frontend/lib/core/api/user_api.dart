import '../models/user.dart';
import 'api_client.dart';

class UserApi {
  final ApiClient _client;
  UserApi(this._client);

  Future<List<UserModel>> getUsers() async {
    final response = await _client.get('/users/');
    return (response.data as List)
        .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<UserModel> createUser(Map<String, dynamic> data) async {
    final response = await _client.post('/users/', data: data);
    return UserModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Returns lecturers with their Lecturer.id (not user id) and full_name.
  /// Use this to build lecturer name maps for timetable entries.
  Future<List<Map<String, dynamic>>> getLecturers() async {
    final response = await _client.get('/lecturers/');
    return (response.data as List).cast<Map<String, dynamic>>();
  }

  /// The current lecturer's own profile (provisions one on first use).
  /// Returns the Lecturer record including its `id` — the value to use as
  /// `lecturer_id` when reading or writing availability.
  Future<Map<String, dynamic>> getMyLecturerProfile() async {
    final response = await _client.get('/lecturers/me');
    return response.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getLecturerAvailability(int lecturerId) async {
    final response = await _client.get('/lecturers/$lecturerId/availability');
    return List<Map<String, dynamic>>.from(response.data as List);
  }

  Future<void> addAvailability(int lecturerId, int timeSlotId) async {
    await _client.post('/lecturers/availability/', data: {
      'lecturer_id': lecturerId,
      'time_slot_id': timeSlotId,
    });
  }

  Future<void> deleteAvailability(int availabilityId) async {
    await _client.delete('/lecturers/availability/$availabilityId');
  }
}
