import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api/academic_api.dart';
import '../../core/api/api_client.dart';
import '../../core/controllers/auth_controller.dart';
import '../../core/controllers/timetable_controller.dart';
import '../../core/models/academic.dart';
import '../../core/models/timetable.dart';

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  List<Semester> _semesters = [];
  List<TimeSlot> _timeSlots = [];
  bool _loadingMeta = false;

  @override
  void initState() {
    super.initState();
    TimetableController.to.fetchTimetables();
    _loadSemesters();
  }

  Future<void> _loadSemesters() async {
    setState(() => _loadingMeta = true);
    try {
      _semesters = await AcademicApi(
              ApiClient(token: AuthController.to.token))
          .getSemesters();
    } finally {
      setState(() => _loadingMeta = false);
    }
  }

  Future<void> _loadTimeSlots(int semesterId) async {
    _timeSlots = await AcademicApi(
            ApiClient(token: AuthController.to.token))
        .getTimeSlots(semesterId);
    setState(() {});
  }

  void _showCreateDialog() {
    if (_semesters.isEmpty) {
      Get.snackbar('No Semesters', 'No semesters found.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    Semester? picked = _semesters.first;
    final deptCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('New Timetable'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Semester>(
                initialValue: picked,
                decoration: const InputDecoration(
                    labelText: 'Semester', border: OutlineInputBorder()),
                items: _semesters
                    .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                    .toList(),
                onChanged: (v) => setS(() => picked = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: deptCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Department ID', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final deptId = int.tryParse(deptCtrl.text);
                if (deptId == null || picked == null) return;
                Navigator.pop(ctx);
                await TimetableController.to.create(picked!.id, deptId);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canManage =
        AuthController.to.user.value?.canManageTimetable ?? false;

    return Obx(() {
      final ctrl = TimetableController.to;
      final timetables = ctrl.timetables;
      final selected = ctrl.selected.value;

      return Column(
        children: [
          // Top bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Text('Timetables',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (canManage)
                  FilledButton.icon(
                    onPressed: _loadingMeta ? null : _showCreateDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: timetable list
                SizedBox(
                  width: 220,
                  child: ctrl.isLoading.value
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: timetables.length,
                          itemBuilder: (_, i) {
                            final t = timetables[i];
                            final isActive = selected?.id == t.id;
                            return Card(
                              color: isActive
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : null,
                              child: ListTile(
                                dense: true,
                                title: Text('Timetable #${t.id}'),
                                subtitle: Text(
                                  t.status.replaceAll('_', ' '),
                                  style: TextStyle(
                                      color: _statusColor(context, t.status)),
                                ),
                                selected: isActive,
                                onTap: () async {
                                  await ctrl.selectTimetable(t.id);
                                  if (t.semesterId != 0) {
                                    await _loadTimeSlots(t.semesterId);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                // Right: grid
                Expanded(
                  child: selected == null
                      ? const Center(
                          child: Text('Select a timetable to view the grid'))
                      : _TimetableGrid(
                          entries: ctrl.entries,
                          timeSlots: _timeSlots,
                          timetable: selected,
                          canManage: canManage,
                        ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Color _statusColor(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    return switch (status) {
      'published' => Colors.green,
      'approved' => cs.primary,
      'under_review' => cs.secondary,
      _ => cs.outline,
    };
  }
}

// ── Timetable Grid ────────────────────────────────────────────────────────────

class _TimetableGrid extends StatelessWidget {
  final List<TimetableEntry> entries;
  final List<TimeSlot> timeSlots;
  final TimetableModel timetable;
  final bool canManage;

  const _TimetableGrid({
    required this.entries,
    required this.timeSlots,
    required this.timetable,
    required this.canManage,
  });

  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'
  ];

  @override
  Widget build(BuildContext context) {
    if (timeSlots.isEmpty) {
      return const Center(child: Text('No time slots — select a timetable'));
    }

    // Group time slots by day
    final byDay = <String, List<TimeSlot>>{};
    for (final day in _days) {
      byDay[day] =
          timeSlots.where((ts) => ts.dayOfWeek == day).toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));
    }

    // Index entries by time_slot_id
    final entryBySlot = <int, TimetableEntry>{};
    for (final e in entries) {
      entryBySlot[e.timeSlotId] = e;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timetable header
          Row(
            children: [
              Text(
                'Timetable #${timetable.id}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              _StatusChip(timetable.status),
            ],
          ),
          const SizedBox(height: 16),
          // Weekly grid
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _days.map((day) {
                final slots = byDay[day] ?? [];
                return SizedBox(
                  width: 160,
                  child: Column(
                    children: [
                      // Day header
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 4),
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        child: Text(
                          day,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      // Slot cells
                      ...slots.map((ts) {
                        final entry = entryBySlot[ts.id];
                        return _SlotCell(
                          timeSlot: ts,
                          entry: entry,
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

  const _SlotCell({required this.timeSlot, this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasEntry = entry != null;

    return Container(
      width: 160,
      constraints: const BoxConstraints(minHeight: 72),
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: hasEntry
            ? (entry!.isOvercapacity
                ? cs.errorContainer
                : cs.secondaryContainer)
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasEntry ? cs.secondary.withAlpha(100) : cs.outlineVariant,
        ),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            timeSlot.label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: cs.outline),
          ),
          if (hasEntry) ...[
            const SizedBox(height: 4),
            Text(
              'Course #${entry!.courseId}',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 12),
            ),
            Text(
              'Room #${entry!.roomId}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.outline),
            ),
            if (entry!.isOvercapacity)
              Text(
                'Overcapacity',
                style: TextStyle(
                    color: cs.error,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'published' => Colors.green,
      'approved' => Theme.of(context).colorScheme.primary,
      'under_review' => Theme.of(context).colorScheme.secondary,
      _ => Theme.of(context).colorScheme.outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
