import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';

import '../../core/api/api_client.dart';
import '../../core/controllers/auth_controller.dart';
import '../../core/controllers/timetable_controller.dart';
import '../../core/models/timetable.dart';
import '../../core/routes.dart';

class GenerationScreen extends StatefulWidget {
  const GenerationScreen({super.key});

  @override
  State<GenerationScreen> createState() => _GenerationScreenState();
}

class _GenerationScreenState extends State<GenerationScreen> {
  final _ctrl = TimetableController.to;

  // facultyId → tree map from /faculty-setup/tree?faculty_id=X
  final Map<int, Map<String, dynamic>> _facultyTrees = {};
  bool _loadingTrees = false;
  TimetableRun? _lastLoadedRun;

  // Readiness checklist from /runs/{id}/readiness
  Map<String, dynamic>? _readiness;
  bool _loadingReadiness = false;

  @override
  void initState() {
    super.initState();
    final run = _ctrl.selected.value;
    if (run != null) {
      _loadTrees(run);
      _loadReadiness(run);
    }
    ever(_ctrl.selected, (run) {
      if (run != null && run != _lastLoadedRun) {
        _loadTrees(run);
        _loadReadiness(run);
      }
    });
  }

  Future<void> _loadTrees(TimetableRun run) async {
    setState(() { _loadingTrees = true; _facultyTrees.clear(); });
    _lastLoadedRun = run;
    final client = ApiClient(token: AuthController.to.token);
    for (final fid in run.facultyIds) {
      try {
        final res = await client.get('/faculty-setup/tree?faculty_id=$fid');
        if (mounted) {
          setState(() => _facultyTrees[fid] = res.data as Map<String, dynamic>);
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _loadingTrees = false);
  }

  Future<void> _loadReadiness(TimetableRun run) async {
    setState(() { _loadingReadiness = true; _readiness = null; });
    final client = ApiClient(token: AuthController.to.token);
    try {
      final res = await client.get('/runs/${run.id}/readiness');
      if (mounted) setState(() => _readiness = res.data as Map<String, dynamic>);
    } catch (_) {
      // leave _readiness null; the button stays enabled and the backend guard still applies
    }
    if (mounted) setState(() => _loadingReadiness = false);
  }

  Future<void> _trigger() async {
    final id = _ctrl.selected.value?.id;
    if (id == null) {
      Get.snackbar('No Run Selected', 'Select a timetable run first from the Timetable screen.');
      return;
    }
    try {
      await _ctrl.generate(id);
    } catch (e) {
      Get.snackbar('Error', 'Failed to start generation: $e');
      final run = _ctrl.selected.value;
      if (run != null) _loadReadiness(run); // refresh so the checklist reflects why
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final timetable = _ctrl.selected.value;
      final jobStatus = _ctrl.jobStatus.value;
      final isGenerating = _ctrl.isGenerating.value;
      final conflicts = _ctrl.conflicts;

      if (timetable == null) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_month_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('No run selected.', style: TextStyle(color: Colors.grey)),
              SizedBox(height: 8),
              Text('Go to the Timetable screen and select a run.',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        );
      }

      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Run info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined, size: 36),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(timetable.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      _StatusChip(timetable.status),
                    ],
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 250.ms),

          const SizedBox(height: 16),

          // Faculty preview
          _FacultyPreview(
            facultyIds: timetable.facultyIds,
            trees: _facultyTrees,
            loading: _loadingTrees,
          ).animate().fadeIn(duration: 250.ms, delay: 50.ms),

          const SizedBox(height: 16),

          // Job status
          if (jobStatus.isNotEmpty)
            _JobStatusCard(status: jobStatus).animate().fadeIn(duration: 200.ms, delay: 100.ms),

          if (jobStatus.isNotEmpty) const SizedBox(height: 16),

          // Conflicts warning
          if (conflicts.isNotEmpty)
            Card(
              color: Colors.amber.shade50,
              child: ListTile(
                leading: const Icon(Icons.warning_amber, color: Colors.orange),
                title: Text('${conflicts.length} conflict(s) need your attention'),
                trailing: TextButton(
                  onPressed: () => Get.offAllNamed(AppRoutes.conflicts),
                  child: const Text('Resolve'),
                ),
              ),
            ).animate().fadeIn(duration: 250.ms, delay: 100.ms),

          if (conflicts.isNotEmpty) const SizedBox(height: 16),

          // Readiness checklist
          _ReadinessCard(
            readiness: _readiness,
            loading: _loadingReadiness,
          ).animate().fadeIn(duration: 250.ms, delay: 120.ms),

          const SizedBox(height: 16),

          // Generate button — blocked until the run is ready
          FilledButton.icon(
            onPressed: (isGenerating || _readiness?['ready'] == false) ? null : _trigger,
            icon: isGenerating
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.auto_fix_high),
            label: Text(isGenerating ? 'Generating…' : 'Generate Timetable'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ).animate().slideY(begin: 0.2, end: 0, duration: 300.ms),

          if (jobStatus == 'completed') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Get.offAllNamed(AppRoutes.timetable),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('View Timetable'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ],
      );
    });
  }
}

// ─── Faculty preview ─────────────────────────────────────────────────────────

class _FacultyPreview extends StatelessWidget {
  final List<int> facultyIds;
  final Map<int, Map<String, dynamic>> trees;
  final bool loading;

  const _FacultyPreview({
    required this.facultyIds, required this.trees, required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text('Faculties in this run',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold)),
                const Spacer(),
                if (loading)
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (facultyIds.isEmpty)
              Text('No faculties selected', style: TextStyle(color: cs.outline))
            else
              ...facultyIds.map((fid) {
                final tree = trees[fid];
                return _FacultyTreeTile(facultyId: fid, tree: tree);
              }),
          ],
        ),
      ),
    );
  }
}

class _FacultyTreeTile extends StatefulWidget {
  final int facultyId;
  final Map<String, dynamic>? tree;

  const _FacultyTreeTile({required this.facultyId, required this.tree});

  @override
  State<_FacultyTreeTile> createState() => _FacultyTreeTileState();
}

class _FacultyTreeTileState extends State<_FacultyTreeTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tree = widget.tree;

    if (tree == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.hourglass_top_outlined, size: 16, color: cs.outline),
            const SizedBox(width: 8),
            Text('Faculty #${widget.facultyId}',
                style: TextStyle(color: cs.outline, fontSize: 13)),
          ],
        ),
      );
    }

    final depts = tree['departments'] as List? ?? [];
    int totalCourses = 0;
    int totalLevels = 0;
    for (final d in depts) {
      final levels = d['levels'] as List? ?? [];
      totalLevels += levels.length;
      for (final l in levels) {
        totalCourses += (l['courses'] as List? ?? []).length;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(tree['code'] as String,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold,
                          color: cs.onPrimaryContainer)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tree['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                Text('$totalCourses course${totalCourses == 1 ? '' : 's'} · '
                    '$totalLevels level${totalLevels == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 11, color: cs.outline)),
                const SizedBox(width: 4),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: cs.outline),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: depts.map((d) {
                final levels = d['levels'] as List? ?? [];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 2),
                      child: Text(d['name'] as String,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: cs.secondary)),
                    ),
                    ...levels.map((l) {
                      final courses = l['courses'] as List? ?? [];
                      return Padding(
                        padding: const EdgeInsets.only(left: 12, top: 2),
                        child: Row(
                          children: [
                            Icon(Icons.layers_outlined, size: 12, color: cs.outline),
                            const SizedBox(width: 6),
                            Text('Level ${l['number']}  ·  '
                                '${l['population']} students  ·  '
                                '${courses.length} course${courses.length == 1 ? '' : 's'}',
                                style: TextStyle(fontSize: 12, color: cs.onSurface)),
                          ],
                        ),
                      );
                    }),
                  ],
                );
              }).toList(),
            ),
          ),
        Divider(color: cs.outlineVariant, height: 8),
      ],
    );
  }
}

// ─── Readiness checklist ──────────────────────────────────────────────────────

class _ReadinessCard extends StatelessWidget {
  final Map<String, dynamic>? readiness;
  final bool loading;

  const _ReadinessCard({required this.readiness, required this.loading});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (loading) {
      return const Card(
        child: ListTile(
          leading: SizedBox(
            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          title: Text('Checking readiness…'),
        ),
      );
    }
    if (readiness == null) return const SizedBox.shrink();

    final ready = readiness!['ready'] == true;
    final checks = (readiness!['checks'] as List? ?? []).cast<Map<String, dynamic>>();

    return Card(
      color: ready ? Colors.green.shade50 : Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ready ? Icons.verified_outlined : Icons.checklist_outlined,
                    size: 18, color: ready ? Colors.green.shade700 : Colors.orange.shade800),
                const SizedBox(width: 8),
                Text(ready ? 'Ready to generate' : 'Not ready to generate',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ...checks.map((c) {
              final ok = c['ok'] == true;
              final detail = (c['detail'] as String?) ?? '';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(ok ? Icons.check_circle : Icons.cancel,
                        size: 16,
                        color: ok ? Colors.green : cs.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c['label'] as String? ?? '',
                              style: const TextStyle(fontSize: 13)),
                          if (!ok && detail.isNotEmpty)
                            Text(detail,
                                style: TextStyle(fontSize: 12, color: cs.error)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ─── Status widgets ───────────────────────────────────────────────────────────

class _JobStatusCard extends StatelessWidget {
  final String status;
  const _JobStatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (status) {
      'completed' => (Colors.green.shade50, Icons.check_circle, 'Completed'),
      'failed' => (Colors.red.shade50, Icons.error_outline, 'Failed'),
      'running' => (Colors.blue.shade50, Icons.hourglass_top, 'Running…'),
      _ => (Colors.grey.shade100, Icons.schedule, 'Pending'),
    };

    return Card(
      color: color,
      child: ListTile(
        leading: status == 'running'
            ? const SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon),
        title: Text('Status: $label'),
        subtitle: status == 'failed'
            ? const Text('Generation failed. Try again.',
                style: TextStyle(color: Colors.red))
            : null,
      ),
    ).animate().fadeIn(duration: 200.ms);
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'published' => Colors.green,
      'approved' => Theme.of(context).colorScheme.primary,
      'under_review' => Colors.orange,
      _ => Colors.grey,
    };
    return Chip(
      label: Text(
        status.replaceAll('_', ' '),
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
