import 'dart:html' as html;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/api/academic_api.dart';
import '../../core/api/api_client.dart';
import '../../core/api/course_api.dart';
import '../../core/api/timetable_api.dart';
import '../../core/api/university_api.dart';
import '../../core/api/user_api.dart';
import '../../core/controllers/auth_controller.dart';
import '../../core/controllers/timetable_controller.dart';
import '../../core/models/academic.dart';
import '../../core/models/course.dart';
import '../../core/models/room.dart';
import '../../core/models/timetable.dart';
import '../../core/models/university.dart';
import '../../core/utils/week_days.dart';
import '../../core/widgets/class_filter_bar.dart';

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  List<Semester> _semesters = [];
  List<Faculty> _faculties = [];
  List<Building> _buildings = [];
  List<TimeSlot> _timeSlots = [];
  Map<int, String> _courseNames = {};
  Map<int, String> _roomNames = {};
  Map<int, int> _roomCapacities = {};
  Map<int, String> _classNames = {};
  Map<int, int> _classPopulations = {};
  List<Room> _allRooms = [];
  Map<int, String> _lecturerNames = {};
  bool _loadingMeta = true;
  List<int>? _filteredClassIds;
  List<Faculty>? _runFaculties;

  @override
  void initState() {
    super.initState();
    TimetableController.to.fetchRuns();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    try {
      final token = AuthController.to.token;
      final client = ApiClient(token: token);
      final results = await Future.wait([
        AcademicApi(client).getSemesters(),
        UniversityApi(client).getFaculties(),
        UniversityApi(client).getBuildings(),
        CourseApi(client).getCourses(),
        UniversityApi(client).getRooms(),
      ]);
      final semesters = results[0] as List<Semester>;
      final faculties = results[1] as List<Faculty>;
      final buildings = results[2] as List<Building>;
      final courses = results[3] as List<Course>;
      final rooms = results[4] as List<Room>;

      // Load class names + populations (one call, works for the officer too).
      final classNames = <int, String>{};
      final classPops = <int, int>{};
      try {
        final resp = await client.get('/faculty-setup/classes');
        for (final c in (resp.data as List)) {
          final m = c as Map<String, dynamic>;
          final id = m['id'] as int;
          classNames[id] = m['name'] as String? ?? 'Class #$id';
          classPops[id] = (m['population'] as int?) ?? 0;
        }
      } catch (_) {}

      // Load lecturer names keyed by Lecturer.id (not user id)
      final lecturerList = await UserApi(client).getLecturers();
      final lecturerNames = <int, String>{
        for (final l in lecturerList)
          (l['id'] as int): (l['full_name'] as String? ?? '')
      };

      if (mounted) {
        setState(() {
          _semesters = semesters;
          _faculties = faculties;
          _buildings = buildings;
          _courseNames = {for (final c in courses) c.id: '${c.code} — ${c.name}'};
          _roomNames = {for (final r in rooms) r.id: r.name};
          _allRooms = rooms;
          _roomCapacities = {for (final r in rooms) r.id: r.capacity};
          _classNames = classNames;
          _classPopulations = classPops;
          _lecturerNames = lecturerNames;
          _loadingMeta = false;
          final run = TimetableController.to.selected.value;
          if (run != null) {
            _runFaculties = _faculties.where((f) => run.facultyIds.contains(f.id)).toList();
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  Future<void> _loadTimeSlots(int semesterId) async {
    try {
      final ts = await AcademicApi(ApiClient(token: AuthController.to.token))
          .getTimeSlots(semesterId);
      if (mounted) setState(() => _timeSlots = ts);
    } catch (_) {}
  }

  Future<void> _showMoveDialog(TimetableEntry entry, TimetableRun run) async {
    // Move tab state.
    int? newSlotId = entry.timeSlotId;
    int? newRoomId = entry.roomId;
    // "Take out" (split) tab state.
    int? splitClassId = entry.classIds.isNotEmpty ? entry.classIds.first : null;
    int? splitSlotId = entry.timeSlotId;
    int? splitRoomId;
    // "Put in" (merge) tab state.
    int? mergeClassId = entry.classIds.isNotEmpty ? entry.classIds.first : null;
    int? mergeTargetEntryId;
    String? errorMsg;

    final sameCourseEntries = TimetableController.to.entries
        .where((e) => e.courseId == entry.courseId && e.id != entry.id)
        .toList();
    final canSplit = entry.classIds.length > 1;
    final canMerge = sameCourseEntries.isNotEmpty && entry.classIds.isNotEmpty;

    final courseName = _courseNames[entry.courseId] ?? 'Course #${entry.courseId}';
    final currentSlot = _timeSlots.firstWhere(
      (s) => s.id == entry.timeSlotId,
      orElse: () => TimeSlot(id: 0, dayOfWeek: '', startTime: '', endTime: '', semesterId: 0),
    );
    final currentRoomLabel = entry.roomId == null
        ? 'Outdoor / off-site'
        : () {
            final room = _roomNames[entry.roomId] ?? 'Room #${entry.roomId}';
            final cap = _roomCapacities[entry.roomId];
            return cap != null ? '$room ($cap seats)' : room;
          }();

    final classNamesList = entry.classIds.map((id) {
      final name = _classNames[id] ?? 'Class #$id';
      final pop = _classPopulations[id];
      return (pop != null && pop > 0) ? '$name ($pop)' : name;
    }).join(', ');
    final totalPopulation = entry.classIds
        .fold<int>(0, (sum, id) => sum + (_classPopulations[id] ?? 0));
    final classLabel = entry.classIds.length > 1 && totalPopulation > 0
        ? '$classNamesList  ·  $totalPopulation total'
        : classNamesList;

    // Dropdown items for the classes that sit in this session.
    List<DropdownMenuItem<int>> classItems() => entry.classIds.map((id) {
          final name = _classNames[id] ?? 'Class #$id';
          final pop = _classPopulations[id];
          final lbl = (pop != null && pop > 0) ? '$name ($pop)' : name;
          return DropdownMenuItem(
              value: id, child: Text(lbl, overflow: TextOverflow.ellipsis));
        }).toList();

    final slotItems = _timeSlots
        .map((s) => DropdownMenuItem(
              value: s.id,
              child: Text('${s.dayOfWeek} ${s.label}',
                  overflow: TextOverflow.ellipsis),
            ))
        .toList();
    final roomItems = _allRooms
        .map((r) => DropdownMenuItem(
              value: r.id,
              child: Text('${r.name} (${r.capacity} seats)',
                  overflow: TextOverflow.ellipsis),
            ))
        .toList();

    // A readable label for another session of the same course.
    String entryLabel(TimetableEntry e) {
      final slot = _timeSlots.firstWhere(
        (s) => s.id == e.timeSlotId,
        orElse: () => TimeSlot(id: 0, dayOfWeek: '?', startTime: '', endTime: '', semesterId: 0),
      );
      final roomTxt = e.roomId == null
          ? 'off-site'
          : (_roomNames[e.roomId] ?? 'Room #${e.roomId}');
      final pop = e.classIds
          .fold<int>(0, (sum, id) => sum + (_classPopulations[id] ?? 0));
      final cap = e.roomId == null ? null : _roomCapacities[e.roomId];
      final capTxt = cap != null ? '$pop/$cap' : '$pop';
      return '${slot.dayOfWeek} ${slot.label} · $roomTxt · $capTxt';
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          // Runs an API call and, on success, closes the dialog and refreshes
          // the grid (so the over-capacity / merged flags update).
          Future<void> runAction(Future<void> Function(TimetableApi api) op) async {
            try {
              final api = TimetableApi(ApiClient(token: AuthController.to.token));
              await op(api);
              if (ctx.mounted) Navigator.pop(ctx);
              TimetableController.to.fetchRuns();
              await TimetableController.to.loadEntries(run.id);
            } on DioException catch (e) {
              final detail = (e.response?.data as Map?)?['detail'] as String? ??
                  e.message ?? 'Unknown error';
              setS(() => errorMsg = detail);
            } catch (e) {
              setS(() => errorMsg = e.toString());
            }
          }

          return DefaultTabController(
            length: 3,
            child: AlertDialog(
              title: Text(courseName),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Shared header ──
                    Row(children: [
                      Expanded(
                        child: _InfoCard(
                          label: 'LECTURER',
                          value: _lecturerNames[entry.lecturerId] ??
                              'Lecturer #${entry.lecturerId}',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _InfoCard(label: 'CLASS', value: classLabel),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: _InfoCard(
                          label: 'CURRENT SLOT',
                          value: '${currentSlot.dayOfWeek} ${currentSlot.label}',
                          highlight: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _InfoCard(
                          label: 'CURRENT ROOM',
                          value: currentRoomLabel,
                          highlight: true,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    const TabBar(
                      labelStyle:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      tabs: [
                        Tab(text: 'Move'),
                        Tab(text: 'Take out'),
                        Tab(text: 'Put in'),
                      ],
                    ),
                    SizedBox(
                      height: 240,
                      child: TabBarView(
                        children: [
                          // ── Tab 1: Move the whole session ──
                          SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 12),
                                DropdownButtonFormField<int>(
                                  value: newSlotId,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Move to slot',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: slotItems,
                                  onChanged: (v) => setS(() {
                                    newSlotId = v;
                                    errorMsg = null;
                                  }),
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<int>(
                                  value: newRoomId,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Move to room',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: roomItems,
                                  onChanged: (v) => setS(() {
                                    newRoomId = v;
                                    errorMsg = null;
                                  }),
                                ),
                                const SizedBox(height: 16),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton(
                                    onPressed:
                                        (newSlotId != null && newRoomId != null)
                                            ? () => runAction((api) => api.moveEntry(
                                                run.id, entry.id, newSlotId!, newRoomId!))
                                            : null,
                                    child: const Text('Move'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // ── Tab 2: Take a class out (split) ──
                          canSplit
                              ? SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Pull one class out into its own session. '
                                        'If the chosen room already runs this same '
                                        'course with the same lecturer in that '
                                        'period, the class joins that session.',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<int>(
                                        value: splitClassId,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Class to take out',
                                          border: OutlineInputBorder(),
                                        ),
                                        items: classItems(),
                                        onChanged: (v) => setS(() {
                                          splitClassId = v;
                                          errorMsg = null;
                                        }),
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<int>(
                                        value: splitSlotId,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'New slot',
                                          border: OutlineInputBorder(),
                                        ),
                                        items: slotItems,
                                        onChanged: (v) => setS(() {
                                          splitSlotId = v;
                                          errorMsg = null;
                                        }),
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<int>(
                                        value: splitRoomId,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'New room',
                                          border: OutlineInputBorder(),
                                        ),
                                        items: roomItems,
                                        onChanged: (v) => setS(() {
                                          splitRoomId = v;
                                          errorMsg = null;
                                        }),
                                      ),
                                      const SizedBox(height: 16),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: FilledButton(
                                          onPressed: (splitClassId != null &&
                                                  splitSlotId != null &&
                                                  splitRoomId != null)
                                              ? () => runAction((api) =>
                                                  api.splitClass(
                                                      run.id,
                                                      entry.id,
                                                      splitClassId!,
                                                      splitSlotId!,
                                                      splitRoomId!))
                                              : null,
                                          child: const Text('Take out'),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                    'Only a merged session (more than one class) '
                                    'can have a class taken out.',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                          // ── Tab 3: Put a class into another session (merge) ──
                          canMerge
                              ? SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Move a class into another session of '
                                        'the same course.',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<int>(
                                        value: mergeClassId,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Class to move',
                                          border: OutlineInputBorder(),
                                        ),
                                        items: classItems(),
                                        onChanged: (v) => setS(() {
                                          mergeClassId = v;
                                          errorMsg = null;
                                        }),
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<int>(
                                        value: mergeTargetEntryId,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Into session',
                                          border: OutlineInputBorder(),
                                        ),
                                        items: sameCourseEntries
                                            .map((e) => DropdownMenuItem(
                                                  value: e.id,
                                                  child: Text(entryLabel(e),
                                                      overflow: TextOverflow
                                                          .ellipsis),
                                                ))
                                            .toList(),
                                        onChanged: (v) => setS(() {
                                          mergeTargetEntryId = v;
                                          errorMsg = null;
                                        }),
                                      ),
                                      const SizedBox(height: 16),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: FilledButton(
                                          onPressed: (mergeClassId != null &&
                                                  mergeTargetEntryId != null)
                                              ? () => runAction((api) =>
                                                  api.mergeClass(
                                                      run.id,
                                                      entry.id,
                                                      mergeClassId!,
                                                      mergeTargetEntryId!))
                                              : null,
                                          child: const Text('Put in'),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                    'There is no other session of this course '
                                    'to put a class into.',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                        ],
                      ),
                    ),
                    if (errorMsg != null) ...[
                      const SizedBox(height: 8),
                      Text(errorMsg!,
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error,
                            fontSize: 12,
                          )),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Delete a run. A published run is live on the public page, so it takes a
  /// typed-name confirmation; any other status takes a plain yes/no confirm.
  Future<void> _confirmAndDeleteRun(TimetableRun run) async {
    final bool confirmed;
    if (run.isPublished) {
      confirmed = await _typedNameDeleteConfirm(run);
    } else {
      confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete run?'),
              content: Text(
                'Delete "${run.name}"? This permanently removes the run and '
                'any timetable generated for it. This cannot be undone.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(ctx).colorScheme.error),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (!confirmed) return;
    try {
      await TimetableController.to.deleteRun(run.id);
      Get.snackbar('Run deleted', '"${run.name}" was removed',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 2));
    } catch (e) {
      Get.snackbar('Delete failed', e.toString(),
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// Make the officer type the run's name before deleting a published run.
  Future<bool> _typedNameDeleteConfirm(TimetableRun run) async {
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final matches = typed.text.trim() == run.name.trim();
          return AlertDialog(
            title: const Text('Delete published run?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This run is published and live on the public timetable. '
                  'Deleting it removes it for everyone who has the link. This '
                  'cannot be undone.',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
                ),
                const SizedBox(height: 12),
                Text('Type the run name to confirm:',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.outline)),
                const SizedBox(height: 6),
                TextField(
                  controller: typed,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: run.name,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setS(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error),
                onPressed: matches ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Delete'),
              ),
            ],
          );
        },
      ),
    );
    return ok ?? false;
  }

  void _showCreateDialog() {
    if (_loadingMeta) return;
    if (_semesters.isEmpty) {
      Get.snackbar('No Data', 'Add semesters first.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final nameCtrl = TextEditingController();
    Semester? semester = _semesters.isNotEmpty ? _semesters.first : null;
    final Set<int> selectedFaculties = {};
    final Set<int> selectedBuildings = {};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.primaryContainer,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month,
                          color: Theme.of(ctx).colorScheme.onPrimaryContainer),
                      const SizedBox(width: 12),
                      Text('New Timetable Run',
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).colorScheme.onPrimaryContainer,
                          )),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Run name
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Run name',
                            hintText: 'e.g. FET — Semester 1 2025/26',
                            prefixIcon: Icon(Icons.label_outline),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Semester
                        DropdownButtonFormField<Semester>(
                          value: semester,
                          decoration: const InputDecoration(
                            labelText: 'Semester',
                            prefixIcon: Icon(Icons.date_range_outlined),
                          ),
                          items: _semesters.map((s) =>
                              DropdownMenuItem(value: s, child: Text(s.name))).toList(),
                          onChanged: (v) => setS(() => semester = v),
                        ),
                        const SizedBox(height: 20),

                        // Faculties
                        Text('Faculties', style: Theme.of(ctx).textTheme.labelLarge),
                        const SizedBox(height: 8),
                        if (_faculties.isEmpty)
                          const Text('No faculties found')
                        else
                          Wrap(
                            spacing: 8, runSpacing: 8,
                            children: _faculties.map((f) {
                              final sel = selectedFaculties.contains(f.id);
                              return FilterChip(
                                label: Text('${f.code} — ${f.name}'),
                                selected: sel,
                                onSelected: (v) => setS(() =>
                                    v ? selectedFaculties.add(f.id)
                                      : selectedFaculties.remove(f.id)),
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 20),

                        // Buildings
                        Text('Buildings', style: Theme.of(ctx).textTheme.labelLarge),
                        const SizedBox(height: 8),
                        if (_buildings.isEmpty)
                          const Text('No buildings found')
                        else
                          Wrap(
                            spacing: 8, runSpacing: 8,
                            children: _buildings.map((b) {
                              final sel = selectedBuildings.contains(b.id);
                              return FilterChip(
                                label: Text(b.name),
                                selected: sel,
                                onSelected: (v) => setS(() =>
                                    v ? selectedBuildings.add(b.id)
                                      : selectedBuildings.remove(b.id)),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            if (nameCtrl.text.trim().isEmpty) {
                              Get.snackbar('Required', 'Enter a run name.',
                                  snackPosition: SnackPosition.BOTTOM);
                              return;
                            }
                            if (semester == null) return;
                            if (selectedFaculties.isEmpty) {
                              Get.snackbar('Required', 'Select at least one faculty.',
                                  snackPosition: SnackPosition.BOTTOM);
                              return;
                            }
                            if (selectedBuildings.isEmpty) {
                              Get.snackbar('Required', 'Select at least one building.',
                                  snackPosition: SnackPosition.BOTTOM);
                              return;
                            }
                            Navigator.pop(ctx);
                            await TimetableController.to.createRun(
                              name: nameCtrl.text.trim(),
                              semesterId: semester!.id,
                              facultyIds: selectedFaculties.toList(),
                              buildingIds: selectedBuildings.toList(),
                            );
                          },
                          child: const Text('Create'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthController.to.user.value;
    final canManage = user?.canManageTimetable ?? false;
    // advance: timetable_officer + faculty_head + admins (matches backend require_timetable_officer)
    final canAdvance = (user?.canManageTimetable ?? false) || (user?.canSetupFaculty ?? false);
    // publish: faculty_head + admins (matches backend require_faculty_head)
    final canPublish = user?.canSetupFaculty ?? false;
    final isTimetableOfficer = user?.isTimetableOfficer ?? false;
    final isFacultyHead = user?.isFacultyHead ?? false;
    final currentUserId = user?.id;
    final cs = Theme.of(context).colorScheme;

    return Obx(() {
      final ctrl = TimetableController.to;
      final runs = ctrl.runs;
      final selected = ctrl.selected.value;

      return Column(
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Timetable Runs',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold)),
                    Text('${runs.length} run${runs.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.outline)),
                  ],
                ),
                const Spacer(),
                if (canManage)
                  FilledButton.icon(
                    onPressed: _loadingMeta ? null : _showCreateDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Run'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left panel: run list
                SizedBox(
                  width: 240,
                  child: ctrl.isLoading.value
                      ? const Center(child: CircularProgressIndicator())
                      : runs.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.calendar_today_outlined,
                                      size: 48, color: cs.outline),
                                  const SizedBox(height: 12),
                                  Text('No runs yet',
                                      style: TextStyle(color: cs.outline)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: runs.length,
                              itemBuilder: (_, i) {
                                final r = runs[i];
                                final isActive = selected?.id == r.id;
                                return _RunCard(
                                  run: r,
                                  isSelected: isActive,
                                  onDelete:
                                      canManage ? () => _confirmAndDeleteRun(r) : null,
                                  onTap: () async {
                                    await ctrl.selectRun(r.id);
                                    await _loadTimeSlots(r.semesterId);
                                    if (mounted) {
                                      setState(() {
                                        _filteredClassIds = null;
                                        _runFaculties = _faculties
                                            .where((f) => r.facultyIds.contains(f.id))
                                            .toList();
                                      });
                                    }
                                  },
                                );
                              },
                            ),
                ),
                VerticalDivider(color: cs.outlineVariant, width: 1),
                // Right panel: timetable grid
                Expanded(
                  child: selected == null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.touch_app_outlined,
                                  size: 56, color: cs.outline),
                              const SizedBox(height: 12),
                              Text('Select a run to view the timetable',
                                  style: TextStyle(color: cs.outline)),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            ClassFilterBar(
                              client: ApiClient(token: AuthController.to.token),
                              faculties: _runFaculties,
                              onScopeSelected: (ids) =>
                                  setState(() => _filteredClassIds = ids),
                            ),
                            _FreeRoomsPanel(
                              rooms: _allRooms
                                  .where((r) =>
                                      r.isActive &&
                                      selected.buildingIds.contains(r.buildingId))
                                  .toList(),
                              entries: ctrl.entries,
                              timeSlots: _timeSlots,
                            ),
                            Expanded(
                              child: _TimetableGrid(
                                entries: _filteredClassIds != null
                                    ? ctrl.entries
                                        .where((e) => e.classIds.any(
                                            (c) => _filteredClassIds!.contains(c)))
                                        .toList()
                                    : ctrl.entries,
                                timeSlots: _timeSlots,
                                run: selected,
                                canManage: canManage,
                                canAdvance: canAdvance,
                                canPublish: canPublish,
                                isTimetableOfficer: isTimetableOfficer,
                                isFacultyHead: isFacultyHead,
                                currentUserId: currentUserId,
                                courseNames: _courseNames,
                                roomNames: _roomNames,
                                facultyNames: {
                                  for (final f in _faculties) f.id: f.code
                                },
                                filteredClassIds: _filteredClassIds,
                                onEntryTap: (canManage || isFacultyHead)
                                    ? (entry) => _showMoveDialog(entry, selected)
                                    : null,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _RunCard extends StatelessWidget {
  final TimetableRun run;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _RunCard({
    required this.run,
    required this.isSelected,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      color: isSelected ? cs.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(run.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Row(
                children: [
                  _StatusBadge(run.status),
                  if (run.isPublished)
                    IconButton(
                      icon: const Icon(Icons.link, size: 18),
                      tooltip: 'Copy shareable link',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        final origin = Uri.base.origin;
                        final link = '$origin/#/public?run=${run.id}';
                        Clipboard.setData(ClipboardData(text: link));
                        Get.snackbar(
                          'Link copied',
                          'Share with students',
                          snackPosition: SnackPosition.BOTTOM,
                          duration: const Duration(seconds: 2),
                        );
                      },
                    ),
                  const Spacer(),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Delete run',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: cs.error,
                      onPressed: onDelete,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${run.facultyIds.length} facult${run.facultyIds.length == 1 ? 'y' : 'ies'} · '
                '${run.buildingIds.length} building${run.buildingIds.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Timetable Grid ────────────────────────────────────────────────────────────

Future<void> _downloadTimetable(int runId, String format,
    {List<int>? classIds}) async {
  try {
    final api = TimetableApi(ApiClient(token: AuthController.to.token));
    final bytes = await api.downloadExport(runId, format, classIds: classIds);
    final blob = html.Blob([Uint8List.fromList(bytes)]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final suffix =
        (classIds != null && classIds.isNotEmpty) ? '_filtered' : '';
    html.AnchorElement(href: url)
      ..setAttribute('download', 'timetable_$runId$suffix.$format')
      ..click();
    html.Url.revokeObjectUrl(url);
  } catch (e) {
    Get.snackbar('Export failed', e.toString(), snackPosition: SnackPosition.BOTTOM);
  }
}

class _TimetableGrid extends StatelessWidget {
  final List<TimetableEntry> entries;
  final List<TimeSlot> timeSlots;
  final TimetableRun run;
  final bool canManage;
  final bool canAdvance;
  final bool canPublish;
  final bool isTimetableOfficer;
  final bool isFacultyHead;
  final int? currentUserId;
  final Map<int, String> courseNames;
  final Map<int, String> roomNames;
  final Map<int, String> facultyNames;
  final List<int>? filteredClassIds;
  final void Function(TimetableEntry)? onEntryTap;

  const _TimetableGrid({
    required this.entries, required this.timeSlots,
    required this.run, required this.canManage,
    this.canAdvance = false, this.canPublish = false,
    this.isTimetableOfficer = false, this.isFacultyHead = false,
    this.currentUserId, this.filteredClassIds,
    this.courseNames = const {}, this.roomNames = const {},
    this.facultyNames = const {},
    this.onEntryTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (timeSlots.isEmpty) {
      return Center(
        child: Text('No time slots for this semester',
            style: TextStyle(color: cs.outline)),
      );
    }

    final days = displayWeekDays(timeSlots);
    final byDay = <String, List<TimeSlot>>{};
    for (final day in days) {
      byDay[day] = timeSlots.where((ts) => ts.dayOfWeek == day).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
    }

    final entryBySlot = <int, TimetableEntry>{};
    for (final e in entries) { entryBySlot[e.timeSlotId] = e; }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Run header
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(run.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold)),
              _StatusBadge(run.status),
              // Generate Draft: draft with no generated output yet, officer only
              if (run.isDraft && run.generatedAt == null && isTimetableOfficer)
                Obx(() {
                  if (TimetableController.to.isGenerating.value) {
                    return const _GeneratingChip();
                  }
                  return FilledButton.icon(
                    onPressed: () => _startGeneration(context, run),
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
                    label: const Text('Generate Draft'),
                  );
                }),
              // Regenerate: draft already generated — re-run replaces the old
              // result (clears it first) instead of stacking another on top.
              if (run.isDraft && run.generatedAt != null && isTimetableOfficer)
                Obx(() {
                  if (TimetableController.to.isGenerating.value) {
                    return const _GeneratingChip();
                  }
                  return OutlinedButton.icon(
                    onPressed: () => _startGeneration(context, run),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Regenerate'),
                  );
                }),
              // Submit for Review: draft already generated, officer only
              if (run.isDraft && run.generatedAt != null && isTimetableOfficer)
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final api = TimetableApi(ApiClient(token: AuthController.to.token));
                      await api.submitForReview(run.id);
                      TimetableController.to.fetchRuns();
                      TimetableController.to.selectRun(run.id);
                    } catch (e) {
                      Get.snackbar('Error', e.toString(),
                          snackPosition: SnackPosition.BOTTOM);
                    }
                  },
                  icon: const Icon(Icons.send_outlined, size: 16),
                  label: const Text('Submit for Review'),
                ),
              if (entries.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: () => _downloadTimetable(run.id, 'csv',
                      classIds: filteredClassIds),
                  icon: const Icon(Icons.table_chart_outlined, size: 16),
                  label:
                      Text(filteredClassIds != null ? 'CSV (filtered)' : 'CSV'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _downloadTimetable(run.id, 'pdf',
                      classIds: filteredClassIds),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                  label:
                      Text(filteredClassIds != null ? 'PDF (filtered)' : 'PDF'),
                ),
              ],
            ],
          ),
          // Publish: approved run, officer only
          if (run.status == 'approved' && isTimetableOfficer)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.icon(
                onPressed: () => TimetableController.to.publish(run.id),
                icon: const Icon(Icons.publish_outlined, size: 16),
                label: const Text('Publish'),
              ),
            ),
          // Under review: show approval panel (visible to everyone, faculty head can act)
          if (run.status == 'under_review')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _ApprovalStatusPanel(
                run: run,
                isFacultyHead: isFacultyHead,
                currentUserId: currentUserId,
                facultyNames: facultyNames,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '${entries.length} session${entries.length == 1 ? '' : 's'} scheduled',
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
          const SizedBox(height: 16),
          // Grid
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: days.map((day) {
                final slots = byDay[day] ?? [];
                return SizedBox(
                  width: 164,
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10)),
                        ),
                        child: Text(day,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: cs.onPrimaryContainer,
                            )),
                      ),
                      ...slots.map((ts) {
                        final entry = entryBySlot[ts.id];
                        return _SlotCell(
                          timeSlot: ts,
                          entry: entry,
                          courseNames: courseNames,
                          roomNames: roomNames,
                          onTap: (onEntryTap != null && entry != null)
                              ? () => onEntryTap!(entry)
                              : null,
                        );
                      }),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotCell extends StatelessWidget {
  final TimeSlot timeSlot;
  final TimetableEntry? entry;
  final Map<int, String> courseNames;
  final Map<int, String> roomNames;
  final VoidCallback? onTap;

  const _SlotCell({
    required this.timeSlot, this.entry,
    this.courseNames = const {}, this.roomNames = const {},
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasEntry = entry != null;

    final cell = Container(
      width: 164,
      constraints: const BoxConstraints(minHeight: 70),
      margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
      decoration: BoxDecoration(
        color: hasEntry
            ? (entry!.isOvercapacity ? cs.errorContainer : cs.secondaryContainer)
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasEntry ? cs.secondary.withAlpha(80) : cs.outlineVariant,
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(timeSlot.label,
              style: TextStyle(fontSize: 10, color: cs.outline)),
          if (hasEntry) ...[
            const SizedBox(height: 4),
            Text(
              courseNames[entry!.courseId] ?? 'Course #${entry!.courseId}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              entry!.roomId == null
                  ? 'Outdoor / off-site'
                  : (roomNames[entry!.roomId] ?? 'Room #${entry!.roomId}'),
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
            if (entry!.isOvercapacity)
              Text('Overcapacity',
                  style: TextStyle(
                      color: cs.error, fontSize: 10, fontWeight: FontWeight.bold)),
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(Icons.edit_outlined, size: 12, color: cs.outline),
              ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: cell,
      );
    }
    return cell;
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'published' => (Colors.green.shade100, Colors.green.shade800),
      'approved' => (Colors.blue.shade100, Colors.blue.shade800),
      'under_review' => (Colors.orange.shade100, Colors.orange.shade800),
      _ => (Colors.grey.shade100, Colors.grey.shade700),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _InfoCard({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: highlight ? cs.primaryContainer.withAlpha(120) : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: highlight
            ? Border.all(color: cs.primary.withAlpha(80))
            : Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 9,
                  color: cs.outline,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: highlight ? cs.primary : cs.onSurface),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _ApprovalStatusPanel extends StatefulWidget {
  final TimetableRun run;
  final bool isFacultyHead;
  final int? currentUserId;
  final Map<int, String> facultyNames;

  const _ApprovalStatusPanel({
    required this.run,
    required this.isFacultyHead,
    required this.currentUserId,
    this.facultyNames = const {},
  });

  @override
  State<_ApprovalStatusPanel> createState() => _ApprovalStatusPanelState();
}

class _ApprovalStatusPanelState extends State<_ApprovalStatusPanel> {
  List<FacultyApproval> _approvals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadApprovals();
  }

  Future<void> _loadApprovals() async {
    try {
      final client = ApiClient(token: AuthController.to.token);
      final approvals = await TimetableApi(client).getApprovals(widget.run.id);
      if (mounted) setState(() { _approvals = approvals; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(FacultyApproval approval) async {
    final client = ApiClient(token: AuthController.to.token);
    try {
      await TimetableApi(client).approveFaculty(widget.run.id, approval.id);
      await _loadApprovals();
      TimetableController.to.fetchRuns();
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _reject(FacultyApproval approval) async {
    final commentCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Reject — Add Comment'),
          content: TextField(
            controller: commentCtrl,
            autofocus: true,
            maxLines: 3,
            onChanged: (_) => setS(() {}),
            decoration: const InputDecoration(
              hintText: 'Describe the issue (required)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: commentCtrl.text.trim().isNotEmpty
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Reject'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || commentCtrl.text.trim().isEmpty) return;
    final client = ApiClient(token: AuthController.to.token);
    try {
      await TimetableApi(client).rejectFaculty(
          widget.run.id, approval.id, commentCtrl.text.trim());
      await _loadApprovals();
      TimetableController.to.fetchRuns();
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }

    final pending = _approvals.where((a) => a.isPending).length;
    final approved = _approvals.where((a) => a.isApproved).length;
    final total = _approvals.length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.how_to_vote_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                'Faculty Approvals — $approved/$total approved',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (pending > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Waiting on $pending faculty head${pending == 1 ? "" : "s"}',
                style: TextStyle(color: cs.outline, fontSize: 12),
              ),
            ),
          const SizedBox(height: 10),
          ..._approvals.map((a) {
            final isMyApproval =
                widget.isFacultyHead && a.facultyHeadId == widget.currentUserId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    a.isApproved
                        ? Icons.check_circle
                        : a.isRejected
                            ? Icons.cancel
                            : Icons.hourglass_empty,
                    size: 16,
                    color: a.isApproved
                        ? Colors.green
                        : a.isRejected
                            ? cs.error
                            : cs.outline,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.facultyNames[a.facultyId] ?? 'Faculty #${a.facultyId}'}'
                          ' — ${a.status.toUpperCase()}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (a.isRejected && a.comment != null)
                          Text(
                            a.comment!,
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.error,
                                fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
                  if (isMyApproval && a.isPending) ...[
                    TextButton(
                      onPressed: () => _reject(a),
                      style: TextButton.styleFrom(foregroundColor: cs.error),
                      child: const Text('Reject',
                          style: TextStyle(fontSize: 12)),
                    ),
                    FilledButton(
                      onPressed: () => _approve(a),
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          minimumSize: Size.zero),
                      child: const Text('Approve',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Inline progress indicator shown in place of the Generate/Regenerate button
/// while a generation job is running, so the user sees it is working.
class _GeneratingChip extends StatelessWidget {
  const _GeneratingChip();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = TimetableController.to.jobStatus.value;
    final msg = status == 'pending'
        ? 'Starting generation…'
        : 'Generating timetable…';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withAlpha(120),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            '$msg this can take up to a minute',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: cs.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}

/// Collapsible panel showing, for a chosen period (day + time slot), which
/// rooms in the run have no session then — so the officer can see exactly what
/// is free at a specific period rather than only rooms idle the whole day.
class _FreeRoomsPanel extends StatefulWidget {
  final List<Room> rooms; // active rooms in the run's buildings
  final List<TimetableEntry> entries; // full run entries (unfiltered)
  final List<TimeSlot> timeSlots;
  const _FreeRoomsPanel({
    required this.rooms,
    required this.entries,
    required this.timeSlots,
  });

  @override
  State<_FreeRoomsPanel> createState() => _FreeRoomsPanelState();
}

class _FreeRoomsPanelState extends State<_FreeRoomsPanel> {
  int? _slotId;

  List<TimeSlot> get _sortedSlots {
    final slots = [...widget.timeSlots];
    slots.sort((a, b) {
      final da = kWeekOrder.indexOf(a.dayOfWeek);
      final db = kWeekOrder.indexOf(b.dayOfWeek);
      if (da != db) return da.compareTo(db);
      return a.startTime.compareTo(b.startTime);
    });
    return slots;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.rooms.isEmpty || widget.timeSlots.isEmpty) {
      return const SizedBox.shrink();
    }

    final slots = _sortedSlots;
    final selectedId = _slotId ?? slots.first.id;

    final usedRoomIds = <int>{};
    for (final e in widget.entries) {
      if (e.roomId != null && e.timeSlotId == selectedId) {
        usedRoomIds.add(e.roomId!);
      }
    }
    final free =
        widget.rooms.where((r) => !usedRoomIds.contains(r.id)).toList();

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ExpansionTile(
        leading: const Icon(Icons.meeting_room_outlined),
        title: const Text('Free rooms by period'),
        subtitle: const Text('Rooms with no session in the selected period'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          DropdownButtonFormField<int>(
            value: selectedId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Period',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: slots
                .map((s) => DropdownMenuItem(
                      value: s.id,
                      child: Text('${s.dayOfWeek} ${s.label}',
                          overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _slotId = v),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${free.length} of ${widget.rooms.length} rooms free',
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13, color: cs.primary),
            ),
          ),
          const SizedBox(height: 8),
          if (free.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('All rooms are in use this period.',
                  style: TextStyle(fontSize: 12, color: cs.outline)),
            )
          else
            SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: free
                    .map((r) => Chip(
                          label: Text(r.name,
                              style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

/// Generation entry point for the officer's "Generate Draft" button.
/// Runs a pre-flight readiness check first: if the run is not ready it shows a
/// dialog listing exactly what is missing, and only attempts generation when
/// every check passes. Any error from the generate call itself is surfaced too,
/// so generation can never fail silently.
Future<void> _startGeneration(BuildContext context, TimetableRun run) async {
  final api = TimetableApi(ApiClient(token: AuthController.to.token));

  Map<String, dynamic> readiness;
  try {
    readiness = await api.getReadiness(run.id);
  } catch (e) {
    if (context.mounted) {
      Get.snackbar('Error', 'Could not check readiness: $e',
          snackPosition: SnackPosition.BOTTOM);
    }
    return;
  }

  final ready = readiness['ready'] == true;
  final checks =
      (readiness['checks'] as List?)?.cast<Map<String, dynamic>>() ?? [];

  if (!ready) {
    if (context.mounted) await _showReadinessDialog(context, checks);
    return;
  }

  try {
    await TimetableController.to.generate(run.id);
  } on DioException catch (e) {
    final detail = (e.response?.data as Map?)?['detail'] as String? ??
        e.message ??
        'Generation could not be started.';
    if (context.mounted) {
      Get.snackbar('Cannot generate', detail,
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 6));
    }
  } catch (e) {
    if (context.mounted) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }
}

Future<void> _showReadinessDialog(
    BuildContext context, List<Map<String, dynamic>> checks) {
  final cs = Theme.of(context).colorScheme;
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: cs.error),
          const SizedBox(width: 8),
          const Expanded(child: Text('Not ready to generate')),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fix the items marked below before generating this timetable.',
              style: TextStyle(fontSize: 13, color: cs.outline),
            ),
            const SizedBox(height: 12),
            ...checks.map((c) {
              final ok = c['ok'] == true;
              final detail = (c['detail'] as String?) ?? '';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      ok ? Icons.check_circle_outline : Icons.cancel_outlined,
                      size: 18,
                      color: ok ? Colors.green : cs.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c['label'] as String? ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  ok ? FontWeight.w400 : FontWeight.w600,
                            ),
                          ),
                          if (!ok && detail.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                detail,
                                style: TextStyle(fontSize: 12, color: cs.error),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}
