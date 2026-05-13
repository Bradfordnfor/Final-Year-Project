import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Add Course'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
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
        subtitle: Text('${faculty.sessionsPerWeek} sessions/week',
            style: TextStyle(
                fontSize: 12,
                color: isSelected ? cs.onPrimaryContainer : cs.outline)),
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

  const _DepartmentCard({
    required this.dept,
    required this.onAddLevel,
    required this.onDeleteDept,
    required this.onAddCourse,
    required this.onDeleteLevel,
    required this.onDeleteCourse,
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

  const _LevelTile({
    required this.level,
    required this.onAddCourse,
    required this.onDeleteLevel,
    required this.onDeleteCourse,
  });

  @override
  State<_LevelTile> createState() => _LevelTileState();
}

class _LevelTileState extends State<_LevelTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final courses = widget.level['courses'] as List? ?? [];
    final population = widget.level['population'] as int? ?? 0;

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
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
                Container(
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
                    Text('$population',
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSecondaryContainer)),
                  ]),
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
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.book_outlined, size: 18),
                  onPressed: widget.onAddCourse,
                  tooltip: 'Add Course',
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
        if (_expanded) ...[
          ...courses.map((co) {
            final course = co as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.fromLTRB(48, 0, 16, 2),
              child: ListTile(
                dense: true,
                leading: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
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
                    _RoomTypeBadge(
                        course['room_type_required'] as String),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 16, color: cs.error),
                      onPressed: () =>
                          widget.onDeleteCourse(course['id'] as int),
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
        Divider(color: cs.outlineVariant, height: 1, indent: 32),
      ],
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
