import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';

import '../../core/constants.dart';
import '../../core/controllers/auth_controller.dart';

class CourseBulkImportScreen extends StatefulWidget {
  const CourseBulkImportScreen({super.key});

  @override
  State<CourseBulkImportScreen> createState() => _CourseBulkImportScreenState();
}

class _CourseBulkImportScreenState extends State<CourseBulkImportScreen> {
  String? _fileName;
  Uint8List? _fileBytes;
  bool _uploading = false;
  Map<String, dynamic>? _preview;
  Map<String, dynamic>? _result;
  String? _error;

  bool get _isFacultyHead =>
      AuthController.to.user.value?.isFacultyHead ?? false;

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    setState(() {
      _fileName = file.name;
      _fileBytes = file.bytes;
      _preview = null;
      _result = null;
      _error = null;
    });
  }

  Future<void> _runImport({required bool dryRun}) async {
    if (_fileBytes == null || _fileName == null) return;
    setState(() {
      _uploading = true;
      _error = null;
      if (dryRun) { _preview = null; _result = null; }
    });
    try {
      final token = AuthController.to.token;
      final dio = Dio(BaseOptions(
        baseUrl: AppConstants.baseUrl,
        headers: {'Authorization': 'Bearer $token'},
      ));
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(_fileBytes!, filename: _fileName),
      });
      final response = await dio.post(
        '/courses/bulk-import/',
        data: formData,
        queryParameters: {'dry_run': dryRun},
      );
      setState(() {
        if (dryRun) {
          _preview = response.data as Map<String, dynamic>;
        } else {
          _result = response.data as Map<String, dynamic>;
          _preview = null;
        }
      });
    } on DioException catch (e) {
      final data = e.response?.data;
      final detail = (data is Map) ? data['detail'] as String? : null;
      setState(() => _error = detail ?? e.message ?? 'Import failed. Please try again.');
    } catch (e) {
      setState(() => _error = 'Import failed: $e');
    } finally {
      setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final createdCount = (_preview?['created'] as List?)?.length ?? 0;

    return CustomScrollView(
      slivers: [
        const SliverAppBar(pinned: true, title: Text('Bulk Import Courses')),
        SliverPadding(
          padding: const EdgeInsets.all(24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Format help (role-aware)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.info_outline, color: cs.primary),
                        const SizedBox(width: 10),
                        Text('File Format (CSV or Excel)',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 12),
                      if (_isFacultyHead) ...const [
                        _FormatRow('code', 'Course code, e.g. CEF440', required: true),
                        _FormatRow('name', 'Course name', required: true),
                        _FormatRow('level', 'Year of study: 200, 300, 400', required: true),
                        _FormatRow('department', 'Department in your faculty; list several with | to share one course', required: true),
                        _FormatRow('semester', '1 or 2 (year-long is university-wide)', required: false),
                        _FormatRow('weekly_hours', 'Hours per week (default 2)', required: false),
                        _FormatRow('room_type', 'lecture_hall / lab / studio', required: false),
                        _FormatRow('lecturer', 'Lecturer name (auto-matched)', required: false),
                        _FormatRow('track', 'Specialization track this course is for (must match a class\'s track at that level); blank = whole level', required: false),
                      ] else ...const [
                        _FormatRow('code', 'Course code, e.g. UB101', required: true),
                        _FormatRow('name', 'Course name', required: true),
                        _FormatRow('weekly_hours', 'Hours per week (default 2)', required: false),
                        _FormatRow('room_type', 'lecture_hall / lab / studio', required: false),
                        _FormatRow('lecturer', 'Lecturer name (auto-matched)', required: false),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Text(
                          _isFacultyHead
                              ? 'code,name,level,department,semester,lecturer,track\n'
                                'CEF440,Internet Programming,400,Computer Engineering,1,Dr. Ateba,\n'
                                'CEF450,Network Security,400,Computer Engineering,1,,Networking\n'
                                'CEF201,Circuits,400,Computer Engineering | Electrical Engineering,1,,\n'
                              : 'code,name,lecturer\n'
                                'UB101,Use of English,\n'
                                'UB102,Civics and Ethics,\n',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12,
                              color: cs.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isFacultyHead
                            ? 'Courses are created in your faculty. Department and '
                              'level are matched by name/number. To share one course '
                              'across departments, list them separated by | (the first '
                              'owns it); it is created once and its other departments\' '
                              'classes are linked. A lecturer name is optional: a clean '
                              'match is assigned, anything else is left to assign manually. '
                              'For a specialization level, set track to the class the course '
                              'is for (e.g. Software / Networking); leave it blank for a course '
                              'the whole level takes.'
                            : 'These are year-long university-wide requirements '
                              '(semester is set automatically). A lecturer name is '
                              'optional and auto-matched.',
                        style: TextStyle(fontSize: 12, color: cs.outline),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // File picker
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Upload File',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: _uploading ? null : _pickFile,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _fileName != null ? cs.primary : cs.outlineVariant,
                              width: _fileName != null ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: _fileName != null
                                ? cs.primaryContainer.withAlpha(40) : null,
                          ),
                          child: Column(children: [
                            Icon(
                              _fileName != null
                                  ? Icons.check_circle_outline
                                  : Icons.upload_file_outlined,
                              size: 40,
                              color: _fileName != null ? cs.primary : cs.outline,
                            ),
                            const SizedBox(height: 12),
                            Text(_fileName ?? 'Click to select a CSV or Excel file',
                                style: TextStyle(
                                  color: _fileName != null ? cs.primary : cs.outline,
                                  fontWeight: _fileName != null
                                      ? FontWeight.w600 : FontWeight.normal,
                                )),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _uploading ? null : _pickFile,
                            child: const Text('Change File'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: (_fileBytes == null || _uploading)
                                ? null : () => _runImport(dryRun: true),
                            icon: _uploading
                                ? const SizedBox(width: 16, height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.fact_check_outlined, size: 18),
                            label: Text(_uploading ? 'Checking...' : 'Preview'),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: cs.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Icon(Icons.error_outline, color: cs.error),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_error!,
                          style: TextStyle(color: cs.onErrorContainer))),
                    ]),
                  ),
                ),
              ],

              // Preview
              if (_preview != null) ...[
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.preview_outlined, color: cs.primary),
                          const SizedBox(width: 10),
                          Text('Preview - nothing saved yet',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          'Will create $createdCount  ·  '
                          'Will skip ${(_preview!['skipped'] as List?)?.length ?? 0}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cs.outline),
                        ),
                        const SizedBox(height: 12),
                        ...(_preview!['created'] as List? ?? []).map((item) {
                          final m = item as Map<String, dynamic>;
                          final note = m['lecturer_note'] as String?;
                          final lecturer = m['lecturer'] as String?;
                          return _PreviewCourseRow(
                            code: m['code'] as String? ?? '',
                            name: m['name'] as String? ?? '',
                            subtitle: [
                              if (m['level'] != null) 'L${m['level']}',
                              (m['semester'] == 0 ? 'Year-long' : 'S${m['semester']}'),
                              if (m['department'] != null) m['department'] as String,
                            ].join('  ·  '),
                            lecturer: lecturer,
                            note: note,
                            sharedWith: (m['shared_with'] as List?)?.cast<String>() ?? const [],
                            sharedNote: m['shared_note'] as String?,
                          );
                        }),
                        if ((_preview!['skipped'] as List?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 12),
                          Text('Will be skipped:',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: cs.outline)),
                          const SizedBox(height: 4),
                          ...(_preview!['skipped'] as List).map((item) {
                            final m = item as Map<String, dynamic>;
                            return Text('• ${m['code']} — ${m['reason']}',
                                style: TextStyle(fontSize: 12, color: cs.outline));
                          }),
                        ],
                        const SizedBox(height: 16),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _uploading
                                  ? null : () => setState(() => _preview = null),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: (createdCount == 0 || _uploading)
                                  ? null : () => _runImport(dryRun: false),
                              icon: _uploading
                                  ? const SizedBox(width: 16, height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check, size: 18),
                              label: Text('Create $createdCount course'
                                  '${createdCount == 1 ? '' : 's'}'),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],

              // Result
              if (_result != null) ...[
                const SizedBox(height: 24),
                Text(
                  'Created ${(_result!['created'] as List?)?.length ?? 0} courses  ·  '
                  'Skipped ${(_result!['skipped'] as List?)?.length ?? 0}',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                ...(_result!['created'] as List? ?? []).map((item) {
                  final m = item as Map<String, dynamic>;
                  return _PreviewCourseRow(
                    code: m['code'] as String? ?? '',
                    name: m['name'] as String? ?? '',
                    subtitle: [
                      if (m['level'] != null) 'L${m['level']}',
                      (m['semester'] == 0 ? 'Year-long' : 'S${m['semester']}'),
                      if (m['department'] != null) m['department'] as String,
                    ].join('  ·  '),
                    lecturer: m['lecturer'] as String?,
                    note: m['lecturer_note'] as String?,
                    sharedWith: (m['shared_with'] as List?)?.cast<String>() ?? const [],
                    sharedNote: m['shared_note'] as String?,
                  );
                }),
                if ((_result!['skipped'] as List?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  Text('Skipped:',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: cs.outline)),
                  const SizedBox(height: 8),
                  ...(_result!['skipped'] as List).map((item) {
                    final m = item as Map<String, dynamic>;
                    return Text('• ${m['code']} — ${m['reason']}',
                        style: TextStyle(color: cs.outline, fontSize: 12));
                  }),
                ],
              ],
            ]),
          ),
        ),
      ],
    );
  }
}

class _PreviewCourseRow extends StatelessWidget {
  final String code;
  final String name;
  final String subtitle;
  final String? lecturer;
  final String? note;
  final List<String> sharedWith;
  final String? sharedNote;
  const _PreviewCourseRow({
    required this.code, required this.name, required this.subtitle,
    this.lecturer, this.note,
    this.sharedWith = const [], this.sharedNote,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Badge: matched (assigned lecturer, no note), ambiguous/unassigned (note).
    final Widget badge;
    if (note == null && (lecturer?.isNotEmpty ?? false)) {
      badge = _Badge(text: 'matched: $lecturer', color: cs.primary);
    } else if (note != null) {
      badge = _Badge(text: note!, color: cs.error);
    } else {
      badge = _Badge(text: 'no lecturer', color: cs.outline);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(Icons.menu_book_outlined, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$code — $name',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(subtitle, style: TextStyle(fontSize: 11, color: cs.outline)),
            if (sharedWith.isNotEmpty)
              Text('shared with: ${sharedWith.join(', ')}',
                  style: TextStyle(fontSize: 11, color: cs.primary)),
            if (sharedNote != null)
              Text(sharedNote!, style: TextStyle(fontSize: 11, color: cs.error)),
          ]),
        ),
        badge,
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, color: color)),
      );
}

class _FormatRow extends StatelessWidget {
  final String column;
  final String description;
  final bool required;
  const _FormatRow(this.column, this.description, {this.required = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 130,
          child: Text(column,
              style: const TextStyle(fontFamily: 'monospace',
                  fontWeight: FontWeight.w600, fontSize: 12)),
        ),
        Expanded(child: Text(description, style: const TextStyle(fontSize: 12))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: required ? Colors.red.shade50 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(required ? 'required' : 'optional',
              style: TextStyle(fontSize: 10,
                  color: required ? Colors.red.shade700 : Colors.grey.shade600)),
        ),
      ]),
    );
  }
}
