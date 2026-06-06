import '../models/timetable.dart';
import 'api_client.dart';

class TimetableApi {
  final ApiClient _client;
  TimetableApi(this._client);

  Future<List<TimetableRun>> getRuns() async {
    final response = await _client.get('/runs/');
    return (response.data as List)
        .map((e) => TimetableRun.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TimetableRun>> getPublishedRuns() async {
    final response = await _client.get('/runs/public');
    return (response.data as List)
        .map((e) => TimetableRun.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TimetableRun> getRun(int id) async {
    final response = await _client.get('/runs/$id');
    return TimetableRun.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TimetableRun> createRun({
    required String name,
    required int semesterId,
    required List<int> facultyIds,
    required List<int> buildingIds,
  }) async {
    final response = await _client.post('/runs/', data: {
      'name': name,
      'semester_id': semesterId,
      'faculty_ids': facultyIds,
      'building_ids': buildingIds,
    });
    return TimetableRun.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteRun(int id) async {
    await _client.delete('/runs/$id');
  }

  Future<List<TimetableEntry>> getEntries(int runId) async {
    final response = await _client.get('/runs/$runId/entries');
    return (response.data as List)
        .map((e) => TimetableEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TimetableConflict>> getConflicts(int runId) async {
    final response = await _client.get('/runs/$runId/conflicts');
    return (response.data as List)
        .map((e) => TimetableConflict.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> triggerGeneration(int runId) async {
    final response = await _client.post('/runs/$runId/generate');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getJobStatus(int runId) async {
    final response = await _client.get('/runs/$runId/job-status');
    return response.data as Map<String, dynamic>;
  }

  Future<TimetableRun> advanceStatus(int runId) async {
    final response = await _client.post('/runs/$runId/advance-status');
    return TimetableRun.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TimetableRun> publish(int runId) async {
    final response = await _client.post('/runs/$runId/publish');
    return TimetableRun.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TimetableConflict> resolveConflict(
      int runId, int conflictId, String resolution) async {
    final response = await _client.post(
      '/runs/$runId/conflicts/$conflictId/resolve',
      data: {'resolution': resolution},
    );
    return TimetableConflict.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getAnalytics(int runId) async {
    final response = await _client.get('/runs/$runId/analytics');
    return response.data as Map<String, dynamic>;
  }

  Future<List<AppNotification>> getMyNotifications() async {
    final response = await _client.get('/notifications/mine');
    return (response.data as List)
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markNotificationRead(int notificationId) async {
    await _client.post('/notifications/$notificationId/read');
  }

  Future<List<int>> downloadExport(int runId, String format) async {
    final response = await _client.downloadFile('/export/runs/$runId/$format');
    return List<int>.from(response.data as List);
  }

  Future<TimetableRun> submitForReview(int runId) async {
    final response = await _client.post('/runs/$runId/submit-for-review');
    return TimetableRun.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<FacultyApproval>> getApprovals(int runId) async {
    final response = await _client.get('/runs/$runId/approvals');
    return (response.data as List)
        .map((e) => FacultyApproval.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<FacultyApproval> approveFaculty(int runId, int approvalId) async {
    final response = await _client.post('/runs/$runId/approvals/$approvalId/approve');
    return FacultyApproval.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> rejectFaculty(int runId, int approvalId, String comment) async {
    await _client.post(
      '/runs/$runId/approvals/$approvalId/reject',
      data: {'comment': comment},
    );
  }

  Future<void> moveEntry(int runId, int entryId, int newSlotId, int newRoomId) async {
    await _client.put('/runs/$runId/entries/move', data: {
      'entry_id': entryId,
      'new_time_slot_id': newSlotId,
      'new_room_id': newRoomId,
    });
  }
}
