import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api/api_client.dart';
import '../../core/api/university_api.dart';
import '../../core/controllers/auth_controller.dart';
import '../../core/models/university.dart';

class UniversitiesScreen extends StatefulWidget {
  const UniversitiesScreen({super.key});

  @override
  State<UniversitiesScreen> createState() => _UniversitiesScreenState();
}

class _UniversitiesScreenState extends State<UniversitiesScreen> {
  List<University> _universities = [];
  bool _loading = true;
  String? _error;

  UniversityApi get _api =>
      UniversityApi(ApiClient(token: AuthController.to.token));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _universities = await _api.getUniversities();
    } catch (e) {
      _error = e.toString();
    }
    setState(() => _loading = false);
  }

  Future<void> _showAddDialog() async {
    final nameCtrl = TextEditingController();
    final slugCtrl = TextEditingController();
    final thresholdCtrl = TextEditingController(text: '0.20');
    final adminNameCtrl = TextEditingController();
    final adminEmailCtrl = TextEditingController();
    final adminPasswordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscure = true;
    Map<String, dynamic>? createdResult;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Add University'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('University Details',
                        style: Theme.of(ctx)
                            .textTheme
                            .labelLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                          labelText: 'University Name',
                          hintText: 'e.g. University of Buea'),
                      validator: (v) =>
                          v?.trim().isEmpty == true ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: slugCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Slug', hintText: 'e.g. ub'),
                      validator: (v) =>
                          v?.trim().isEmpty == true ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: thresholdCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Overflow Threshold'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        final n = double.tryParse(v ?? '');
                        if (n == null || n < 0 || n > 1) {
                          return 'Enter a number between 0 and 1';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text('Admin Account',
                        style: Theme.of(ctx)
                            .textTheme
                            .labelLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'The university admin will use these credentials to log in.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.outline),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: adminNameCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Admin Full Name'),
                      validator: (v) =>
                          v?.trim().isEmpty == true ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: adminEmailCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Admin Email'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) =>
                          v?.trim().isEmpty == true ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: adminPasswordCtrl,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: 'Admin Password',
                        suffixIcon: IconButton(
                          icon: Icon(obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setS(() => obscure = !obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'At least 6 characters'
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    try {
      createdResult = await _api.createUniversityWithAdmin({
        'name': nameCtrl.text.trim(),
        'slug': slugCtrl.text.trim(),
        'overflow_threshold': double.parse(thresholdCtrl.text.trim()),
        'admin_full_name': adminNameCtrl.text.trim(),
        'admin_email': adminEmailCtrl.text.trim(),
        'admin_password': adminPasswordCtrl.text.trim(),
      });
      await _load();
      if (mounted) {
        await _showCreatedConfirmation(createdResult);
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar('Error', e.toString(),
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  Future<void> _showCreatedConfirmation(Map<String, dynamic>? result) async {
    if (result == null) return;
    final email = result['admin_email'] as String;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle,
                color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('University Created'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share these login details with the university admin:',
                style: Theme.of(ctx).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Theme.of(ctx).colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Email: $email',
                      style: const TextStyle(fontFamily: 'monospace')),
                  const SizedBox(height: 4),
                  Text('University: ${result['name']}'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'The admin can change their password after logging in.',
              style: Theme.of(ctx)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(ctx).colorScheme.outline),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _showStructure(University u) async {
    Map<String, dynamic>? structure;
    String? error;
    try {
      structure = await _api.getUniversityStructure(u.id);
    } catch (e) {
      error = e.toString();
    }
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scroll) => _UniversityStructureSheet(
          structure: structure,
          error: error,
          universityName: u.name,
          scrollController: scroll,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(University u) async {
    // Step 1 — show impact
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Theme.of(ctx).colorScheme.error),
            const SizedBox(width: 8),
            const Text('Delete University'),
          ],
        ),
        content: Text(
          'Deleting "${u.name}" will permanently remove all associated '
          'faculties, departments, users, buildings, semesters, and timetable runs.\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true) return;

    // Step 2 — typed-name confirmation
    final inputCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: DefaultTextStyle.of(ctx).style,
                  children: [
                    const TextSpan(text: 'Type '),
                    TextSpan(
                      text: u.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: ' exactly to confirm:'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: inputCtrl,
                autofocus: true,
                decoration:
                    const InputDecoration(hintText: 'University name'),
                onChanged: (_) => setS(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: inputCtrl.text.trim() == u.name.trim()
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Delete Forever'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      await _api.deleteUniversity(u.id);
      await _load();
    } catch (e) {
      if (mounted) {
        Get.snackbar('Error', e.toString(),
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.account_balance_outlined, color: cs.primary, size: 20),
            const SizedBox(width: 8),
            const Text('Universities'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add University'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: cs.error),
                      const SizedBox(height: 12),
                      Text('Failed to load',
                          style: TextStyle(color: cs.error)),
                      const SizedBox(height: 8),
                      FilledButton(
                          onPressed: _load,
                          child: const Text('Retry')),
                    ],
                  ),
                )
              : _universities.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_balance_outlined,
                              size: 64, color: cs.outline),
                          const SizedBox(height: 16),
                          Text('No universities yet',
                              style:
                                  Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text('Tap + to add the first one.',
                              style: TextStyle(color: cs.outline)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _universities.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final u = _universities[i];
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            leading: CircleAvatar(
                              backgroundColor: cs.primaryContainer,
                              child: Icon(Icons.account_balance,
                                  size: 20, color: cs.primary),
                            ),
                            title: Text(u.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              'Slug: ${u.slug}  ·  Overflow: ${(u.overflowThreshold * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                  color: cs.outline, fontSize: 12),
                            ),
                            onTap: () => _showStructure(u),
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: cs.error),
                              tooltip: 'Delete',
                              onPressed: () => _confirmDelete(u),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

// ── Structure bottom sheet ────────────────────────────────────────────────────

class _UniversityStructureSheet extends StatelessWidget {
  final Map<String, dynamic>? structure;
  final String? error;
  final String universityName;
  final ScrollController scrollController;

  const _UniversityStructureSheet({
    required this.structure,
    required this.error,
    required this.universityName,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load structure: $error',
              style: TextStyle(color: cs.error)),
        ),
      );
    }

    if (structure == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final faculties =
        (structure!['faculties'] as List<dynamic>? ?? []);

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
              Icon(Icons.account_balance_outlined,
                  color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  universityName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold),
                ),
              ),
              Chip(
                label: Text(
                  '${faculties.length} ${faculties.length == 1 ? "faculty" : "faculties"}',
                  style: const TextStyle(fontSize: 11),
                ),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        const Divider(),
        if (faculties.isEmpty)
          Expanded(
            child: Center(
              child: Text('No faculties yet',
                  style: TextStyle(color: cs.outline)),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: faculties.length,
              itemBuilder: (_, i) {
                final f = faculties[i] as Map<String, dynamic>;
                final depts =
                    (f['departments'] as List<dynamic>? ?? []);
                return ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.secondaryContainer,
                    radius: 18,
                    child: Text(
                      (f['code'] as String).substring(0, 1),
                      style: TextStyle(
                          color: cs.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),
                  title: Text(f['name'] as String,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${f['code']}  ·  ${depts.length} dept${depts.length == 1 ? "" : "s"}',
                      style:
                          TextStyle(color: cs.outline, fontSize: 12)),
                  children: depts.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                                56, 0, 16, 12),
                            child: Text('No departments',
                                style: TextStyle(
                                    color: cs.outline,
                                    fontSize: 13)),
                          )
                        ]
                      : depts.map((d) {
                          final dept = d as Map<String, dynamic>;
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.fromLTRB(56, 0, 16, 0),
                            leading: Icon(Icons.folder_outlined,
                                size: 16, color: cs.outline),
                            title: Text(dept['name'] as String,
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(dept['code'] as String,
                                style: TextStyle(
                                    fontSize: 11, color: cs.outline)),
                            dense: true,
                          );
                        }).toList(),
                );
              },
            ),
          ),
      ],
    );
  }
}
