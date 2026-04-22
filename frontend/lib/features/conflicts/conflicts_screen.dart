import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';

import '../../core/controllers/timetable_controller.dart';
import '../../core/models/timetable.dart';

class ConflictsScreen extends StatefulWidget {
  const ConflictsScreen({super.key});

  @override
  State<ConflictsScreen> createState() => _ConflictsScreenState();
}

class _ConflictsScreenState extends State<ConflictsScreen> {
  final _ctrl = TimetableController.to;

  @override
  void initState() {
    super.initState();
    final id = _ctrl.selected.value?.id;
    if (id != null) _ctrl.loadConflicts(id);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (_ctrl.selected.value == null) {
        return const Center(
          child: Text('No timetable selected.', style: TextStyle(color: Colors.grey)),
        );
      }

      if (_ctrl.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      if (_ctrl.conflicts.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              Text('No unresolved conflicts',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('The timetable is conflict-free.',
                  style: TextStyle(color: Colors.grey)),
            ],
          ).animate().fadeIn(duration: 300.ms),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _ctrl.conflicts.length,
        itemBuilder: (_, i) => _ConflictCard(
          conflict: _ctrl.conflicts[i],
          runId: _ctrl.selected.value!.id,
        )
            .animate(delay: Duration(milliseconds: i * 50))
            .fadeIn(duration: 250.ms)
            .slideY(begin: 0.1, end: 0, curve: Curves.easeOut),
      );
    });
  }
}

class _ConflictCard extends StatelessWidget {
  final TimetableConflict conflict;
  final int runId;
  const _ConflictCard({required this.conflict, required this.runId});

  Map<String, dynamic> _parseDetails(String details) {
    try {
      return jsonDecode(details) as Map<String, dynamic>;
    } catch (_) {
      return {'message': details};
    }
  }

  Future<void> _resolve(BuildContext context, String resolution) async {
    try {
      await TimetableController.to
          .resolveConflict(runId, conflict.id, resolution);
      Get.snackbar(
        'Resolved',
        'Conflict resolved with: ${resolution.replaceAll('_', ' ')}',
        backgroundColor: Colors.green.shade50,
      );
    } catch (e) {
      Get.snackbar('Error', 'Failed: $e',
          backgroundColor: Colors.red.shade50);
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = _parseDetails(conflict.details);
    final message = details['message']?.toString() ?? conflict.details;

    return Card(
      color: Colors.amber.shade50,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    conflict.conflictType.replaceAll('_', ' ').toUpperCase(),
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: Colors.orange.shade800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _resolve(context, 'add_session'),
                    child: const Text('Add Session'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _resolve(context, 'rotate_groups'),
                    child: const Text('Rotate Groups'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
