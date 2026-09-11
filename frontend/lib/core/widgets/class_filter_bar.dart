import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/university_api.dart';
import '../models/university.dart';

class ClassFilterBar extends StatefulWidget {
  /// Pre-supply faculties to restrict the dropdown (internal timetable).
  /// If null, all faculties are loaded from the API.
  final List<Faculty>? faculties;

  /// Called with the class IDs in the chosen scope when the user taps View:
  /// a single class (faculty+dept+level), every class in a department
  /// (faculty+dept), or every class in a faculty (faculty only). Called with
  /// null when Clear is tapped (show everything).
  final void Function(List<int>? classIds) onScopeSelected;

  /// Unauthenticated client for public view; authenticated for internal.
  final ApiClient client;

  const ClassFilterBar({
    super.key,
    required this.onScopeSelected,
    required this.client,
    this.faculties,
  });

  @override
  State<ClassFilterBar> createState() => _ClassFilterBarState();
}

class _ClassFilterBarState extends State<ClassFilterBar> {
  List<Faculty> _faculties = [];
  List<Department> _departments = [];
  // dept id -> its levels ({id, number, class_id}); cached when a faculty loads.
  Map<int, List<Map<String, dynamic>>> _deptLevels = {};

  Faculty? _selectedFaculty;
  Department? _selectedDept;
  Map<String, dynamic>? _selectedLevel;
  Map<String, dynamic>? _selectedTrackClass; // one class of the level, or null = whole level

  bool _loadingFaculties = false;
  bool _loadingDepts = false;

  List<Map<String, dynamic>> get _levels =>
      _selectedDept == null ? [] : (_deptLevels[_selectedDept!.id] ?? []);

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
      if (mounted) {
        setState(() {
          _faculties = faculties;
          _loadingFaculties = false;
        });
      }
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
      _deptLevels = {};
    });
    if (f == null) return;
    setState(() => _loadingDepts = true);
    try {
      final all = await UniversityApi(widget.client).getDepartments();
      final depts = all.where((d) => d.facultyId == f.id).toList();
      // Pre-fetch every department's levels so a faculty-wide or
      // department-wide scope can be built without further requests.
      final deptLevels = <int, List<Map<String, dynamic>>>{};
      await Future.wait(depts.map((d) async {
        try {
          final resp = await widget.client
              .get('/faculty-setup/public-levels?department_id=${d.id}');
          deptLevels[d.id] = (resp.data as List).cast<Map<String, dynamic>>();
        } catch (_) {
          deptLevels[d.id] = [];
        }
      }));
      if (mounted) {
        setState(() {
          _departments = depts;
          _deptLevels = deptLevels;
          _loadingDepts = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDepts = false);
    }
  }

  void _onDeptSelected(Department? d) {
    setState(() {
      _selectedDept = d;
      _selectedLevel = null;
      _selectedTrackClass = null;
    });
  }

  /// A level's specialization tracks (classes with a non-null track).
  List<Map<String, dynamic>> _tracksOf(Map<String, dynamic>? level) {
    if (level == null) return [];
    final classes = (level['classes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return classes.where((c) => (c['track'] as String?) != null).toList();
  }

  /// Every class id at a level — includes all specialization tracks, so a
  /// scoped view never drops one. Falls back to the legacy single `class_id`.
  List<int> _classIdsOf(Map<String, dynamic> level) {
    final ids = (level['class_ids'] as List?)?.whereType<int>().toList();
    if (ids != null && ids.isNotEmpty) return ids;
    final cid = level['class_id'] as int?;
    return cid != null ? [cid] : [];
  }

  /// The class IDs covered by the current selection.
  List<int> _scope() {
    if (_selectedLevel != null) {
      if (_selectedTrackClass != null) {
        return [_selectedTrackClass!['id'] as int];
      }
      return _classIdsOf(_selectedLevel!);
    }
    if (_selectedDept != null) {
      return (_deptLevels[_selectedDept!.id] ?? [])
          .expand(_classIdsOf)
          .toList();
    }
    if (_selectedFaculty != null) {
      return _deptLevels.values
          .expand((ls) => ls)
          .expand(_classIdsOf)
          .toList();
    }
    return [];
  }

  void _clear() {
    setState(() {
      _selectedFaculty = null;
      _selectedDept = null;
      _selectedLevel = null;
      _selectedTrackClass = null;
      _departments = [];
      _deptLevels = {};
    });
    widget.onScopeSelected(null);
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
                              child:
                                  Text(f.code, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: _onFacultySelected,
                  ),
          ),
          const SizedBox(width: 8),
          // Department (optional — leave blank for the whole faculty)
          Expanded(
            child: _loadingDepts
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<Department>(
                    value: _selectedDept,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Dept (all)',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: _departments
                        .map((d) => DropdownMenuItem(
                              value: d,
                              child:
                                  Text(d.code, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged:
                        _selectedFaculty == null ? null : _onDeptSelected,
                  ),
          ),
          const SizedBox(width: 8),
          // Level (optional — leave blank for the whole department)
          Expanded(
            child: DropdownButtonFormField<Map<String, dynamic>>(
              value: _selectedLevel,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Level (all)',
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
              onChanged: _selectedDept == null
                  ? null
                  : (l) => setState(() {
                        _selectedLevel = l;
                        _selectedTrackClass = null;
                      }),
            ),
          ),
          if (_tracksOf(_selectedLevel).isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<Map<String, dynamic>?>(
                value: _selectedTrackClass,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Track (all)',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                items: [
                  const DropdownMenuItem<Map<String, dynamic>?>(
                    value: null, child: Text('All tracks'),
                  ),
                  ..._tracksOf(_selectedLevel).map(
                    (c) => DropdownMenuItem<Map<String, dynamic>?>(
                      value: c, child: Text(c['track'] as String),
                    ),
                  ),
                ],
                onChanged: (c) => setState(() => _selectedTrackClass = c),
              ),
            ),
          ],
          const SizedBox(width: 8),
          // View button — enabled once at least a faculty is chosen
          FilledButton(
            onPressed: _selectedFaculty != null
                ? () => widget.onScopeSelected(_scope())
                : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              minimumSize: Size.zero,
            ),
            child: const Text('View'),
          ),
          const SizedBox(width: 4),
          // Clear button
          TextButton(
            onPressed: _clear,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              minimumSize: Size.zero,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
