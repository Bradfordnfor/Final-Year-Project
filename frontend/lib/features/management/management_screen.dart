import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';

import '../../core/api/api_client.dart';
import '../../core/api/course_api.dart';
import '../../core/api/university_api.dart';
import '../../core/api/user_api.dart';
import '../../core/api/academic_api.dart';
import '../../core/controllers/auth_controller.dart';
import '../../core/models/course.dart';
import '../../core/models/room.dart';
import '../../core/models/university.dart';
import '../../core/models/user.dart';
import '../../core/models/academic.dart';

class ManagementScreen extends StatelessWidget {
  const ManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthController.to.user.value;
    final isAdmin = user?.isUniversityAdmin ?? false;
    final isLecturer = user?.isLecturer ?? false;

    final tabs = <Tab>[];
    final views = <Widget>[];

    if (isAdmin) {
      tabs.add(const Tab(icon: Icon(Icons.meeting_room_outlined), text: 'Rooms'));
      views.add(const _RoomsTab());
    }

    tabs.add(const Tab(icon: Icon(Icons.book_outlined), text: 'Courses'));
    views.add(const _CoursesTab());

    if (isAdmin) {
      tabs.add(const Tab(icon: Icon(Icons.people_outline), text: 'Users'));
      views.add(const _UsersTab());
    }

    if (isLecturer || isAdmin) {
      tabs.add(const Tab(icon: Icon(Icons.event_available_outlined), text: 'Availability'));
      views.add(const _AvailabilityTab());
    }

    if (tabs.isEmpty) {
      return const Center(child: Text('No management options for your role.'));
    }

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          TabBar(tabs: tabs),
          Expanded(
            child: TabBarView(children: views),
          ),
        ],
      ),
    );
  }
}

// ─── Rooms Tab ───────────────────────────────────────────────────────────────

class _RoomsTab extends StatefulWidget {
  const _RoomsTab();

  @override
  State<_RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends State<_RoomsTab> {
  late final UniversityApi _api;
  List<Room> _rooms = [];
  bool _loading = true;

  static const _roomTypes = ['lecture_hall', 'lab', 'outdoor'];

  @override
  void initState() {
    super.initState();
    _api = UniversityApi(ApiClient(token: AuthController.to.token));
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rooms = await _api.getRooms();
      setState(() { _rooms = rooms; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _delete(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Room'),
        content: const Text('Are you sure you want to delete this room?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.deleteRoom(id);
      await _load();
    } catch (e) {
      Get.snackbar('Error', 'Failed to delete room: $e');
    }
  }

  Future<void> _showAddSheet() async {
    final nameCtrl = TextEditingController();
    final capCtrl = TextEditingController();
    String selectedType = _roomTypes.first;
    List<Building> buildings = [];
    int? selectedBuildingId;

    try {
      buildings = await _api.getBuildings();
      if (buildings.isNotEmpty) selectedBuildingId = buildings.first.id;
    } catch (_) {}

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add Room', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Room Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: capCtrl,
                decoration: const InputDecoration(labelText: 'Capacity', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: const InputDecoration(labelText: 'Room Type', border: OutlineInputBorder()),
                items: _roomTypes.map((t) => DropdownMenuItem(
                  value: t, child: Text(t.replaceAll('_', ' ')),
                )).toList(),
                onChanged: (v) => setSheet(() => selectedType = v!),
              ),
              if (buildings.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: selectedBuildingId,
                  decoration: const InputDecoration(labelText: 'Building', border: OutlineInputBorder()),
                  items: buildings.map((b) => DropdownMenuItem(
                    value: b.id, child: Text(b.name),
                  )).toList(),
                  onChanged: (v) => setSheet(() => selectedBuildingId = v),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  try {
                    await _api.createRoom({
                      'name': nameCtrl.text.trim(),
                      'capacity': int.parse(capCtrl.text.trim()),
                      'room_type': selectedType,
                      if (selectedBuildingId != null) 'building_id': selectedBuildingId,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _load();
                  } catch (e) {
                    Get.snackbar('Error', 'Failed: $e');
                  }
                },
                child: const Text('Add Room'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        child: const Icon(Icons.add),
      ),
      body: _rooms.isEmpty
          ? const Center(child: Text('No rooms yet.', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              itemCount: _rooms.length,
              itemBuilder: (_, i) {
                final r = _rooms[i];
                return ListTile(
                  leading: const Icon(Icons.meeting_room_outlined),
                  title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${r.roomType.replaceAll('_', ' ')} · Capacity ${r.capacity}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _delete(r.id),
                  ),
                ).animate(delay: Duration(milliseconds: i * 30)).fadeIn(duration: 200.ms);
              },
            ),
    );
  }
}

// ─── Courses Tab ─────────────────────────────────────────────────────────────

class _CoursesTab extends StatefulWidget {
  const _CoursesTab();

  @override
  State<_CoursesTab> createState() => _CoursesTabState();
}

class _CoursesTabState extends State<_CoursesTab> {
  late final CourseApi _api;
  List<Course> _courses = [];
  bool _loading = true;
  String _search = '';

  static const _roomTypes = ['lecture_hall', 'lab', 'outdoor'];

  @override
  void initState() {
    super.initState();
    _api = CourseApi(ApiClient(token: AuthController.to.token));
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final courses = await _api.getCourses();
      setState(() { _courses = courses; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _delete(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Course'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.deleteCourse(id);
      await _load();
    } catch (e) {
      Get.snackbar('Error', 'Failed: $e');
    }
  }

  Future<void> _showAddSheet() async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String selectedType = _roomTypes.first;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add Course', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(labelText: 'Course Code (e.g. CSC 201)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Course Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: const InputDecoration(labelText: 'Room Type Required', border: OutlineInputBorder()),
                items: _roomTypes.map((t) => DropdownMenuItem(
                  value: t, child: Text(t.replaceAll('_', ' ')),
                )).toList(),
                onChanged: (v) => setSheet(() => selectedType = v!),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  try {
                    await _api.createCourse({
                      'code': codeCtrl.text.trim(),
                      'name': nameCtrl.text.trim(),
                      'room_type_required': selectedType,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _load();
                  } catch (e) {
                    Get.snackbar('Error', 'Failed: $e');
                  }
                },
                child: const Text('Add Course'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _courses.where((c) =>
        c.code.toLowerCase().contains(_search.toLowerCase()) ||
        c.name.toLowerCase().contains(_search.toLowerCase())).toList();

    if (_loading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search courses…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No courses found.', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      return ListTile(
                        leading: const Icon(Icons.book_outlined),
                        title: Text(c.code,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(c.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(
                              label: Text(c.roomTypeRequired.replaceAll('_', ' '),
                                  style: const TextStyle(fontSize: 11)),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _delete(c.id),
                            ),
                          ],
                        ),
                      ).animate(delay: Duration(milliseconds: i * 30)).fadeIn(duration: 200.ms);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Users Tab ────────────────────────────────────────────────────────────────

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  late final UserApi _api;
  List<UserModel> _users = [];
  bool _loading = true;
  String _search = '';

  static const _roles = [
    'university_admin', 'faculty_head', 'timetable_officer', 'lecturer', 'student',
  ];

  static const _roleColors = {
    'super_admin': Colors.purple,
    'university_admin': Colors.blue,
    'faculty_head': Colors.teal,
    'timetable_officer': Colors.indigo,
    'lecturer': Colors.green,
    'student': Colors.grey,
  };

  @override
  void initState() {
    super.initState();
    _api = UserApi(ApiClient(token: AuthController.to.token));
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final users = await _api.getUsers();
      setState(() { _users = users; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _showAddSheet() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String selectedRole = _roles.first;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add User', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              TextField(controller: passCtrl,
                  decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                  obscureText: true),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                items: _roles.map((r) => DropdownMenuItem(
                  value: r, child: Text(r.replaceAll('_', ' ')),
                )).toList(),
                onChanged: (v) => setSheet(() => selectedRole = v!),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  try {
                    await _api.createUser({
                      'full_name': nameCtrl.text.trim(),
                      'email': emailCtrl.text.trim(),
                      'password': passCtrl.text,
                      'role': selectedRole,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _load();
                  } catch (e) {
                    Get.snackbar('Error', 'Failed: $e');
                  }
                },
                child: const Text('Create User'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _users.where((u) =>
        u.fullName.toLowerCase().contains(_search.toLowerCase()) ||
        u.email.toLowerCase().contains(_search.toLowerCase())).toList();

    if (_loading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        child: const Icon(Icons.person_add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by name or email…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No users found.', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final u = filtered[i];
                      final roleColor = _roleColors[u.role] ?? Colors.grey;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: roleColor.withAlpha(40),
                          child: Text(
                            u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : '?',
                            style: TextStyle(color: roleColor, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(u.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(u.email),
                        trailing: Chip(
                          label: Text(u.role.replaceAll('_', ' '),
                              style: const TextStyle(fontSize: 11, color: Colors.white)),
                          backgroundColor: roleColor,
                          padding: EdgeInsets.zero,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ).animate(delay: Duration(milliseconds: i * 30)).fadeIn(duration: 200.ms);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Availability Tab ─────────────────────────────────────────────────────────

class _AvailabilityTab extends StatefulWidget {
  const _AvailabilityTab();

  @override
  State<_AvailabilityTab> createState() => _AvailabilityTabState();
}

class _AvailabilityTabState extends State<_AvailabilityTab> {
  late final UserApi _api;
  late final AcademicApi _academicApi;
  List<TimeSlot> _slots = [];
  List<Map<String, dynamic>> _unavailable = [];
  final Set<int> _unavailableSlotIds = {};
  bool _loading = true;
  bool _saving = false;

  int get _lecturerId => AuthController.to.user.value!.id;

  @override
  void initState() {
    super.initState();
    final token = AuthController.to.token;
    _api = UserApi(ApiClient(token: token));
    _academicApi = AcademicApi(ApiClient(token: token));
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final semesters = await _academicApi.getSemesters();
      if (semesters.isNotEmpty) {
        final slots = await _academicApi.getTimeSlots(semesters.first.id);
        _slots = slots;
      }
      _unavailable = await _api.getLecturerAvailability(_lecturerId);
      _unavailableSlotIds
        ..clear()
        ..addAll(_unavailable.map((e) => e['time_slot_id'] as int));
    } catch (_) {
      // keep empty state on error
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Delete all existing unavailability entries
      for (final entry in _unavailable) {
        await _api.deleteAvailability(entry['id'] as int);
      }
      // Add current selections
      for (final slotId in _unavailableSlotIds) {
        await _api.addAvailability(_lecturerId, slotId);
      }
      Get.snackbar('Saved', 'Availability updated.',
          backgroundColor: Colors.green.shade50);
      await _load();
    } catch (e) {
      Get.snackbar('Error', 'Failed to save: $e');
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
    final slotsByDay = {
      for (final day in days)
        day: _slots.where((s) => s.dayOfWeek.toLowerCase() == day.toLowerCase()).toList()
    };

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tap slots you are NOT available. Red = unavailable.',
                  style: TextStyle(fontSize: 12, color: Colors.blue),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _slots.isEmpty
              ? const Center(
                  child: Text('No time slots available.',
                      style: TextStyle(color: Colors.grey)))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                          Theme.of(context).colorScheme.primaryContainer),
                      columns: [
                        const DataColumn(label: Text('Time')),
                        ...days.map((d) => DataColumn(
                            label: Text(d.substring(0, 3),
                                style: const TextStyle(fontWeight: FontWeight.w600)))),
                      ],
                      rows: _buildRows(days, slotsByDay),
                    ),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            label: const Text('Save Availability'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ],
    );
  }

  List<DataRow> _buildRows(
      List<String> days, Map<String, List<TimeSlot>> slotsByDay) {
    // Collect unique time labels
    final timeLabels = _slots.map((s) => s.label).toSet().toList()..sort();

    return timeLabels.map((label) {
      return DataRow(
        cells: [
          DataCell(Text(label, style: const TextStyle(fontSize: 12))),
          ...days.map((day) {
            final slot = slotsByDay[day]?.where((s) => s.label == label).firstOrNull;
            if (slot == null) return const DataCell(SizedBox.shrink());
            final isUnavailable = _unavailableSlotIds.contains(slot.id);
            return DataCell(
              GestureDetector(
                onTap: () => setState(() {
                  if (isUnavailable) {
                    _unavailableSlotIds.remove(slot.id);
                  } else {
                    _unavailableSlotIds.add(slot.id);
                  }
                }),
                child: Container(
                  width: 60,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isUnavailable
                        ? Colors.red.shade100
                        : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    isUnavailable ? Icons.close : Icons.check,
                    size: 16,
                    color: isUnavailable ? Colors.red.shade700 : Colors.green.shade700,
                  ),
                ),
              ),
            );
          }),
        ],
      );
    }).toList();
  }
}
