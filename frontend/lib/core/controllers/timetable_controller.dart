import 'dart:async';

import 'package:get/get.dart';

import '../api/api_client.dart';
import '../api/timetable_api.dart';
import '../models/timetable.dart';
import 'auth_controller.dart';

class TimetableController extends GetxController {
  static TimetableController get to => Get.find();

  final RxList<TimetableRun> runs = <TimetableRun>[].obs;
  final Rx<TimetableRun?> selected = Rx<TimetableRun?>(null);
  final RxList<TimetableEntry> entries = <TimetableEntry>[].obs;
  final RxList<TimetableConflict> conflicts = <TimetableConflict>[].obs;

  final RxBool isLoading = false.obs;
  final RxBool isGenerating = false.obs;
  final RxString jobStatus = ''.obs;

  Timer? _pollTimer;

  TimetableApi get _api =>
      TimetableApi(ApiClient(token: AuthController.to.token));

  @override
  void onClose() {
    _pollTimer?.cancel();
    super.onClose();
  }

  Future<void> fetchRuns() async {
    isLoading.value = true;
    try {
      final user = AuthController.to.user.value;
      runs.value = (user?.isStudent ?? false)
          ? await _api.getPublishedRuns()
          : await _api.getRuns();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> selectRun(int id) async {
    isLoading.value = true;
    try {
      selected.value = await _api.getRun(id);
      await Future.wait([loadEntries(id), loadConflicts(id)]);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadEntries(int runId) async {
    entries.value = await _api.getEntries(runId);
  }

  Future<void> loadConflicts(int runId) async {
    conflicts.value = await _api.getConflicts(runId);
  }

  Future<void> createRun({
    required String name,
    required int semesterId,
    required List<int> facultyIds,
    required List<int> buildingIds,
  }) async {
    isLoading.value = true;
    try {
      final run = await _api.createRun(
        name: name,
        semesterId: semesterId,
        facultyIds: facultyIds,
        buildingIds: buildingIds,
      );
      runs.add(run);
      selected.value = run;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> deleteRun(int id) async {
    await _api.deleteRun(id);
    runs.removeWhere((r) => r.id == id);
    if (selected.value?.id == id) {
      selected.value = null;
      entries.clear();
      conflicts.clear();
    }
  }

  Future<void> generate(int runId) async {
    isGenerating.value = true;
    jobStatus.value = 'pending';
    await _api.triggerGeneration(runId);
    _startPolling(runId);
  }

  void _startPolling(int runId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final status = await _api.getJobStatus(runId);
      jobStatus.value = status['status'] as String? ?? '';
      if (jobStatus.value == 'completed' || jobStatus.value == 'failed') {
        _pollTimer?.cancel();
        isGenerating.value = false;
        if (jobStatus.value == 'completed') {
          await selectRun(runId);
        }
      }
    });
  }

  Future<void> advanceStatus(int runId) async {
    try {
      final updated = await _api.advanceStatus(runId);
      _replaceRun(updated);
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> publish(int runId) async {
    try {
      final updated = await _api.publish(runId);
      _replaceRun(updated);
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> resolveConflict(
      int runId, int conflictId, String resolution) async {
    final updated = await _api.resolveConflict(runId, conflictId, resolution);
    final idx = conflicts.indexWhere((c) => c.id == conflictId);
    if (idx != -1) conflicts[idx] = updated;
  }

  void _replaceRun(TimetableRun updated) {
    final idx = runs.indexWhere((r) => r.id == updated.id);
    if (idx != -1) runs[idx] = updated;
    if (selected.value?.id == updated.id) selected.value = updated;
  }
}
