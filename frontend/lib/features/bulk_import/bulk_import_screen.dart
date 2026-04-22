import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
  Map<String, dynamic>? _result;
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
      _result = null;
      _error = null;
    });
  }

  Future<void> _upload() async {
    if (_fileBytes == null || _fileName == null) return;
    setState(() { _uploading = true; _error = null; _result = null; });

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

      final response = await dio.post('/users/bulk-import/', data: formData);
      setState(() => _result = response.data as Map<String, dynamic>);
    } catch (e) {
      setState(() => _error = e.toString());
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
                      _CsvFormatRow('full_name', 'Lecturer full name', required: true),
                      _CsvFormatRow('email', 'Lecturer email address', required: true),
                      _CsvFormatRow('department_id', 'Department ID (integer)', required: true),
                      _CsvFormatRow('faculty_id', 'Faculty ID (optional)', required: false),
                      _CsvFormatRow('university_id', 'University ID (optional)', required: false),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Text(
                          'full_name,email,department_id,faculty_id\n'
                          'John Doe,jdoe@ub.cm,3,1\n'
                          'Jane Smith,jsmith@ub.cm,3,1',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Each lecturer account will be created with a random temporary password '
                        'which is returned in the response.',
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
                                  : _upload,
                              icon: _uploading
                                  ? const SizedBox(
                                      width: 16, height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.cloud_upload_outlined,
                                      size: 18),
                              label: Text(_uploading ? 'Uploading…' : 'Import'),
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

              // Results
              if (_result != null) ...[
                const SizedBox(height: 20),
                _ResultsCard(result: _result!),
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

class _ResultsCard extends StatelessWidget {
  final Map<String, dynamic> result;
  const _ResultsCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final created = result['created'] as List? ?? [];
    final skipped = result['skipped'] as List? ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.done_all, color: cs.primary),
              const SizedBox(width: 10),
              Text('Import Complete',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _StatBox('Created', created.length.toString(), Colors.green),
              const SizedBox(width: 12),
              _StatBox('Skipped', skipped.length.toString(), Colors.orange),
            ]),
            if (created.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Created accounts', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              ...created.map((item) {
                final m = item as Map<String, dynamic>;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m['full_name'] as String,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(m['email'] as String,
                                style: TextStyle(fontSize: 12, color: cs.outline)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Temp password:',
                              style: TextStyle(fontSize: 10, color: cs.outline)),
                          Text(m['temp_password'] as String,
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ],
            if (skipped.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Skipped', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              ...skipped.map((item) {
                final m = item as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.skip_next, size: 16, color: cs.outline),
                      const SizedBox(width: 8),
                      Text(m['email'] as String),
                      const SizedBox(width: 8),
                      Text('— ${m['reason']}',
                          style: TextStyle(fontSize: 12, color: cs.outline)),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatBox(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
