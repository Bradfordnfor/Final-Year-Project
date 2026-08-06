import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';

import '../../core/api/academic_api.dart';
import '../../core/api/api_client.dart';
import '../../core/api/course_api.dart';
import '../../core/api/university_api.dart';
import '../../core/api/user_api.dart';
import '../../core/controllers/auth_controller.dart';
import '../../core/models/academic.dart';
import '../../core/models/course.dart';
import '../../core/models/room.dart';
import '../../core/models/university.dart';
import '../../core/utils/week_days.dart';
import '../../core/models/user.dart';

class ManagementScreen extends StatelessWidget {
  const ManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthController.to.user.value;
    final isAdmin = user?.canManageUniversity ?? false;
    final isLecturer = user?.isLecturer ?? false;

    final tabs = <Tab>[];
    final views = <Widget>[];

    if (isAdmin) {
      tabs.add(const Tab(icon: Icon(Icons.apartment_outlined), text: 'Buildings'));
      views.add(const _BuildingsTab());

      tabs.add(const Tab(icon: Icon(Icons.people_outline), text: 'Users'));
      views.add(const _UsersTab());

      tabs.add(const Tab(icon: Icon(Icons.schedule_outlined), text: 'Semesters'));
      views.add(const _SemestersTab());

      tabs.add(const Tab(icon: Icon(Icons.book_outlined), text: 'Courses'));
      views.add(const _CoursesTab());
    }

    if (isLecturer) {
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

// ─── Buildings Tab ────────────────────────────────────────────────────────────

class _BuildingsTab extends StatefulWidget {
  const _BuildingsTab();

  @override
  State<_BuildingsTab> createState() => _BuildingsTabState();
}

class _BuildingsTabState extends State<_BuildingsTab> {
  late final UniversityApi _api;
  List<Building> _buildings = [];
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
      final results = await Future.wait([_api.getBuildings(), _api.getRooms()]);
      setState(() {
        _buildings = results[0] as List<Building>;
        _rooms = results[1] as List<Room>;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<Room> _roomsFor(int buildingId) =>
      _rooms.where((r) => r.buildingId == buildingId).toList();

  Future<void> _addBuilding() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Building'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Building Name', hintText: 'e.g. FET Main Block')),
            const SizedBox(height: 12),
            TextField(controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Description (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final uid = AuthController.to.user.value?.universityId;
      await _api.createBuilding({
        'name': nameCtrl.text.trim(),
        if (descCtrl.text.trim().isNotEmpty) 'description': descCtrl.text.trim(),
        'university_id': uid,
      });
      _load();
    } catch (e) {
      Get.snackbar('Error', 'Failed to add building: $e');
    }
  }

  Future<void> _deleteBuilding(Building b) async {
    final rooms = _roomsFor(b.id);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Building'),
        content: Text(rooms.isEmpty
            ? 'Delete "${b.name}"?'
            : 'Delete "${b.name}" and its ${rooms.length} room${rooms.length == 1 ? '' : 's'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.deleteBuilding(b.id);
      _load();
    } catch (e) {
      Get.snackbar('Error', 'Failed to delete building: $e');
    }
  }

  Future<void> _addRoom(int buildingId) async {
    final nameCtrl = TextEditingController();
    final capCtrl = TextEditingController();
    String selectedType = _roomTypes.first;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
              Row(children: [
                Text('Add Room', style: Theme.of(ctx).textTheme.titleLarge),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Room Name', hintText: 'e.g. Amphi 750',
                    prefixIcon: Icon(Icons.meeting_room_outlined)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: capCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Capacity',
                    prefixIcon: Icon(Icons.people_outline)),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: const InputDecoration(
                    labelText: 'Room Type',
                    prefixIcon: Icon(Icons.category_outlined)),
                items: _roomTypes.map((t) => DropdownMenuItem(
                  value: t, child: Text(t.replaceAll('_', ' ')),
                )).toList(),
                onChanged: (v) => setSheet(() => selectedType = v!),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Room'),
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty || capCtrl.text.trim().isEmpty) {
                    Get.snackbar('Required', 'Fill all fields.',
                        snackPosition: SnackPosition.BOTTOM);
                    return;
                  }
                  try {
                    await _api.createRoom({
                      'name': nameCtrl.text.trim(),
                      'capacity': int.parse(capCtrl.text.trim()),
                      'room_type': selectedType,
                      'building_id': buildingId,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    _load();
                  } catch (e) {
                    Get.snackbar('Error', 'Failed: $e');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteRoom(Room r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Room'),
        content: Text('Delete "${r.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.deleteRoom(r.id);
      _load();
    } catch (e) {
      Get.snackbar('Error', 'Failed to delete room: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addBuilding,
        icon: const Icon(Icons.add),
        label: const Text('Add Building'),
      ),
      body: _buildings.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.apartment_outlined, size: 64, color: cs.outline),
                  const SizedBox(height: 16),
                  Text('No buildings yet', style: TextStyle(color: cs.outline)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: _buildings.length,
              itemBuilder: (_, i) {
                final b = _buildings[i];
                final rooms = _roomsFor(b.id);
                return _BuildingCard(
                  building: b,
                  rooms: rooms,
                  onAddRoom: () => _addRoom(b.id),
                  onDeleteBuilding: () => _deleteBuilding(b),
                  onDeleteRoom: _deleteRoom,
                ).animate(delay: Duration(milliseconds: i * 40)).fadeIn(duration: 200.ms);
              },
            ),
    );
  }
}

class _BuildingCard extends StatefulWidget {
  final Building building;
  final List<Room> rooms;
  final VoidCallback onAddRoom;
  final VoidCallback onDeleteBuilding;
  final Future<void> Function(Room) onDeleteRoom;

  const _BuildingCard({
    required this.building, required this.rooms,
    required this.onAddRoom, required this.onDeleteBuilding,
    required this.onDeleteRoom,
  });

  @override
  State<_BuildingCard> createState() => _BuildingCardState();
}

class _BuildingCardState extends State<_BuildingCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rooms = widget.rooms;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.apartment_outlined,
                        size: 20, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.building.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15)),
                        Text('${rooms.length} room${rooms.length == 1 ? '' : 's'}',
                            style: TextStyle(fontSize: 12, color: cs.outline)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onPressed: widget.onAddRoom,
                    tooltip: 'Add Room',
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 20, color: cs.error),
                    onPressed: widget.onDeleteBuilding,
                    tooltip: 'Delete Building',
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      color: cs.outline),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(color: cs.outlineVariant, height: 1),
            if (rooms.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No rooms yet — tap + to add one',
                    style: TextStyle(color: cs.outline, fontSize: 13)),
              )
            else
              ...rooms.map((r) => ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                    leading: Icon(Icons.meeting_room_outlined,
                        color: cs.primary, size: 20),
                    title: Text(r.name,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(
                        '${r.roomType.replaceAll('_', ' ')} · Cap ${r.capacity}',
                        style: const TextStyle(fontSize: 12)),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline, color: cs.error, size: 20),
                      onPressed: () => widget.onDeleteRoom(r),
                    ),
                  )),
          ],
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
  late final UniversityApi _uniApi;
  List<UserModel> _users = [];
  List<Faculty> _faculties = [];
  List<Department> _departments = [];
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
    final client = ApiClient(token: AuthController.to.token);
    _api = UserApi(client);
    _uniApi = UniversityApi(client);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Load the three independently: a failure in one (e.g. the user list) must
    // not blank the faculty/department pickers used by the Add User form.
    List<UserModel> users = [];
    List<Faculty> faculties = [];
    List<Department> departments = [];
    try { users = await _api.getUsers(); } catch (_) {}
    try { faculties = await _uniApi.getFaculties(); } catch (_) {}
    try { departments = await _uniApi.getDepartments(); } catch (_) {}
    if (mounted) {
      setState(() {
        _users = users;
        _faculties = faculties;
        _departments = departments;
        _loading = false;
      });
    }
  }

  Future<void> _showAddSheet() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String selectedRole = _roles.first;
    Faculty? selFaculty;
    Department? selDept;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheet) {
            // A faculty head is tied to a faculty; a lecturer is tied to a department.
            final needsFaculty = selectedRole == 'faculty_head';
            final needsDept = selectedRole == 'lecturer';
            final deptsForFaculty = selFaculty == null
                ? _departments
                : _departments.where((d) => d.facultyId == selFaculty!.id).toList();

            return SingleChildScrollView(child: Column(
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Theme.of(ctx).colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.mark_email_read_outlined,
                          size: 18, color: Theme.of(ctx).colorScheme.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'An activation invite will be emailed to this address. '
                          'The user sets their own password from the link.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                  items: _roles.map((r) => DropdownMenuItem(
                    value: r, child: Text(r.replaceAll('_', ' ')),
                  )).toList(),
                  onChanged: (v) => setSheet(() {
                    selectedRole = v!;
                    selFaculty = null;
                    selDept = null;
                  }),
                ),
                if (needsFaculty || needsDept) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Faculty>(
                    value: selFaculty,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: needsFaculty ? 'Faculty (required)' : 'Faculty',
                      border: const OutlineInputBorder(),
                    ),
                    items: _faculties.map((f) => DropdownMenuItem(
                      value: f, child: Text('${f.code} — ${f.name}'),
                    )).toList(),
                    onChanged: (v) => setSheet(() { selFaculty = v; selDept = null; }),
                  ),
                ],
                if (needsDept) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Department>(
                    value: selDept,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Department (required)', border: OutlineInputBorder()),
                    items: deptsForFaculty.map((d) => DropdownMenuItem(
                      value: d, child: Text('${d.code} — ${d.name}'),
                    )).toList(),
                    onChanged: (v) => setSheet(() => selDept = v),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    if (needsFaculty && selFaculty == null) {
                      Get.snackbar('Faculty required', 'A faculty head must be assigned to a faculty.');
                      return;
                    }
                    if (needsDept && selDept == null) {
                      Get.snackbar('Department required', 'A lecturer must be assigned to a department.');
                      return;
                    }
                    final payload = <String, dynamic>{
                      'full_name': nameCtrl.text.trim(),
                      'email': emailCtrl.text.trim(),
                      'role': selectedRole,
                    };
                    // Stamp the creating admin's university on every new user, so
                    // they all belong to (and are listed under) this university.
                    final adminUniId = AuthController.to.user.value?.universityId;
                    if (adminUniId != null) payload['university_id'] = adminUniId;
                    if (selFaculty != null) {
                      payload['faculty_id'] = selFaculty!.id;
                      payload['university_id'] = selFaculty!.universityId;
                    }
                    if (selDept != null) payload['department_id'] = selDept!.id;
                    try {
                      await _api.createUser(payload);
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _load();
                    } catch (e) {
                      Get.snackbar('Error', 'Failed: $e');
                    }
                  },
                  child: const Text('Create User'),
                ),
              ],
            ));
          },
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

// ─── Semesters & Time Slots Tab ───────────────────────────────────────────────

class _SemestersTab extends StatefulWidget {
  const _SemestersTab();

  @override
  State<_SemestersTab> createState() => _SemestersTabState();
}

class _SemestersTabState extends State<_SemestersTab> {
  late final AcademicApi _api;
  List<Semester> _semesters = [];
  final Map<int, List<TimeSlot>> _slots = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _api = AcademicApi(ApiClient(token: AuthController.to.token));
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sems = await _api.getSemesters();
      final slotResults = await Future.wait(sems.map((s) => _api.getTimeSlots(s.id)));
      setState(() {
        _semesters = sems;
        _slots.clear();
        for (var i = 0; i < sems.length; i++) {
          _slots[sems[i].id] = slotResults[i];
        }
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _addSemester() async {
    final nameCtrl = TextEditingController();
    DateTime? startDate;
    DateTime? endDate;
    int term = 1;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final canAdd = nameCtrl.text.trim().isNotEmpty &&
              startDate != null && endDate != null;
          return AlertDialog(
            title: const Text('Add Semester'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  onChanged: (_) => setS(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    hintText: 'e.g. 2024/2025 First Semester',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(startDate == null ? 'Pick Start Date' : _fmtDate(startDate!)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (d != null) setS(() => startDate = d);
                  },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(endDate == null ? 'Pick End Date' : _fmtDate(endDate!)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: startDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (d != null) setS(() => endDate = d);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: term,
                  decoration: const InputDecoration(
                    labelText: 'Semester of the year',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('First semester')),
                    DropdownMenuItem(value: 2, child: Text('Second semester')),
                  ],
                  onChanged: (v) => setS(() => term = v ?? 1),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: canAdd ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || startDate == null || endDate == null) return;
    try {
      final uid = AuthController.to.user.value?.universityId;
      await _api.createSemester({
        'name': nameCtrl.text.trim(),
        'start_date': _fmtDate(startDate!),
        'end_date': _fmtDate(endDate!),
        'university_id': uid,
        'term': term,
      });
      _load();
    } catch (e) {
      Get.snackbar('Error', 'Failed: $e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _deleteSemester(Semester s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Semester'),
        content: Text('Delete "${s.name}"? This will also delete all its time slots.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.deleteSemester(s.id);
      _load();
    } catch (e) {
      Get.snackbar('Error', 'Failed: $e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _addTimeSlots(int semesterId) async {
    const allDays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
      'Sunday',
    ];
    final selectedDays = <String>{
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
    };
    final starts = <TimeOfDay?>[null];
    final ends = <TimeOfDay?>[null];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          int valid = 0;
          for (var i = 0; i < starts.length; i++) {
            if (starts[i] != null && ends[i] != null) valid++;
          }
          final total = valid * selectedDays.length;

          return AlertDialog(
            title: const Text('Add Time Slots'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Define time ranges once — they are applied to every selected day.',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Day selector
                    const Text('Apply to days',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: allDays.map((d) {
                        final sel = selectedDays.contains(d);
                        return FilterChip(
                          label: Text(d.substring(0, 3),
                              style: const TextStyle(fontSize: 12)),
                          selected: sel,
                          onSelected: (v) => setS(() {
                            if (v) {
                              selectedDays.add(d);
                            } else {
                              selectedDays.remove(d);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Time range rows
                    Row(children: [
                      const Text('Time ranges',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add range',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        onPressed: () => setS(() {
                          starts.add(null);
                          ends.add(null);
                        }),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    ...List.generate(starts.length, (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact),
                            onPressed: () async {
                              final t = await showTimePicker(
                                context: ctx,
                                initialTime:
                                    const TimeOfDay(hour: 7, minute: 30),
                                builder: (c, child) => MediaQuery(
                                  data: MediaQuery.of(c).copyWith(
                                      alwaysUse24HourFormat: true),
                                  child: child!,
                                ),
                              );
                              if (t != null) setS(() => starts[i] = t);
                            },
                            child: Text(
                              starts[i] == null
                                  ? 'Start'
                                  : _fmtTime(starts[i]!),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text('–'),
                        ),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact),
                            onPressed: () async {
                              final t = await showTimePicker(
                                context: ctx,
                                initialTime:
                                    const TimeOfDay(hour: 9, minute: 30),
                                builder: (c, child) => MediaQuery(
                                  data: MediaQuery.of(c).copyWith(
                                      alwaysUse24HourFormat: true),
                                  child: child!,
                                ),
                              );
                              if (t != null) setS(() => ends[i] = t);
                            },
                            child: Text(
                              ends[i] == null ? 'End' : _fmtTime(ends[i]!),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          visualDensity: VisualDensity.compact,
                          onPressed: starts.length > 1
                              ? () => setS(() {
                                    starts.removeAt(i);
                                    ends.removeAt(i);
                                  })
                              : null,
                        ),
                      ]),
                    )),

                    if (total > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Will create $total slot${total == 1 ? '' : 's'}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: total == 0 ? null : () => Navigator.pop(ctx, true),
                child: Text(
                    'Create $total slot${total == 1 ? '' : 's'}'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    final validStarts =
        List.generate(starts.length, (i) => starts[i]).toList();
    final validEnds = List.generate(ends.length, (i) => ends[i]).toList();

    setState(() => _loading = true);
    try {
      for (var i = 0; i < validStarts.length; i++) {
        if (validStarts[i] == null || validEnds[i] == null) continue;
        for (final day in selectedDays) {
          await _api.createTimeSlot({
            'day_of_week': day,
            'start_time': _fmtTime(validStarts[i]!),
            'end_time': _fmtTime(validEnds[i]!),
            'semester_id': semesterId,
          });
        }
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed: $e',
          snackPosition: SnackPosition.BOTTOM);
    }
    _load();
  }

  Future<void> _deleteTimeSlots(List<int> ids) async {
    // Optimistic local update — no loading spinner so cards stay expanded
    setState(() {
      for (final semId in _slots.keys) {
        _slots[semId] = _slots[semId]!.where((s) => !ids.contains(s.id)).toList();
      }
    });
    try {
      for (final id in ids) {
        await _api.deleteTimeSlot(id);
      }
      // Silent background sync
      final sems = await _api.getSemesters();
      final slotResults = await Future.wait(sems.map((s) => _api.getTimeSlots(s.id)));
      if (mounted) {
        setState(() {
          _semesters = sems;
          _slots.clear();
          for (var i = 0; i < sems.length; i++) {
            _slots[sems[i].id] = slotResults[i];
          }
        });
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to delete: $e', snackPosition: SnackPosition.BOTTOM);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSemester,
        icon: const Icon(Icons.add),
        label: const Text('Add Semester'),
      ),
      body: _semesters.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_month_outlined, size: 64, color: cs.outline),
                  const SizedBox(height: 16),
                  Text('No semesters yet', style: TextStyle(color: cs.outline)),
                  const SizedBox(height: 8),
                  Text('Add a semester to start defining time slots.',
                      style: TextStyle(color: cs.outline, fontSize: 12)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: _semesters.length,
              itemBuilder: (_, i) {
                final s = _semesters[i];
                return _SemesterCard(
                  key: ValueKey(s.id),
                  semester: s,
                  slots: _slots[s.id] ?? [],
                  onDelete: () => _deleteSemester(s),
                  onAddSlot: () => _addTimeSlots(s.id),
                  onDeleteSlots: _deleteTimeSlots,
                ).animate(delay: Duration(milliseconds: i * 40)).fadeIn(duration: 200.ms);
              },
            ),
    );
  }
}

class _SemesterCard extends StatefulWidget {
  final Semester semester;
  final List<TimeSlot> slots;
  final VoidCallback onDelete;
  final VoidCallback onAddSlot;
  final Future<void> Function(List<int>) onDeleteSlots;

  const _SemesterCard({
    super.key,
    required this.semester, required this.slots,
    required this.onDelete, required this.onAddSlot,
    required this.onDeleteSlots,
  });

  @override
  State<_SemesterCard> createState() => _SemesterCardState();
}

class _SemesterCardState extends State<_SemesterCard> {
  bool _expanded = false;
  bool _selecting = false;
  final Set<int> _selected = {};

  void _toggleSelect(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _exitSelect() => setState(() { _selecting = false; _selected.clear(); });

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    _exitSelect();
    await widget.onDeleteSlots(ids);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sem = widget.semester;
    final slots = widget.slots;

    final days = kWeekOrder;
    final byDay = <String, List<TimeSlot>>{
      for (final d in days)
        d: slots
            .where((s) => s.dayOfWeek.toLowerCase() == d.toLowerCase())
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime)),
    };
    final activeDays = days.where((d) => (byDay[d] ?? []).isNotEmpty).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          // ── Card header ───────────────────────────────────────────────────
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: sem.isActive ? cs.primaryContainer : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.calendar_month_outlined,
                        size: 20,
                        color: sem.isActive ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(sem.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 15)),
                          ),
                          if (sem.isActive) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('Active',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ]),
                        Text(
                          '${sem.startDate} → ${sem.endDate}  ·  '
                          '${slots.length} slot${slots.length == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 12, color: cs.outline),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onPressed: widget.onAddSlot,
                    tooltip: 'Add Time Slots',
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 20, color: cs.error),
                    onPressed: widget.onDelete,
                    tooltip: 'Delete Semester',
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      color: cs.outline),
                ],
              ),
            ),
          ),

          // ── Expanded slot list ────────────────────────────────────────────
          if (_expanded) ...[
            Divider(color: cs.outlineVariant, height: 1),
            if (slots.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No time slots yet — tap + to add',
                    style: TextStyle(color: cs.outline, fontSize: 13)),
              )
            else ...[
              // Selection toolbar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                child: Row(
                  children: [
                    if (_selecting) ...[
                      Text(
                        _selected.isEmpty
                            ? 'Select slots to delete'
                            : '${_selected.length} selected',
                        style: TextStyle(
                            fontSize: 12,
                            color: _selected.isEmpty ? cs.outline : cs.primary,
                            fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      if (_selected.isNotEmpty)
                        FilledButton.tonalIcon(
                          onPressed: _deleteSelected,
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: Text('Delete ${_selected.length}'),
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.errorContainer,
                            foregroundColor: cs.onErrorContainer,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _exitSelect,
                        style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        child: const Text('Cancel'),
                      ),
                    ] else ...[
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => setState(() => _selecting = true),
                        icon: const Icon(Icons.checklist_outlined, size: 16),
                        label: const Text('Select',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                      ),
                    ],
                  ],
                ),
              ),
              ...activeDays.map((day) {
                final daySlots = byDay[day]!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                      child: Text(day,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: cs.secondary)),
                    ),
                    ...daySlots.map((slot) {
                      final isChecked = _selected.contains(slot.id);
                      return ListTile(
                        contentPadding: EdgeInsets.fromLTRB(
                            _selecting ? 8 : 32, 0, 8, 0),
                        dense: true,
                        leading: _selecting
                            ? Checkbox(
                                value: isChecked,
                                onChanged: (_) => _toggleSelect(slot.id),
                              )
                            : Icon(Icons.schedule_outlined,
                                size: 16, color: cs.outline),
                        title: Text(slot.label,
                            style: const TextStyle(fontSize: 13)),
                        selected: isChecked,
                        selectedTileColor: cs.errorContainer.withAlpha(80),
                        onTap: _selecting
                            ? () => _toggleSelect(slot.id)
                            : null,
                        trailing: _selecting
                            ? null
                            : IconButton(
                                icon: Icon(Icons.delete_outline,
                                    color: cs.error, size: 18),
                                onPressed: () =>
                                    widget.onDeleteSlots([slot.id]),
                              ),
                      );
                    }),
                  ],
                );
              }),
              const SizedBox(height: 8),
            ],
          ],
        ],
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
  List<Map<String, dynamic>> _lecturers = [];
  bool _loading = true;
  String _search = '';
  bool _unassignedOnly = false;
  String? _universityName;

  static const _roomTypes = ['lecture_hall', 'lab', 'outdoor'];

  @override
  void initState() {
    super.initState();
    _api = CourseApi(ApiClient(token: AuthController.to.token));
    _load();
    _loadLecturers();
  }

  Future<void> _loadLecturers() async {
    try {
      final lecturers = await UserApi(ApiClient(token: AuthController.to.token)).getLecturers();
      if (mounted) setState(() => _lecturers = lecturers);
    } catch (_) {}
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
    final user = AuthController.to.user.value;
    final isUniversityAdmin = user?.isUniversityAdmin ?? false;

    if (!isUniversityAdmin) {
      await _showAddSheetForOfficer();
      return;
    }

    // University admin: university-wide requirements only
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final hoursCtrl = TextEditingController(text: '2');
    String selectedType = _roomTypes.first;
    int semester = 1;

    // Load university name for banner
    try {
      final uApi = UniversityApi(ApiClient(token: AuthController.to.token));
      final unis = await uApi.getUniversities();
      final uid = user?.universityId;
      if (uid != null) {
        for (final u in unis) {
          if (u.id == uid) {
            setState(() => _universityName = u.name);
            break;
          }
        }
      }
    } catch (_) {}
    final String universityLabel = _universityName ?? 'your university';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Text('Add Course', style: Theme.of(ctx).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                ]),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.primaryContainer.withAlpha(120),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Theme.of(ctx).colorScheme.primary.withAlpha(60)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          color: Theme.of(ctx).colorScheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You are adding $universityLabel Requirements — courses all students must complete, regardless of faculty or department.',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: Theme.of(ctx).colorScheme.onPrimaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Course Code *',
                      hintText: 'e.g. ENG101',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Course Name *',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: const InputDecoration(
                          labelText: 'Room Type', border: OutlineInputBorder()),
                      items: _roomTypes.map((t) => DropdownMenuItem(
                        value: t, child: Text(t.replaceAll('_', ' ')),
                      )).toList(),
                      onChanged: (v) => setSheet(() => selectedType = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: hoursCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Hrs/week', border: OutlineInputBorder()),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: semester,
                  decoration: const InputDecoration(
                      labelText: 'Semester', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('First semester')),
                    DropdownMenuItem(value: 2, child: Text('Second semester')),
                    DropdownMenuItem(value: 0, child: Text('Both (year-long)')),
                  ],
                  onChanged: (v) => setSheet(() => semester = v ?? 1),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: codeCtrl.text.trim().isEmpty ||
                          nameCtrl.text.trim().isEmpty
                      ? null
                      : () async {
                          try {
                            await _api.createCourse({
                              'code': codeCtrl.text.trim(),
                              'name': nameCtrl.text.trim(),
                              'room_type_required': selectedType,
                              'weekly_hours': int.tryParse(hoursCtrl.text) ?? 2,
                              'semester': semester,
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
      ),
    );
  }

  Future<void> _showAddSheetForOfficer() async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final hoursCtrl = TextEditingController(text: '2');
    String selectedType = _roomTypes.first;

    // Load faculty/dept/level data once before opening the sheet
    List<Faculty> faculties = [];
    List<Department> departments = [];
    List<Level> levels = [];
    try {
      final uApi = UniversityApi(ApiClient(token: AuthController.to.token));
      final aApi = AcademicApi(ApiClient(token: AuthController.to.token));
      final results = await Future.wait([
        uApi.getFaculties(), uApi.getDepartments(), aApi.getLevels(),
      ]);
      faculties = results[0] as List<Faculty>;
      departments = results[1] as List<Department>;
      levels = results[2] as List<Level>;
    } catch (e) {
      Get.snackbar('Error', 'Could not load faculties/departments: $e');
      return;
    }

    Faculty? selFaculty;
    Department? selDept;
    Level? selLevel;
    int semester = 1;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheet) {
            final deptOptions = selFaculty == null
                ? <Department>[]
                : departments.where((d) => d.facultyId == selFaculty!.id).toList();
            final levelOptions = selDept == null
                ? <Level>[]
                : levels.where((l) => l.departmentId == selDept!.id).toList();

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Text('Add Course', style: Theme.of(ctx).textTheme.titleLarge),
                    const Spacer(),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx)),
                  ]),
                  const SizedBox(height: 16),

                  // Faculty → Department → Level cascade
                  DropdownButtonFormField<Faculty>(
                    value: selFaculty,
                    decoration: const InputDecoration(
                        labelText: 'Faculty *', border: OutlineInputBorder()),
                    items: faculties.map((f) => DropdownMenuItem(
                      value: f, child: Text('${f.code} — ${f.name}'),
                    )).toList(),
                    onChanged: (v) => setSheet(() {
                      selFaculty = v;
                      selDept = null;
                      selLevel = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Department>(
                    value: selDept,
                    decoration: InputDecoration(
                        labelText: 'Department *',
                        border: const OutlineInputBorder(),
                        enabled: selFaculty != null),
                    items: deptOptions.map((d) => DropdownMenuItem(
                      value: d, child: Text('${d.code} — ${d.name}'),
                    )).toList(),
                    onChanged: selFaculty == null ? null : (v) => setSheet(() {
                      selDept = v;
                      selLevel = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Level>(
                    value: selLevel,
                    decoration: InputDecoration(
                        labelText: 'Level *',
                        border: const OutlineInputBorder(),
                        enabled: selDept != null),
                    items: levelOptions.map((l) => DropdownMenuItem(
                      value: l, child: Text(l.label),
                    )).toList(),
                    onChanged: selDept == null ? null : (v) =>
                        setSheet(() => selLevel = v),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Course Code *',
                        hintText: 'e.g. CSC 201',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Course Name *',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: selectedType,
                        decoration: const InputDecoration(
                            labelText: 'Room Type',
                            border: OutlineInputBorder()),
                        items: _roomTypes.map((t) => DropdownMenuItem(
                          value: t, child: Text(t.replaceAll('_', ' ')),
                        )).toList(),
                        onChanged: (v) => setSheet(() => selectedType = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: hoursCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Hrs/week',
                            border: OutlineInputBorder()),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: semester,
                    decoration: const InputDecoration(
                        labelText: 'Semester', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('First semester')),
                      DropdownMenuItem(value: 2, child: Text('Second semester')),
                      DropdownMenuItem(value: 0, child: Text('Both (year-long)')),
                    ],
                    onChanged: (v) => setSheet(() => semester = v ?? 1),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: selLevel == null ||
                            codeCtrl.text.trim().isEmpty ||
                            nameCtrl.text.trim().isEmpty
                        ? null
                        : () async {
                            try {
                              await _api.createCourse({
                                'code': codeCtrl.text.trim(),
                                'name': nameCtrl.text.trim(),
                                'room_type_required': selectedType,
                                'department_id': selDept!.id,
                                'level_id': selLevel!.id,
                                'weekly_hours':
                                    int.tryParse(hoursCtrl.text) ?? 2,
                                'semester': semester,
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
            );
          },
        ),
      ),
    );
  }

  Future<void> _showAssignLecturerDialog(Course course) async {
    int? selectedId = course.lecturerId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Assign Lecturer — ${course.code}'),
          content: DropdownButtonFormField<int?>(
            value: selectedId,
            decoration: const InputDecoration(
              labelText: 'Lecturer',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Unassigned')),
              ..._lecturers.map((l) => DropdownMenuItem(
                    value: l['id'] as int,
                    child: Text(l['full_name'] as String? ?? ''),
                  )),
            ],
            onChanged: (v) => setS(() => selectedId = v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    try {
      await _api.updateCourseLecturer(course.id, selectedId);
      await _load();
    } catch (e) {
      if (mounted) Get.snackbar('Error', 'Failed: $e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unassignedCount = _courses.where((c) => c.lecturerId == null).length;
    final filtered = _courses.where((c) {
      final matchesSearch =
          c.code.toLowerCase().contains(_search.toLowerCase()) ||
              c.name.toLowerCase().contains(_search.toLowerCase());
      final matchesAssignment = !_unassignedOnly || c.lecturerId == null;
      return matchesSearch && matchesAssignment;
    }).toList();

    if (_loading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                avatar: Icon(
                  _unassignedOnly
                      ? Icons.person_off
                      : Icons.person_off_outlined,
                  size: 18,
                ),
                label: Text('Needs lecturer ($unassignedCount)'),
                selected: _unassignedOnly,
                onSelected: (v) => setState(() => _unassignedOnly = v),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('No courses found.',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      return ListTile(
                        title: Text(
                          '${c.code} — ${c.name}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          c.lecturerId != null
                              ? (_lecturers
                                    .where((l) => l['id'] == c.lecturerId)
                                    .firstOrNull?['full_name'] as String?)
                                  ?? 'Unknown'
                              : 'No lecturer assigned',
                          style: TextStyle(
                            color: c.lecturerId == null
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.outline,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.person_outline, size: 20),
                              tooltip: 'Assign Lecturer',
                              onPressed: () => _showAssignLecturerDialog(c),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  size: 20, color: Theme.of(context).colorScheme.error),
                              tooltip: 'Delete',
                              onPressed: () => _delete(c.id),
                            ),
                          ],
                        ),
                      ).animate(
                              delay: Duration(milliseconds: i * 30))
                          .fadeIn(duration: 200.ms);
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

  // The Lecturer profile id (NOT the user id). Resolved from /lecturers/me.
  int? _lecturerId;

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
      _lecturerId = (await _api.getMyLecturerProfile())['id'] as int;
      final semesters = await _academicApi.getSemesters();
      if (semesters.isNotEmpty) {
        final slots = await _academicApi.getTimeSlots(semesters.first.id);
        _slots = slots;
      }
      _unavailable = await _api.getLecturerAvailability(_lecturerId!);
      _unavailableSlotIds
        ..clear()
        ..addAll(_unavailable.map((e) => e['time_slot_id'] as int));
    } on DioException catch (e) {
      final detail = (e.response?.data as Map?)?['detail'] as String? ??
          'Could not load your availability.';
      Get.snackbar('Error', detail, snackPosition: SnackPosition.BOTTOM);
    } catch (_) {
      // keep empty state on other errors
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_lecturerId == null) {
      Get.snackbar('Error', 'Your lecturer profile is not available yet.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    setState(() => _saving = true);
    try {
      for (final entry in _unavailable) {
        await _api.deleteAvailability(entry['id'] as int);
      }
      for (final slotId in _unavailableSlotIds) {
        await _api.addAvailability(_lecturerId!, slotId);
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

    final days = displayWeekDays(_slots);
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
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)))),
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
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            label: const Text('Save Availability'),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ],
    );
  }

  List<DataRow> _buildRows(
      List<String> days, Map<String, List<TimeSlot>> slotsByDay) {
    final timeLabels = _slots.map((s) => s.label).toSet().toList()..sort();

    return timeLabels.map((label) {
      return DataRow(
        cells: [
          DataCell(Text(label, style: const TextStyle(fontSize: 12))),
          ...days.map((day) {
            final slot = slotsByDay[day]
                ?.where((s) => s.label == label)
                .firstOrNull;
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
                    color: isUnavailable
                        ? Colors.red.shade700
                        : Colors.green.shade700,
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
