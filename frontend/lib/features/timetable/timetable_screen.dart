import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api/academic_api.dart';
import '../../core/api/api_client.dart';
import '../../core/api/university_api.dart';
import '../../core/controllers/auth_controller.dart';
import '../../core/controllers/timetable_controller.dart';
import '../../core/models/academic.dart';
import '../../core/models/timetable.dart';
import '../../core/models/university.dart';

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
  bool _loadingMeta = true;

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
      ]);
      if (mounted) {
        setState(() {
          _semesters = results[0] as List<Semester>;
          _faculties = results[1] as List<Faculty>;
          _buildings = results[2] as List<Building>;
          _loadingMeta = false;
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
                                  onTap: () async {
                                    await ctrl.selectRun(r.id);
                                    await _loadTimeSlots(r.semesterId);
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
                      : _TimetableGrid(
                          entries: ctrl.entries,
                          timeSlots: _timeSlots,
                          run: selected,
                          canManage: canManage,
                          canAdvance: canAdvance,
                          canPublish: canPublish,
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

  const _RunCard({required this.run, required this.isSelected, required this.onTap});

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
              _StatusBadge(run.status),
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

class _TimetableGrid extends StatelessWidget {
  final List<TimetableEntry> entries;
  final List<TimeSlot> timeSlots;
  final TimetableRun run;
  final bool canManage;
  final bool canAdvance;
  final bool canPublish;

  const _TimetableGrid({
    required this.entries, required this.timeSlots,
    required this.run, required this.canManage,
    this.canAdvance = false, this.canPublish = false,
  });

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (timeSlots.isEmpty) {
      return Center(
        child: Text('No time slots for this semester',
            style: TextStyle(color: cs.outline)),
      );
    }

    final byDay = <String, List<TimeSlot>>{};
    for (final day in _days) {
      byDay[day] = timeSlots.where((ts) => ts.dayOfWeek == day).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
    }

    final entryBySlot = <int, TimetableEntry>{};
    for (final e in entries) entryBySlot[e.timeSlotId] = e;

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
              if (canAdvance && run.status == 'draft')
                OutlinedButton.icon(
                  onPressed: () => TimetableController.to.advanceStatus(run.id),
                  icon: const Icon(Icons.send_outlined, size: 16),
                  label: const Text('Submit for Review'),
                ),
              if (canAdvance && run.status == 'under_review')
                FilledButton.tonalIcon(
                  onPressed: () => TimetableController.to.advanceStatus(run.id),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Approve'),
                ),
              if (canPublish && run.status == 'approved')
                FilledButton.icon(
                  onPressed: () => TimetableController.to.publish(run.id),
                  icon: const Icon(Icons.publish_outlined, size: 16),
                  label: const Text('Publish'),
                ),
            ],
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
              children: _days.map((day) {
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
                      ...slots.map((ts) => _SlotCell(
                            timeSlot: ts,
                            entry: entryBySlot[ts.id],
                          )),
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
  const _SlotCell({required this.timeSlot, this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasEntry = entry != null;

    return Container(
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
            Text('Course #${entry!.courseId}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            Text('Room #${entry!.roomId}',
                style: TextStyle(fontSize: 11, color: cs.outline)),
            if (entry!.isOvercapacity)
              Text('Overcapacity',
                  style: TextStyle(
                      color: cs.error, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ],
      ),
    );
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
