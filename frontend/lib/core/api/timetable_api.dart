import '../models/timetable.dart';
import 'api_client.dart';

class TimetableApi {
  final ApiClient _client;
  TimetableApi(this._client);

  Future<List<TimetableModel>> getTimetables() async {
    final response = await _client.get('/timetables/');
    return (response.data as List)
        .map((e) => TimetableModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TimetableModel> getTimetable(int id) async {
    final response = await _client.get('/timetables/$id');
    return TimetableModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TimetableModel> createTimetable(int semesterId, int departmentId) async {
    final response = await _client.post('/timetables/', data: {
      'semester_id': semesterId,
      'department_id': departmentId,
    });
    return TimetableModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<TimetableEntry>> getEntries(int timetableId) async {
    final response = await _client.get('/timetables/$timetableId/entries');
    return (response.data as List)
        .map((e) => TimetableEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TimetableConflict>> getConflicts(int timetableId) async {
    final response = await _client.get('/timetables/$timetableId/conflicts');
    return (response.data as List)
        .map((e) => TimetableConflict.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> triggerGeneration(int timetableId) async {
    final response = await _client.post('/timetables/$timetableId/generate');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getJobStatus(int timetableId) async {
    final response = await _client.get('/timetables/$timetableId/job-status');
    return response.data as Map<String, dynamic>;
  }

  Future<TimetableModel> advanceStatus(int timetableId) async {
    final response = await _client.post('/timetables/$timetableId/advance-status');
    return TimetableModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TimetableModel> publish(int timetableId) async {
    final response = await _client.post('/timetables/$timetableId/publish');
    return TimetableModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TimetableConflict> resolveConflict(
      int timetableId, int conflictId, String resolution) async {
    final response = await _client.post(
      '/timetables/$timetableId/conflicts/$conflictId/resolve',
      data: {'resolution': resolution},
    );
    return TimetableConflict.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getAnalytics(int timetableId) async {
    final response = await _client.get('/timetables/$timetableId/analytics');
    return response.data as Map<String, dynamic>;
  }

  Future<List<AppNotification>> getMyNotifications() async {
    final response = await _client.get('/timetables/notifications/mine');
    return (response.data as List)
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markNotificationRead(int notificationId) async {
    await _client.post('/timetables/notifications/$notificationId/read');
  }

  Future<List<int>> downloadExport(int timetableId, String format) async {
    final response = await _client.downloadFile(
      '/export/timetables/$timetableId/$format',
    );
    return List<int>.from(response.data as List);
  }
}
