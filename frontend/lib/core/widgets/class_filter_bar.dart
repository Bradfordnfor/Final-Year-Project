import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/university_api.dart';
import '../models/university.dart';

class ClassFilterBar extends StatefulWidget {
  /// Pre-supply faculties to restrict the dropdown (internal timetable).
  /// If null, all faculties are loaded from the API.
  final List<Faculty>? faculties;

  /// Called with the selected class_id when the user taps View,
  /// or null when Clear is tapped.
  final void Function(int? classId) onClassSelected;

  /// Unauthenticated client for public view; authenticated for internal.
  final ApiClient client;

  const ClassFilterBar({
    super.key,
    required this.onClassSelected,
    required this.client,
    this.faculties,
  });

  @override
  State<ClassFilterBar> createState() => _ClassFilterBarState();
}

class _ClassFilterBarState extends State<ClassFilterBar> {
  List<Faculty> _faculties = [];
  List<Department> _departments = [];
  List<Map<String, dynamic>> _levels = [];

  Faculty? _selectedFaculty;
  Department? _selectedDept;
  Map<String, dynamic>? _selectedLevel;

  bool _loadingFaculties = false;
  bool _loadingDepts = false;
  bool _loadingLevels = false;

  @override
  void initState() {
    super.initState();
    if (widget.faculties != null) {
      _faculties = widget.faculties!;
    } else {
      _loadFaculties();
    }
  }

  Future<void> _loadFaculties() async {
    setState(() => _loadingFaculties = true);
    try {
      final faculties = await UniversityApi(widget.client).getFaculties();
      if (mounted) setState(() { _faculties = faculties; _loadingFaculties = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingFaculties = false);
    }
  }

  Future<void> _onFacultySelected(Faculty? f) async {
    setState(() {
      _selectedFaculty = f;
      _selectedDept = null;
      _selectedLevel = null;
      _departments = [];
      _levels = [];
    });
    if (f == null) return;
    setState(() => _loadingDepts = true);
    try {
      final all = await UniversityApi(widget.client).getDepartments();
      if (mounted) {
        setState(() {
          _departments = all.where((d) => d.facultyId == f.id).toList();
          _loadingDepts = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDepts = false);
    }
  }

  Future<void> _onDeptSelected(Department? d) async {
    setState(() {
      _selectedDept = d;
      _selectedLevel = null;
      _levels = [];
    });
    if (d == null) return;
    setState(() => _loadingLevels = true);
    try {
      final resp = await widget.client
          .get('/faculty-setup/public-levels?department_id=${d.id}');
      final levels = (resp.data as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() { _levels = levels; _loadingLevels = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingLevels = false);
    }
  }

  void _clear() {
    setState(() {
      _selectedFaculty = null;
      _selectedDept = null;
      _selectedLevel = null;
      _departments = [];
      _levels = [];
    });
    widget.onClassSelected(null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Faculty
          Expanded(
            child: _loadingFaculties
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<Faculty>(
                    value: _selectedFaculty,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Faculty',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: _faculties
                        .map((f) => DropdownMenuItem(
                              value: f,
                              child: Text(f.code,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: _onFacultySelected,
                  ),
          ),
          const SizedBox(width: 8),
          // Department
          Expanded(
            child: _loadingDepts
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<Department>(
                    value: _selectedDept,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Department',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: _departments
                        .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text(d.code,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: _onDeptSelected,
                  ),
          ),
          const SizedBox(width: 8),
          // Level
          Expanded(
            child: _loadingLevels
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<Map<String, dynamic>>(
                    value: _selectedLevel,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Level',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: _levels
                        .map((l) => DropdownMenuItem(
                              value: l,
                              child: Text('Level ${l['number']}'),
                            ))
                        .toList(),
                    onChanged: (l) => setState(() => _selectedLevel = l),
                  ),
          ),
          const SizedBox(width: 8),
          // View button
          FilledButton(
            onPressed: _selectedLevel != null
                ? () => widget
                    .onClassSelected(_selectedLevel!['class_id'] as int?)
                : null,
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              minimumSize: Size.zero,
            ),
            child: const Text('View'),
          ),
          const SizedBox(width: 4),
          // Clear button
          TextButton(
            onPressed: _clear,
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              minimumSize: Size.zero,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
