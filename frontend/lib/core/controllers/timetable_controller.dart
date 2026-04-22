import 'dart:async';

import 'package:get/get.dart';

import '../api/api_client.dart';
import '../api/timetable_api.dart';
import '../models/timetable.dart';
import 'auth_controller.dart';

class TimetableController extends GetxController {
  static TimetableController get to => Get.find();

  final RxList<TimetableModel> timetables = <TimetableModel>[].obs;
  final Rx<TimetableModel?> selected = Rx<TimetableModel?>(null);
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

  Future<void> fetchTimetables() async {
    isLoading.value = true;
    try {
      timetables.value = await _api.getTimetables();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> selectTimetable(int id) async {
    isLoading.value = true;
    try {
      selected.value = await _api.getTimetable(id);
      await Future.wait([loadEntries(id), loadConflicts(id)]);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadEntries(int timetableId) async {
    entries.value = await _api.getEntries(timetableId);
  }

  Future<void> loadConflicts(int timetableId) async {
    conflicts.value = await _api.getConflicts(timetableId);
  }

  Future<void> create(int semesterId, int departmentId) async {
    isLoading.value = true;
    try {
      final t = await _api.createTimetable(semesterId, departmentId);
      timetables.add(t);
      selected.value = t;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> generate(int timetableId) async {
    isGenerating.value = true;
    jobStatus.value = 'pending';
    await _api.triggerGeneration(timetableId);
    _startPolling(timetableId);
  }

  void _startPolling(int timetableId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final status = await _api.getJobStatus(timetableId);
      jobStatus.value = status['status'] as String? ?? '';
      if (jobStatus.value == 'completed' || jobStatus.value == 'failed') {
        _pollTimer?.cancel();
        isGenerating.value = false;
        if (jobStatus.value == 'completed') {
          await selectTimetable(timetableId);
        }
      }
    });
  }

  Future<void> advanceStatus(int timetableId) async {
    final updated = await _api.advanceStatus(timetableId);
    _replaceTimetable(updated);
  }

  Future<void> publish(int timetableId) async {
    final updated = await _api.publish(timetableId);
    _replaceTimetable(updated);
  }

  Future<void> resolveConflict(
      int timetableId, int conflictId, String resolution) async {
    final updated =
        await _api.resolveConflict(timetableId, conflictId, resolution);
    final idx = conflicts.indexWhere((c) => c.id == conflictId);
    if (idx != -1) conflicts[idx] = updated;
  }

  void _replaceTimetable(TimetableModel updated) {
    final idx = timetables.indexWhere((t) => t.id == updated.id);
    if (idx != -1) timetables[idx] = updated;
    if (selected.value?.id == updated.id) selected.value = updated;
  }
}
