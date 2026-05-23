import '../models/university.dart';
import '../models/room.dart';
import 'api_client.dart';

class UniversityApi {
  final ApiClient _client;
  UniversityApi(this._client);

  Future<List<University>> getUniversities() async {
    final response = await _client.get('/universities/');
    return (response.data as List)
        .map((e) => University.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<University> createUniversity(Map<String, dynamic> data) async {
    final response = await _client.post('/universities/', data: data);
    return University.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteUniversity(int id) async {
    await _client.delete('/universities/$id');
  }

  Future<List<Faculty>> getFaculties() async {
    final response = await _client.get('/faculties/');
    return (response.data as List)
        .map((e) => Faculty.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Department>> getDepartments() async {
    final response = await _client.get('/departments/');
    return (response.data as List)
        .map((e) => Department.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Building>> getBuildings() async {
    final response = await _client.get('/buildings/');
    return (response.data as List)
        .map((e) => Building.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Building> createBuilding(Map<String, dynamic> data) async {
    final response = await _client.post('/buildings/', data: data);
    return Building.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteBuilding(int id) async {
    await _client.delete('/buildings/$id');
  }

  Future<List<Room>> getRooms() async {
    final response = await _client.get('/rooms/');
    return (response.data as List)
        .map((e) => Room.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Room> createRoom(Map<String, dynamic> data) async {
    final response = await _client.post('/rooms/', data: data);
    return Room.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteRoom(int id) async {
    await _client.delete('/rooms/$id');
  }

  Future<Map<String, dynamic>> createUniversityWithAdmin(
      Map<String, dynamic> data) async {
    final response = await _client.post('/universities/', data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getUniversityStructure(int id) async {
    final response = await _client.get('/universities/$id/structure');
    return response.data as Map<String, dynamic>;
  }
}
