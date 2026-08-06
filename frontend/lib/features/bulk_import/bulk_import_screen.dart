import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';

import '../../core/constants.dart';
import '../../core/controllers/auth_controller.dart';

class BulkImportScreen extends StatefulWidget {
  const BulkImportScreen({super.key});

  @override
  State<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends State<BulkImportScreen> {
  String? _fileName;
  Uint8List? _fileBytes;
  bool _uploading = false;
  Map<String, dynamic>? _preview;   // dry-run result awaiting confirm/cancel
  Map<String, dynamic>? _result;    // committed result
  String? _error;

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
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

  /// Send the CSV to the backend. With [dryRun] true it only validates and
  /// returns the preview (nothing is created); false commits the import.
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
        headers: {
          'Authorization': 'Bearer $token',
        },
      ));

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(_fileBytes!, filename: _fileName),
      });

      final response = await dio.post(
        '/users/bulk-import/',
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
      // Surface the backend's friendly message (e.g. wrong columns / not a CSV)
      // rather than the raw exception text.
      final data = e.response?.data;
      final detail = (data is Map) ? data['detail'] as String? : null;
      setState(() => _error =
          detail ?? e.message ?? 'Import failed. Please try again.');
    } catch (e) {
      setState(() => _error = 'Import failed: $e');
    } finally {
      setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return CustomScrollView(
      slivers: [
        const SliverAppBar(pinned: true, title: Text('Bulk Import Lecturers')),
        SliverPadding(
          padding: const EdgeInsets.all(24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Instructions card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.info_outline, color: cs.primary),
                        const SizedBox(width: 10),
                        Text('CSV Format', style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 12),
                      const _CsvFormatRow('name', 'Lecturer full name', required: true),
                      const _CsvFormatRow('email', 'Login email (must be unique)', required: true),
                      const _CsvFormatRow('faculty', 'Faculty name', required: true),
                      const _CsvFormatRow('department', 'Department name', required: true),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Text(
                          'name,email,faculty,department\n'
                          'John Doe,jdoe@ub.cm,Faculty of Engineering and Technology,Computer Engineering\n'
                          'Jane Smith,jsmith@ub.cm,Faculty of Engineering and Technology,Electrical Engineering',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Lecturers are imported into your university. Faculty and '
                        'department are matched by name (case-insensitive). Each '
                        'lecturer is emailed an activation invite to set their own '
                        'password.',
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
                      Text('Upload CSV',
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
                              color: _fileName != null
                                  ? cs.primary
                                  : cs.outlineVariant,
                              width: _fileName != null ? 2 : 1,
                              style: BorderStyle.solid,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: _fileName != null
                                ? cs.primaryContainer.withAlpha(40)
                                : null,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                _fileName != null
                                    ? Icons.check_circle_outline
                                    : Icons.upload_file_outlined,
                                size: 40,
                                color: _fileName != null ? cs.primary : cs.outline,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _fileName ?? 'Click to select a CSV file',
                                style: TextStyle(
                                  color: _fileName != null ? cs.primary : cs.outline,
                                  fontWeight: _fileName != null
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
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
                                  ? null
                                  : () => _runImport(dryRun: true),
                              icon: _uploading
                                  ? const SizedBox(
                                      width: 16, height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.fact_check_outlined,
                                      size: 18),
                              label: Text(_uploading ? 'Checking…' : 'Preview'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: cs.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: cs.error),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_error!,
                            style: TextStyle(color: cs.onErrorContainer))),
                      ],
                    ),
                  ),
                ),
              ],

              // Preview (dry-run) — confirm or cancel before anything is created
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
                          Text('Preview — nothing saved yet',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          'Will create ${(_preview!['created'] as List?)?.length ?? 0}  ·  '
                          'Will skip ${(_preview!['skipped'] as List?)?.length ?? 0}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cs.outline),
                        ),
                        const SizedBox(height: 12),
                        ...(_preview!['created'] as List? ?? []).map((item) {
                          final m = item as Map<String, dynamic>;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(Icons.person_add_alt,
                                    size: 16, color: cs.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(m['name'] as String? ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13)),
                                      Text(
                                          '${m['email']}  ·  ${m['faculty']} / ${m['department']}',
                                          style: TextStyle(
                                              fontSize: 11, color: cs.outline)),
                                    ],
                                  ),
                                ),
                                const Text('will invite',
                                    style: TextStyle(fontSize: 10)),
                              ],
                            ),
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
                            return Text('• ${m['email']} — ${m['reason']}',
                                style: TextStyle(fontSize: 12, color: cs.outline));
                          }),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _uploading
                                    ? null
                                    : () => setState(() => _preview = null),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: (((_preview!['created'] as List?)
                                                ?.isEmpty ??
                                            true) ||
                                        _uploading)
                                    ? null
                                    : () => _runImport(dryRun: false),
                                icon: _uploading
                                    ? const SizedBox(
                                        width: 16, height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.check, size: 18),
                                label: Text(
                                  'Create ${(_preview!['created'] as List?)?.length ?? 0} account'
                                  '${((_preview!['created'] as List?)?.length ?? 0) == 1 ? '' : 's'}',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Results
              if (_result != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withAlpha(80),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withAlpha(80)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.mark_email_read_outlined,
                          color: Theme.of(context).colorScheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Invitations sent to ${(_result!['created'] as List?)?.length ?? 0} '
                          'lecturer${((_result!['created'] as List?)?.length ?? 0) == 1 ? '' : 's'}. '
                          'Each sets their own password from the emailed link.',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Invited ${(_result!['created'] as List?)?.length ?? 0}  ·  '
                  'Skipped ${(_result!['skipped'] as List?)?.length ?? 0}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline),
                ),
                const SizedBox(height: 12),
                ...(_result!['created'] as List? ?? []).map((item) {
                  final m = item as Map<String, dynamic>;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(Icons.person_add_alt,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m['name'] as String? ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                Text(m['email'] as String? ?? '',
                                    style: TextStyle(
                                        color: Theme.of(context).colorScheme.outline,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          Text('invited',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.outline)),
                        ],
                      ),
                    ),
                  );
                }),
                if ((_result!['skipped'] as List?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  Text('Skipped:',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.outline)),
                  const SizedBox(height: 8),
                  ...(_result!['skipped'] as List).map((item) {
                    final m = item as Map<String, dynamic>;
                    return Text('• ${m['email']} — ${m['reason']}',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                            fontSize: 12));
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

class _CsvFormatRow extends StatelessWidget {
  final String column;
  final String description;
  final bool required;
  const _CsvFormatRow(this.column, this.description, {this.required = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(column,
                style: const TextStyle(
                    fontFamily: 'monospace', fontWeight: FontWeight.w600, fontSize: 12)),
          ),
          Expanded(child: Text(description, style: const TextStyle(fontSize: 12))),
          if (required)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('required',
                  style: TextStyle(fontSize: 10, color: Colors.red.shade700)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('optional',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ),
        ],
      ),
    );
  }
}

