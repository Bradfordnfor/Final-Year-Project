import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/course_api.dart';
import '../../core/api/timetable_api.dart';
import '../../core/api/academic_api.dart';
import '../../core/api/university_api.dart';
import '../../core/models/academic.dart';
import '../../core/models/course.dart';
import '../../core/models/room.dart';
import '../../core/models/timetable.dart';

class PublicTimetableScreen extends StatefulWidget {
  const PublicTimetableScreen({super.key});

  @override
  State<PublicTimetableScreen> createState() => _PublicTimetableScreenState();
}

class _PublicTimetableScreenState extends State<PublicTimetableScreen> {
  List<TimetableRun> _runs = [];
  TimetableRun? _selectedRun;
  List<TimetableEntry> _entries = [];
  List<TimeSlot> _timeSlots = [];
  Map<int, String> _courseNames = {};
  Map<int, String> _roomNames = {};
  bool _loading = true;
  bool _loadingEntries = false;

  // Unauthenticated client (no token)
  final _client = ApiClient();

  @override
  void initState() {
    super.initState();
    _loadPublished();
  }

  Future<void> _loadPublished() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        TimetableApi(_client).getPublishedRuns(),
        CourseApi(_client).getCourses(),
        UniversityApi(_client).getRooms(),
      ]);
      _runs = results[0] as List<TimetableRun>;
      final courses = results[1] as List<Course>;
      final rooms = results[2] as List<Room>;
      _courseNames = {for (final c in courses) c.id: '${c.code} — ${c.name}'};
      _roomNames = {for (final r in rooms) r.id: r.name};
    } catch (_) {
      _runs = [];
    }
    setState(() => _loading = false);
  }

  Future<void> _selectRun(TimetableRun run) async {
    setState(() {
      _selectedRun = run;
      _loadingEntries = true;
      _entries = [];
      _timeSlots = [];
    });
    try {
      final api = TimetableApi(_client);
      final academicApi = AcademicApi(_client);
      final results = await Future.wait([
        api.getEntries(run.id),
        academicApi.getTimeSlots(run.semesterId),
      ]);
      setState(() {
        _entries = results[0] as List<TimetableEntry>;
        _timeSlots = results[1] as List<TimeSlot>;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load timetable: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingEntries = false);
    }
  }

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.public, color: cs.primary, size: 20),
            const SizedBox(width: 8),
            const Text('Public Timetable'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPublished,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _runs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 64, color: cs.outline),
                      const SizedBox(height: 16),
                      Text('No published timetables yet',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('Check back later.',
                          style: TextStyle(color: cs.outline)),
                    ],
                  ),
                )
              : isWide
                  ? Row(
                      children: [
                        SizedBox(
                          width: 280,
                          child: _RunList(
                            runs: _runs,
                            selected: _selectedRun,
                            onSelect: _selectRun,
                          ),
                        ),
                        VerticalDivider(color: cs.outlineVariant, width: 1),
                        Expanded(child: _TimetableView(
                          run: _selectedRun,
                          entries: _entries,
                          timeSlots: _timeSlots,
                          loading: _loadingEntries,
                          days: _days,
                          courseNames: _courseNames,
                          roomNames: _roomNames,
                        )),
                      ],
                    )
                  : _selectedRun == null
                      ? _RunList(
                          runs: _runs,
                          selected: null,
                          onSelect: _selectRun,
                        )
                      : Column(
                          children: [
                            ListTile(
                              leading: BackButton(
                                onPressed: () =>
                                    setState(() => _selectedRun = null),
                              ),
                              title: Text(_selectedRun!.name),
                            ),
                            Expanded(child: _TimetableView(
                              run: _selectedRun,
                              entries: _entries,
                              timeSlots: _timeSlots,
                              loading: _loadingEntries,
                              days: _days,
                              courseNames: _courseNames,
                              roomNames: _roomNames,
                            )),
                          ],
                        ),
    );
  }
}

class _RunList extends StatelessWidget {
  final List<TimetableRun> runs;
  final TimetableRun? selected;
  final Future<void> Function(TimetableRun) onSelect;

  const _RunList({required this.runs, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text('Published Timetables',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            itemCount: runs.length,
            itemBuilder: (_, i) {
              final r = runs[i];
              final isSelected = r.id == selected?.id;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: isSelected ? cs.primaryContainer : null,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isSelected
                        ? cs.onPrimaryContainer.withAlpha(20)
                        : cs.primaryContainer,
                    child: Icon(Icons.calendar_month,
                        size: 18,
                        color: isSelected ? cs.onPrimaryContainer : cs.primary),
                  ),
                  title: Text(r.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isSelected ? cs.onPrimaryContainer : null,
                      )),
                  subtitle: Text(
                    '${r.facultyIds.length} facult${r.facultyIds.length == 1 ? 'y' : 'ies'}',
                    style: TextStyle(
                        color: isSelected
                            ? cs.onPrimaryContainer.withAlpha(180)
                            : null),
                  ),
                  selected: isSelected,
                  onTap: () => onSelect(r),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TimetableView extends StatelessWidget {
  final TimetableRun? run;
  final List<TimetableEntry> entries;
  final List<TimeSlot> timeSlots;
  final bool loading;
  final List<String> days;
  final Map<int, String> courseNames;
  final Map<int, String> roomNames;

  const _TimetableView({
    required this.run, required this.entries, required this.timeSlots,
    required this.loading, required this.days,
    this.courseNames = const {}, this.roomNames = const {},
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (run == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined, size: 56, color: cs.outline),
            const SizedBox(height: 12),
            Text('Select a timetable to view',
                style: TextStyle(color: cs.outline)),
          ],
        ),
      );
    }

    if (loading) return const Center(child: CircularProgressIndicator());

    if (timeSlots.isEmpty) {
      return Center(child: Text('No schedule data',
          style: TextStyle(color: cs.outline)));
    }

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
          Text(run!.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${entries.length} sessions scheduled',
              style: TextStyle(color: cs.outline, fontSize: 13)),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: days.map((day) {
                final slots = byDay[day] ?? [];
                return SizedBox(
                  width: 170,
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10)),
                        ),
                        child: Text(day,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: cs.onPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            )),
                      ),
                      ...slots.map((ts) {
                        final entry = entryBySlot[ts.id];
                        return _PublicSlotCell(
                          timeSlot: ts, entry: entry,
                          courseNames: courseNames, roomNames: roomNames,
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

class _PublicSlotCell extends StatelessWidget {
  final TimeSlot timeSlot;
  final TimetableEntry? entry;
  final Map<int, String> courseNames;
  final Map<int, String> roomNames;

  const _PublicSlotCell({
    required this.timeSlot, this.entry,
    this.courseNames = const {}, this.roomNames = const {},
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final has = entry != null;

    return Container(
      width: 170,
      constraints: const BoxConstraints(minHeight: 64),
      margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
      decoration: BoxDecoration(
        color: has ? cs.primaryContainer.withAlpha(180) : cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: has ? cs.primary.withAlpha(60) : cs.outlineVariant,
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(timeSlot.label,
              style: TextStyle(fontSize: 10, color: cs.outline)),
          if (has) ...[
            const SizedBox(height: 4),
            Text(
              courseNames[entry!.courseId] ?? 'Course #${entry!.courseId}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              roomNames[entry!.roomId] ?? 'Room #${entry!.roomId}',
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
          ],
        ],
      ),
    );
  }
}
