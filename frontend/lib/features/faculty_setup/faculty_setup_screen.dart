import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api/academic_api.dart';
import '../../core/api/api_client.dart';
import '../../core/controllers/auth_controller.dart';
import '../../core/models/university.dart';

class FacultySetupScreen extends StatefulWidget {
  const FacultySetupScreen({super.key});

  @override
  State<FacultySetupScreen> createState() => _FacultySetupScreenState();
}

class _FacultySetupScreenState extends State<FacultySetupScreen> {
  late final bool _isSuperAdmin;
  late final bool _isUniversityAdmin;
  late final bool _isFacultyHead;

  List<Faculty> _faculties = [];
  bool _loadingFaculties = false;
  Faculty? _selectedFaculty; // super_admin picker only

  Map<String, dynamic>? _tree;
  bool _loadingTree = false;
  String? _treeError;

  ApiClient get _client => ApiClient(token: AuthController.to.token);

  // Only super_admin needs to pass faculty_id — faculty_head uses their assigned faculty
  String get _fq => _isSuperAdmin && _selectedFaculty != null
      ? '?faculty_id=${_selectedFaculty!.id}'
      : '';

  @override
  void initState() {
    super.initState();
    final user = AuthController.to.user.value;
    _isSuperAdmin = user?.isSuperAdmin ?? false;
    _isUniversityAdmin = user?.isUniversityAdmin ?? false;
    _isFacultyHead = user?.isFacultyHead ?? false;

    if (_isSuperAdmin || _isUniversityAdmin) {
      _loadFaculties();
    } else if (_isFacultyHead) {
      _loadTree();
    }
  }

  // ── Faculty CRUD ─────────────────────────────────────────────────────────────

  Future<void> _loadFaculties() async {
    setState(() => _loadingFaculties = true);
    try {
      final resp = await _client.get('/faculty-setup/faculties');
      if (!mounted) return;
      final loaded = (resp.data as List)
          .map((e) => Faculty.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _faculties = loaded;
        if (_selectedFaculty != null) {
          _selectedFaculty = _faculties.firstWhereOrNull(
              (f) => f.id == _selectedFaculty!.id);
        }
        _loadingFaculties = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFaculties = false);
      Get.snackbar('Error', 'Failed to load faculties',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _addFaculty() async {
    final user = AuthController.to.user.value;
    if (user?.universityId == null) return;
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Faculty'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Faculty name',
                  hintText: 'e.g. Faculty of Engineering and Technology')),
          const SizedBox(height: 12),
          TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(
                  labelText: 'Code', hintText: 'e.g. FET')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (nameCtrl.text.trim().isEmpty || codeCtrl.text.trim().isEmpty) return;
    try {
      await _client.post('/faculties/', data: {
        'name': nameCtrl.text.trim(),
        'code': codeCtrl.text.trim().toUpperCase(),
        'university_id': user!.universityId,
      });
      _loadFaculties();
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<Faculty?> _renameFaculty(Faculty faculty) async {
    final nameCtrl = TextEditingController(text: faculty.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Faculty'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Faculty name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (confirmed != true) return null;
    final newName = nameCtrl.text.trim();
    if (newName.isEmpty) return null;
    try {
      final resp = await _client.put('/faculties/${faculty.id}', data: {
        'name': newName,
        'code': faculty.code,
        'sessions_per_week': faculty.sessionsPerWeek,
        'session_duration_hours': faculty.sessionDurationHours,
        'university_id': faculty.universityId,
      });
      await _loadFaculties();
      return Faculty.fromJson(resp.data as Map<String, dynamic>);
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
      return null;
    }
  }

  Future<void> _deleteFaculty(Faculty faculty) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Faculty'),
        content: Text(
            'Delete "${faculty.name}"? All departments, levels, and courses '
            'within it will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.delete('/faculties/${faculty.id}');
      if (_selectedFaculty?.id == faculty.id) {
        setState(() {
          _selectedFaculty = null;
          _tree = null;
        });
      }
      _loadFaculties();
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  // ── Tree CRUD ─────────────────────────────────────────────────────────────────

  Future<void> _loadTree() async {
    if (_isSuperAdmin && _selectedFaculty == null) return;
    setState(() {
      _loadingTree = true;
      _treeError = null;
    });
    try {
      final resp = await _client.get('/faculty-setup/tree$_fq');
      if (!mounted) return;
      setState(() {
        _tree = resp.data as Map<String, dynamic>;
        _loadingTree = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _treeError = e.toString();
        _loadingTree = false;
      });
    }
  }

  Future<void> _addDepartment() async {
    if (_isSuperAdmin && _selectedFaculty == null) return;
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Department'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(
                  labelText: 'Code', hintText: 'e.g. CSC')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.post('/faculty-setup/departments$_fq', data: {
        'name': nameCtrl.text.trim(),
        'code': codeCtrl.text.trim(),
      });
      _loadTree();
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _deleteDepartment(int deptId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Department'),
        content: const Text(
            'This will permanently delete the department and all its levels and courses.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.delete('/faculty-setup/departments/$deptId$_fq');
      _loadTree();
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _addLevel(int deptId) async {
    final numCtrl = TextEditingController();
    final popCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Level'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: numCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Level number', hintText: 'e.g. 200, 300, 400')),
          const SizedBox(height: 12),
          TextField(
              controller: popCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Student population', hintText: 'e.g. 120')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.post('/faculty-setup/levels$_fq', data: {
        'number': int.parse(numCtrl.text.trim()),
        'department_id': deptId,
        'population': int.tryParse(popCtrl.text.trim()) ?? 0,
      });
      _loadTree();
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _deleteLevel(int levelId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Level'),
        content: const Text(
            'This will permanently delete the level and all its courses.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.delete('/faculty-setup/levels/$levelId$_fq');
      _loadTree();
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _addCourse(int levelId, int deptId) async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String roomType = 'lecture_hall';
    int weeklyHours = 2;
    int semester = 1;
    final Set<int> sharedClassIds = {};
    // Other classes across the faculty that can jointly attend this course.
    final List<Map<String, dynamic>> classOptions = [];
    for (final d in (_tree?['departments'] as List? ?? [])) {
      final dcode = d['code'] as String? ?? '';
      for (final l in (d['levels'] as List? ?? [])) {
        final cid = l['class_id'] as int?;
        if (cid != null && l['id'] != levelId) {
          classOptions.add({'id': cid, 'label': '$dcode ${l['number']}'});
        }
      }
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Add Course'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(
                    labelText: 'Code', hintText: 'e.g. CSC 301')),
            const SizedBox(height: 12),
            TextField(
                controller: nameCtrl,
                decoration:
                    const InputDecoration(labelText: 'Course name')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: roomType,
              decoration: const InputDecoration(labelText: 'Room type'),
              items: ['lecture_hall', 'lab', 'outdoor']
                  .map((t) => DropdownMenuItem(
                      value: t, child: Text(t.replaceAll('_', ' '))))
                  .toList(),
              onChanged: (v) => setS(() => roomType = v ?? 'lecture_hall'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(
                  child: Text('Sessions / week',
                      style: TextStyle(fontSize: 13))),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                visualDensity: VisualDensity.compact,
                onPressed:
                    weeklyHours > 1 ? () => setS(() => weeklyHours--) : null,
              ),
              SizedBox(
                  width: 32,
                  child: Text('$weeklyHours',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16))),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                visualDensity: VisualDensity.compact,
                onPressed:
                    weeklyHours < 7 ? () => setS(() => weeklyHours++) : null,
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: semester,
              decoration: const InputDecoration(labelText: 'Semester'),
              items: const [
                DropdownMenuItem(value: 1, child: Text('First semester')),
                DropdownMenuItem(value: 2, child: Text('Second semester')),
                DropdownMenuItem(value: 0, child: Text('Both (year-long)')),
              ],
              onChanged: (v) => setS(() => semester = v ?? 1),
            ),
            if (classOptions.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Joint with (other classes that take this course)',
                    style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: classOptions.map((c) {
                  final id = c['id'] as int;
                  return FilterChip(
                    label: Text(c['label'] as String,
                        style: const TextStyle(fontSize: 11)),
                    selected: sharedClassIds.contains(id),
                    onSelected: (v) => setS(() {
                      if (v) {
                        sharedClassIds.add(id);
                      } else {
                        sharedClassIds.remove(id);
                      }
                    }),
                  );
                }).toList(),
              ),
            ],
          ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.post('/faculty-setup/courses$_fq', data: {
        'code': codeCtrl.text.trim(),
        'name': nameCtrl.text.trim(),
        'room_type_required': roomType,
        'level_id': levelId,
        'department_id': deptId,
        'weekly_hours': weeklyHours,
        'semester': semester,
        'shared_class_ids': sharedClassIds.toList(),
      });
      _loadTree();
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _deleteCourse(int courseId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Course'),
        content: const Text('Remove this course from the curriculum?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.delete('/faculty-setup/courses/$courseId$_fq');
      _loadTree();
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  // ── Department bottom sheet ───────────────────────────────────────────────────

  Future<void> _showFacultyDepartments(Faculty faculty) async {
    Faculty current = faculty;
    List<Map<String, dynamic>> departments = [];
    bool loading = true;
    String? error;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          if (loading) {
            Future.microtask(() async {
              try {
                final client = ApiClient(token: AuthController.to.token);
                final resp = await client.get(
                    '/faculty-setup/tree?faculty_id=${faculty.id}');
                final tree = resp.data as Map<String, dynamic>;
                final depts = (tree['departments'] as List<dynamic>? ?? []);
                setS(() {
                  departments = depts.cast<Map<String, dynamic>>();
                  loading = false;
                });
              } catch (e) {
                setS(() {
                  error = e.toString();
                  loading = false;
                });
              }
            });
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.5,
            maxChildSize: 0.85,
            builder: (_, scroll) {
              final cs = Theme.of(ctx).colorScheme;
              return Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        Icon(Icons.school_outlined,
                            color: cs.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(current.name,
                                  style: Theme.of(ctx)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                          fontWeight: FontWeight.bold)),
                              Text(faculty.code,
                                  style: TextStyle(
                                      color: cs.outline, fontSize: 12)),
                            ],
                          ),
                        ),
                        if (_isUniversityAdmin)
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: 'Rename Faculty',
                            onPressed: () async {
                              final updated = await _renameFaculty(current);
                              if (updated != null) {
                                setS(() => current = updated);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                  const Divider(),
                  if (loading)
                    const Expanded(
                        child: Center(child: CircularProgressIndicator()))
                  else if (error != null)
                    Expanded(
                        child: Center(
                            child: Text('Error: $error',
                                style: TextStyle(color: cs.error))))
                  else if (departments.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text('No departments in this faculty.',
                            style: TextStyle(color: cs.outline)),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        controller: scroll,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: departments.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final d = departments[i];
                          return ListTile(
                            leading: Icon(Icons.folder_outlined,
                                color: cs.primary),
                            title: Text(d['name'] as String),
                            subtitle: Text(d['code'] as String),
                            dense: true,
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isUniversityAdmin) return _buildFacultyListOnly();
    if (_isFacultyHead) return _buildTreeOnly();
    return _buildSuperAdminView();
  }

  // University admin — manage the faculty list only
  Widget _buildFacultyListOnly() {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('Faculty Management'),
            actions: [
              IconButton(
                  onPressed: _loadFaculties, icon: const Icon(Icons.refresh)),
              FilledButton.tonalIcon(
                onPressed: _addFaculty,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Faculty'),
              ),
              const SizedBox(width: 12),
            ],
          ),
          if (_loadingFaculties)
            const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()))
          else if (_faculties.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.account_balance_outlined,
                      size: 64, color: cs.outline),
                  const SizedBox(height: 16),
                  Text('No faculties yet',
                      style: TextStyle(color: cs.outline)),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _addFaculty,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Faculty'),
                  ),
                ]),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _FacultyTile(
                    faculty: _faculties[i],
                    onTap: () => _showFacultyDepartments(_faculties[i]),
                    onDelete: () => _deleteFaculty(_faculties[i]),
                  ),
                  childCount: _faculties.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Faculty head — their faculty's tree only
  Widget _buildTreeOnly() {
    final cs = Theme.of(context).colorScheme;
    final hasData =
        _tree != null && (_tree!['departments'] as List).isNotEmpty;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('Faculty Setup'),
            actions: [
              IconButton(
                  onPressed: _loadTree, icon: const Icon(Icons.refresh)),
              if (hasData || _tree != null)
                FilledButton.tonalIcon(
                  onPressed: _loadingTree ? null : _addDepartment,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Dept'),
                ),
              const SizedBox(width: 12),
            ],
          ),
          ..._treeSlivers(cs, fullPage: true),
        ],
      ),
    );
  }

  // Super admin — faculty list + picker + tree
  Widget _buildSuperAdminView() {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('Faculty Setup'),
            actions: [
              IconButton(
                onPressed: () {
                  _loadFaculties();
                  if (_selectedFaculty != null) _loadTree();
                },
                icon: const Icon(Icons.refresh),
              ),
              if (_selectedFaculty != null)
                FilledButton.tonalIcon(
                  onPressed: _loadingTree ? null : _addDepartment,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Dept'),
                ),
              const SizedBox(width: 12),
            ],
          ),

          // Faculties section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                Text('Faculties',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addFaculty,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: _loadingFaculties
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()))
                : _faculties.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text('No faculties yet.',
                            style: TextStyle(color: cs.outline)))
                    : Column(
                        children: _faculties
                            .map((f) => _FacultyTile(
                                  faculty: f,
                                  isSelected: _selectedFaculty?.id == f.id,
                                  onTap: () {
                                    setState(() {
                                      _selectedFaculty = f;
                                      _tree = null;
                                    });
                                    _loadTree();
                                  },
                                  onDelete: () => _deleteFaculty(f),
                                ))
                            .toList(),
                      ),
          ),

          const SliverToBoxAdapter(child: Divider()),

          // Faculty data section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Faculty Data',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: DropdownButtonFormField<Faculty>(
                value: _selectedFaculty,
                hint: const Text('Select a faculty to manage its data'),
                decoration: const InputDecoration(
                  labelText: 'Faculty',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
                items: _faculties
                    .map((f) => DropdownMenuItem(
                        value: f, child: Text('${f.code} — ${f.name}')))
                    .toList(),
                onChanged: (f) {
                  setState(() {
                    _selectedFaculty = f;
                    _tree = null;
                  });
                  if (f != null) _loadTree();
                },
              ),
            ),
          ),
          if (_selectedFaculty == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                      'Select a faculty above to manage its departments and courses',
                      style: TextStyle(color: cs.outline),
                      textAlign: TextAlign.center),
                ),
              ),
            )
          else
            ..._treeSlivers(cs, fullPage: false),
        ],
      ),
    );
  }

  // Returns tree content as slivers.
  // fullPage: uses SliverFillRemaining for empty/loading states (faculty head view)
  // !fullPage: uses SliverToBoxAdapter (embedded in super admin view)
  List<Widget> _treeSlivers(ColorScheme cs, {required bool fullPage}) {
    Widget centered(Widget child) => fullPage
        ? SliverFillRemaining(child: Center(child: child))
        : SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(child: child)));

    if (_loadingTree) {
      return [centered(const CircularProgressIndicator())];
    }
    if (_treeError != null) {
      return [
        centered(Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 48, color: cs.error),
          const SizedBox(height: 12),
          Text(_treeError!, style: TextStyle(color: cs.error)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _loadTree, child: const Text('Retry')),
        ]))
      ];
    }
    if (_tree == null || (_tree!['departments'] as List).isEmpty) {
      return [
        centered(Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.school_outlined, size: 64, color: cs.outline),
          const SizedBox(height: 16),
          Text('No departments yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: cs.outline)),
          const SizedBox(height: 8),
          Text('Tap "Add Dept" to get started.',
              style: TextStyle(color: cs.outline)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _addDepartment,
            icon: const Icon(Icons.add),
            label: const Text('Add Department'),
          ),
        ]))
      ];
    }
    final depts = _tree!['departments'] as List;
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final dept = depts[i] as Map<String, dynamic>;
            return _DepartmentCard(
              dept: dept,
              onAddLevel: () => _addLevel(dept['id'] as int),
              onDeleteDept: () => _deleteDepartment(dept['id'] as int),
              onAddCourse: (levelId) =>
                  _addCourse(levelId, dept['id'] as int),
              onDeleteLevel: (levelId) => _deleteLevel(levelId),
              onDeleteCourse: (courseId) => _deleteCourse(courseId),
              onChanged: _loadTree,
            );
          },
          childCount: depts.length,
        ),
      ),
    ];
  }
}

// ── Faculty tile (for admin faculty list) ─────────────────────────────────────

class _FacultyTile extends StatelessWidget {
  final Faculty faculty;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  const _FacultyTile({
    required this.faculty,
    this.isSelected = false,
    this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isSelected ? cs.primaryContainer : null,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? cs.primary : cs.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            faculty.code,
            style: TextStyle(
              color: isSelected ? cs.onPrimary : cs.onPrimaryContainer,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(faculty.name,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isSelected ? cs.onPrimaryContainer : null)),
        onTap: onTap,
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: cs.error, size: 20),
          onPressed: onDelete,
          tooltip: 'Delete faculty',
        ),
      ),
    );
  }
}

// ── Department card ───────────────────────────────────────────────────────────

class _DepartmentCard extends StatefulWidget {
  final Map<String, dynamic> dept;
  final VoidCallback onAddLevel;
  final VoidCallback onDeleteDept;
  final Future<void> Function(int levelId) onAddCourse;
  final void Function(int levelId) onDeleteLevel;
  final void Function(int courseId) onDeleteCourse;
  final VoidCallback onChanged;

  const _DepartmentCard({
    required this.dept,
    required this.onAddLevel,
    required this.onDeleteDept,
    required this.onAddCourse,
    required this.onDeleteLevel,
    required this.onDeleteCourse,
    required this.onChanged,
  });

  @override
  State<_DepartmentCard> createState() => _DepartmentCardState();
}

class _DepartmentCardState extends State<_DepartmentCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final levels = widget.dept['levels'] as List? ?? [];

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        children: [
          InkWell(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.dept['code'] as String,
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.dept['name'] as String,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ),
                  Text('${levels.length} level${levels.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 12, color: cs.outline)),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onPressed: widget.onAddLevel,
                    tooltip: 'Add Level',
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 20, color: cs.error),
                    onPressed: widget.onDeleteDept,
                    tooltip: 'Delete Department',
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      color: cs.outline),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(color: cs.outlineVariant, height: 1),
            ...levels.map((lvl) {
              final level = lvl as Map<String, dynamic>;
              return _LevelTile(
                level: level,
                onAddCourse: () => widget.onAddCourse(level['id'] as int),
                onDeleteLevel: () =>
                    widget.onDeleteLevel(level['id'] as int),
                onDeleteCourse: widget.onDeleteCourse,
                onChanged: widget.onChanged,
              );
            }),
            if (levels.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No levels yet — tap + to add one',
                    style: TextStyle(color: cs.outline, fontSize: 13)),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Level tile ────────────────────────────────────────────────────────────────

class _LevelTile extends StatefulWidget {
  final Map<String, dynamic> level;
  final VoidCallback onAddCourse;
  final VoidCallback onDeleteLevel;
  final void Function(int courseId) onDeleteCourse;
  final VoidCallback onChanged;

  const _LevelTile({
    required this.level,
    required this.onAddCourse,
    required this.onDeleteLevel,
    required this.onDeleteCourse,
    required this.onChanged,
  });

  @override
  State<_LevelTile> createState() => _LevelTileState();
}

class _LevelTileState extends State<_LevelTile> {
  bool _expanded = false;
  late int _population;
  List<Map<String, dynamic>> _groups = [];
  bool _loadingGroups = false;
  int _activeTab = 0; // 0 = Courses, 1 = Lab Groups
  final _newGroupCtrl = TextEditingController();
  bool _addingGroup = false;

  @override
  void initState() {
    super.initState();
    _population = widget.level['population'] as int? ?? 0;
  }

  @override
  void dispose() {
    _newGroupCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    final classId = widget.level['class_id'] as int?;
    if (classId == null) return;
    setState(() => _loadingGroups = true);
    try {
      final groups = await AcademicApi(ApiClient(token: AuthController.to.token))
          .getGroups(classId);
      if (mounted) setState(() { _groups = groups; _loadingGroups = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingGroups = false);
    }
  }

  Future<void> _editPopulation() async {
    final classId = widget.level['class_id'] as int?;
    if (classId == null) return;

    final ctrl = TextEditingController(text: '$_population');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Level ${widget.level['number']} Population'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Number of students',
            border: OutlineInputBorder(),
          ),
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
    );

    if (confirmed != true) return;
    final newPop = int.tryParse(ctrl.text.trim());
    if (newPop == null || newPop < 0) return;

    try {
      final token = AuthController.to.token;
      await AcademicApi(ApiClient(token: token))
          .updateClassPopulation(classId, newPop);
      if (mounted) setState(() => _population = newPop);
    } catch (e) {
      if (mounted) {
        Get.snackbar('Error', 'Failed to update population: $e',
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  List<Map<String, dynamic>> get _classes =>
      (widget.level['classes'] as List? ?? []).cast<Map<String, dynamic>>();

  Future<void> _addTrackClass() async {
    final level = widget.level;
    final nameCtrl = TextEditingController();
    final popCtrl = TextEditingController();
    final trackCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add track — Level ${level['number']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: trackCtrl,
              decoration: const InputDecoration(
                  labelText: 'Track', hintText: 'e.g. Software')),
          const SizedBox(height: 12),
          TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Class name', hintText: 'e.g. CE400 Software')),
          const SizedBox(height: 12),
          TextField(
              controller: popCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Student population', hintText: 'e.g. 120')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (confirmed != true) return;
    final track = trackCtrl.text.trim();
    final name = nameCtrl.text.trim();
    final pop = int.tryParse(popCtrl.text.trim()) ?? 0;
    if (name.isEmpty || track.isEmpty) {
      Get.snackbar('Missing info', 'Track and class name are required',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      await AcademicApi(ApiClient(token: AuthController.to.token)).createClass(
        levelId: level['id'] as int, name: name, population: pop, track: track,
      );
      widget.onChanged();
    } catch (e) {
      Get.snackbar('Error', 'Failed to add track: $e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _deleteTrackClass(int classId, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete class'),
        content: Text('Delete "$label"? This is only allowed if no courses, '
            'shared courses or lab groups still point at it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AcademicApi(ApiClient(token: AuthController.to.token))
          .deleteClass(classId);
      widget.onChanged();
    } catch (e) {
      Get.snackbar('Error', 'Failed to delete class: $e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Widget _buildTrackStrip(ColorScheme cs) {
    final classes = _classes;
    final hasTracks =
        classes.any((c) => (c['track'] as String?) != null) || classes.length > 1;
    if (!hasTracks) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 0, 16, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final c in classes)
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text(
                '${(c['track'] as String?) ?? c['name']} · ${c['population']}',
                style: const TextStyle(fontSize: 11),
              ),
              onDeleted: () => _deleteTrackClass(c['id'] as int,
                  (c['track'] as String?) ?? c['name'] as String),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final courses = widget.level['courses'] as List? ?? [];

    return Column(
      children: [
        InkWell(
          onTap: () {
            final wasExpanded = _expanded;
            setState(() => _expanded = !_expanded);
            if (!wasExpanded) _loadGroups();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 10, 12, 10),
            child: Row(
              children: [
                Icon(Icons.layers_outlined, size: 18, color: cs.secondary),
                const SizedBox(width: 10),
                Text('Level ${widget.level['number']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _editPopulation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.people_outline,
                          size: 12, color: cs.onSecondaryContainer),
                      const SizedBox(width: 4),
                      Text('$_population',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSecondaryContainer)),
                      const SizedBox(width: 4),
                      Icon(Icons.edit_outlined,
                          size: 10, color: cs.onSecondaryContainer),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                      '${courses.length} course${courses.length == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontSize: 11, color: cs.onTertiaryContainer)),
                ),
                if (_groups.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.group_outlined, size: 12, color: cs.onTertiaryContainer),
                      const SizedBox(width: 4),
                      Text('${_groups.length} grp${_groups.length == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 11, color: cs.onTertiaryContainer)),
                    ]),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.call_split, size: 18),
                  onPressed: _addTrackClass,
                  tooltip: 'Add specialization track',
                ),
                IconButton(
                  icon: const Icon(Icons.book_outlined, size: 18),
                  onPressed: widget.onAddCourse,
                  tooltip: 'Add Course',
                ),
                IconButton(
                  icon: const Icon(Icons.group_add_outlined, size: 18),
                  onPressed: () {
                    setState(() {
                      _expanded = true;
                      _activeTab = 1;
                      _addingGroup = true;
                    });
                    if (_groups.isEmpty) _loadGroups();
                  },
                  tooltip: 'Add Group',
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: cs.error),
                  onPressed: widget.onDeleteLevel,
                  tooltip: 'Delete Level',
                ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: cs.outline),
              ],
            ),
          ),
        ),
        _buildTrackStrip(cs),
        if (_expanded) ...[
          // Tab row
          Row(
            children: [
              _TabButton(
                label: 'Courses',
                active: _activeTab == 0,
                onTap: () => setState(() => _activeTab = 0),
              ),
              _TabButton(
                label: 'Lab Groups',
                active: _activeTab == 1,
                onTap: () => setState(() => _activeTab = 1),
              ),
            ],
          ),
          // Courses tab — existing course list, unchanged
          if (_activeTab == 0) ...[
            ...courses.map((co) {
              final course = co as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.fromLTRB(48, 0, 16, 2),
                child: ListTile(
                  dense: true,
                  leading: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(course['code'] as String,
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSecondaryContainer,
                            fontWeight: FontWeight.bold)),
                  ),
                  title: Text(course['name'] as String,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text('${course['weekly_hours'] ?? 2}×/week',
                      style: TextStyle(fontSize: 10, color: cs.outline)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RoomTypeBadge(course['room_type_required'] as String),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 16, color: cs.error),
                        onPressed: () => widget.onDeleteCourse(course['id'] as int),
                        tooltip: 'Delete course',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              );
            }),
            if (courses.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(48, 0, 16, 8),
                child: Text('No courses yet',
                    style: TextStyle(fontSize: 12, color: cs.outline)),
              ),
          ],
          // Lab Groups tab
          if (_activeTab == 1) ...[
            if (_loadingGroups)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              )
            else ...[
              if (_addingGroup)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 8, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newGroupCtrl,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'Group name, e.g. Group A',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.check, size: 18),
                        color: cs.primary,
                        onPressed: () async {
                          final name = _newGroupCtrl.text.trim();
                          if (name.isEmpty) return;
                          final classId = widget.level['class_id'] as int?;
                          if (classId == null) return;
                          try {
                            await AcademicApi(ApiClient(token: AuthController.to.token))
                                .createGroup(name, classId);
                            _newGroupCtrl.clear();
                            setState(() => _addingGroup = false);
                            await _loadGroups();
                          } catch (e) {
                            Get.snackbar('Error', 'Failed: $e', snackPosition: SnackPosition.BOTTOM);
                          }
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.close, size: 18, color: cs.outline),
                        onPressed: () {
                          _newGroupCtrl.clear();
                          setState(() => _addingGroup = false);
                        },
                      ),
                    ],
                  ),
                ),
              if (_groups.isEmpty && !_addingGroup)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 12, 12, 12),
                  child: Text('No groups yet',
                      style: TextStyle(color: cs.outline, fontSize: 13)),
                ),
              ..._groups.map((g) => Padding(
                padding: const EdgeInsets.fromLTRB(32, 2, 12, 2),
                child: Row(
                  children: [
                    Icon(Icons.group_outlined, size: 16, color: cs.secondary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(g['name'] as String,
                        style: const TextStyle(fontSize: 13))),
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 16, color: cs.error),
                      onPressed: () async {
                        try {
                          await AcademicApi(ApiClient(token: AuthController.to.token))
                              .deleteGroup(g['id'] as int);
                          await _loadGroups();
                        } catch (e) {
                          Get.snackbar('Error', 'Failed: $e', snackPosition: SnackPosition.BOTTOM);
                        }
                      },
                    ),
                  ],
                ),
              )),
            ],
          ],
        ],
        Divider(color: cs.outlineVariant, height: 1, indent: 32),
      ],
    );
  }
}

// ── Tab button ────────────────────────────────────────────────────────────────

class _TabButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabButton({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? cs.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? cs.primary : cs.outline,
          ),
        ),
      ),
    );
  }
}

// ── Room type badge ───────────────────────────────────────────────────────────

class _RoomTypeBadge extends StatelessWidget {
  final String type;
  const _RoomTypeBadge(this.type);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      'lab' => ('Lab', Colors.purple),
      'outdoor' => ('Outdoor', Colors.green),
      _ => ('Hall', Colors.blue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
