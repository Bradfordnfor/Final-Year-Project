import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';

import '../../core/controllers/timetable_controller.dart';
import '../../core/routes.dart';

class GenerationScreen extends StatefulWidget {
  const GenerationScreen({super.key});

  @override
  State<GenerationScreen> createState() => _GenerationScreenState();
}

class _GenerationScreenState extends State<GenerationScreen> {
  final _ctrl = TimetableController.to;

  Future<void> _trigger() async {
    final id = _ctrl.selected.value?.id;
    if (id == null) {
      Get.snackbar('No Timetable', 'Select a timetable first from the Timetable screen.');
      return;
    }
    try {
      await _ctrl.generate(id);
    } catch (e) {
      Get.snackbar('Error', 'Failed to start generation: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final timetable = _ctrl.selected.value;
      final status = _ctrl.jobStatus.value;
      final isGenerating = _ctrl.isGenerating.value;
      final conflicts = _ctrl.conflicts;

      if (timetable == null) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_month_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('No timetable selected.',
                  style: TextStyle(color: Colors.grey)),
              SizedBox(height: 8),
              Text('Go to the Timetable screen and select one.',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Timetable info card
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
                        Text('Timetable #${timetable.id}',
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

            // Job status card
            if (status.isNotEmpty) _JobStatusCard(status: status),

            const SizedBox(height: 16),

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

            const Spacer(),

            // Generate button
            FilledButton.icon(
              onPressed: isGenerating ? null : _trigger,
              icon: isGenerating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_fix_high),
              label: Text(isGenerating ? 'Generating…' : 'Generate Timetable'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ).animate().slideY(begin: 0.2, end: 0, duration: 300.ms),

            if (status == 'completed') ...[
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
        ),
      );
    });
  }
}

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
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
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
