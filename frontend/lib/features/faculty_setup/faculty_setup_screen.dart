import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api/api_client.dart';
import '../../core/controllers/auth_controller.dart';

class FacultySetupScreen extends StatefulWidget {
  const FacultySetupScreen({super.key});

  @override
  State<FacultySetupScreen> createState() => _FacultySetupScreenState();
}

class _FacultySetupScreenState extends State<FacultySetupScreen> {
  Map<String, dynamic>? _tree;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTree();
  }

  Future<void> _loadTree() async {
    setState(() { _loading = true; _error = null; });
    try {
      final client = ApiClient(token: AuthController.to.token);
      final response = await client.get('/faculty-setup/tree');
      setState(() {
        _tree = response.data as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addDepartment() async {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Department'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(controller: codeCtrl,
                decoration: const InputDecoration(labelText: 'Code', hintText: 'e.g. CSC')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final client = ApiClient(token: AuthController.to.token);
      await client.post('/faculty-setup/departments', data: {
        'name': nameCtrl.text.trim(),
        'code': codeCtrl.text.trim(),
      });
      _loadTree();
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _addLevel(int deptId) async {
    final numCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Level'),
        content: TextField(
          controller: numCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Level number',
            hintText: 'e.g. 200, 300, 400',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final client = ApiClient(token: AuthController.to.token);
      await client.post('/faculty-setup/levels', data: {
        'number': int.parse(numCtrl.text.trim()),
        'department_id': deptId,
      });
      _loadTree();
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _addClass(int levelId) async {
    final nameCtrl = TextEditingController();
    final popCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Class'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Class name', hintText: 'e.g. EE400')),
            const SizedBox(height: 12),
            TextField(controller: popCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Population')),
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
      final client = ApiClient(token: AuthController.to.token);
      await client.post('/faculty-setup/classes', data: {
        'name': nameCtrl.text.trim(),
        'population': int.parse(popCtrl.text.trim()),
        'level_id': levelId,
      });
      _loadTree();
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _addCourse(int levelId, int deptId) async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String roomType = 'lecture_hall';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Add Course'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: codeCtrl,
                  decoration: const InputDecoration(labelText: 'Code', hintText: 'e.g. CSC 301')),
              const SizedBox(height: 12),
              TextField(controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Course name')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: roomType,
                decoration: const InputDecoration(labelText: 'Room type'),
                items: ['lecture_hall', 'lab', 'studio'].map((t) =>
                    DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' ')))).toList(),
                onChanged: (v) => setS(() => roomType = v ?? 'lecture_hall'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      final client = ApiClient(token: AuthController.to.token);
      await client.post('/faculty-setup/courses', data: {
        'code': codeCtrl.text.trim(),
        'name': nameCtrl.text.trim(),
        'room_type_required': roomType,
        'level_id': levelId,
        'department_id': deptId,
      });
      _loadTree();
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('Faculty Setup'),
            actions: [
              IconButton(onPressed: _loadTree, icon: const Icon(Icons.refresh)),
              FilledButton.tonalIcon(
                onPressed: _loading ? null : _addDepartment,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Department'),
              ),
              const SizedBox(width: 12),
            ],
          ),
          if (_loading)
            const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: cs.error),
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: cs.error)),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _loadTree, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          else if (_tree == null || (_tree!['departments'] as List).isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.school_outlined, size: 64, color: cs.outline),
                    const SizedBox(height: 16),
                    Text('No departments yet',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: cs.outline)),
                    const SizedBox(height: 8),
                    Text('Add departments for your faculty to get started.',
                        style: TextStyle(color: cs.outline)),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _addDepartment,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Department'),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final dept = (_tree!['departments'] as List)[i]
                      as Map<String, dynamic>;
                  return _DepartmentCard(
                    dept: dept,
                    onAddLevel: () => _addLevel(dept['id'] as int),
                    onAddClass: _addClass,
                    onAddCourse: (levelId) =>
                        _addCourse(levelId, dept['id'] as int),
                  );
                },
                childCount: (_tree!['departments'] as List).length,
              ),
            ),
        ],
      ),
    );
  }
}

class _DepartmentCard extends StatefulWidget {
  final Map<String, dynamic> dept;
  final VoidCallback onAddLevel;
  final Future<void> Function(int levelId) onAddClass;
  final Future<void> Function(int levelId) onAddCourse;

  const _DepartmentCard({
    required this.dept, required this.onAddLevel,
    required this.onAddClass, required this.onAddCourse,
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
          // Department header
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ),
                  Text('${levels.length} level${levels.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 12, color: cs.outline)),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onPressed: widget.onAddLevel,
                    tooltip: 'Add Level',
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      color: cs.outline),
                ],
              ),
            ),
          ),
          // Levels
          if (_expanded) ...[
            Divider(color: cs.outlineVariant, height: 1),
            ...levels.map((lvl) {
              final level = lvl as Map<String, dynamic>;
              return _LevelTile(
                level: level,
                onAddClass: () => widget.onAddClass(level['id'] as int),
                onAddCourse: () => widget.onAddCourse(level['id'] as int),
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

class _LevelTile extends StatefulWidget {
  final Map<String, dynamic> level;
  final VoidCallback onAddClass;
  final VoidCallback onAddCourse;

  const _LevelTile({
    required this.level, required this.onAddClass, required this.onAddCourse,
  });

  @override
  State<_LevelTile> createState() => _LevelTileState();
}

class _LevelTileState extends State<_LevelTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final classes = widget.level['classes'] as List? ?? [];
    final courses = widget.level['courses'] as List? ?? [];

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
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${courses.length} course${courses.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 11, color: cs.onTertiaryContainer)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.group_add_outlined, size: 18),
                  onPressed: widget.onAddClass,
                  tooltip: 'Add Class',
                ),
                IconButton(
                  icon: const Icon(Icons.book_outlined, size: 18),
                  onPressed: widget.onAddCourse,
                  tooltip: 'Add Course',
                ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: cs.outline),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          // Classes
          if (classes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(48, 0, 16, 8),
              child: Wrap(
                spacing: 8, runSpacing: 6,
                children: classes.map((c) {
                  final cls = c as Map<String, dynamic>;
                  return Chip(
                    avatar: const Icon(Icons.people_outline, size: 14),
                    label: Text('${cls['name']} (${cls['population']})',
                        style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ),
          // Courses
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
                      style: TextStyle(fontSize: 11, color: cs.onSecondaryContainer,
                          fontWeight: FontWeight.bold)),
                ),
                title: Text(course['name'] as String,
                    style: const TextStyle(fontSize: 13)),
                trailing: _RoomTypeBadge(course['room_type_required'] as String),
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

class _RoomTypeBadge extends StatelessWidget {
  final String type;
  const _RoomTypeBadge(this.type);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      'lab' => ('Lab', Colors.purple),
      'studio' => ('Studio', Colors.teal),
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
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
