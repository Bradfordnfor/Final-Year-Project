import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/api/api_client.dart';
import '../../core/api/timetable_api.dart';
import '../../core/controllers/auth_controller.dart';
import '../../core/controllers/timetable_controller.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = TimetableController.to.selected.value?.id;
    if (id == null) {
      setState(() { _loading = false; _error = 'no_run'; });
      return;
    }
    try {
      final api = TimetableApi(ApiClient(token: AuthController.to.token));
      final data = await api.getAnalytics(id);
      setState(() { _data = data; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error == 'no_run') {
      return const Center(
        child: Text('No run selected.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    if (_data == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Failed to load analytics'),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return _AnalyticsBody(data: _data!);
  }
}

class _AnalyticsBody extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AnalyticsBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = data['total_entries'] as int? ?? 0;
    final overcapacity = data['overcapacity_count'] as int? ?? 0;
    final rawCounts = data['lecturer_session_counts'] as Map? ?? {};
    final lecturerCounts = rawCounts
        .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats row
          Row(
            children: [
              _StatCard('Total Sessions', '$total',
                  Icons.calendar_month, Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              _StatCard('Overcapacity', '$overcapacity',
                  Icons.warning_amber_rounded, Colors.orange),
            ],
          ).animate().fadeIn(duration: 250.ms),

          // Bar chart
          if (lecturerCounts.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Sessions per Lecturer',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  barGroups: lecturerCounts.entries
                      .toList()
                      .asMap()
                      .entries
                      .map((e) => BarChartGroupData(
                            x: e.key,
                            barRods: [
                              BarChartRodData(
                                toY: e.value.value.toDouble(),
                                color: Theme.of(context).colorScheme.primary,
                                width: 18,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                              ),
                            ],
                          ))
                      .toList(),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true, reservedSize: 28)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (val, _) {
                          final idx = val.toInt();
                          final keys = lecturerCounts.keys.toList();
                          if (idx < 0 || idx >= keys.length) {
                            return const SizedBox.shrink();
                          }
                          return Text('L${idx + 1}',
                              style: const TextStyle(fontSize: 11));
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ).animate().fadeIn(duration: 350.ms, delay: 100.ms),
          ],

          // Overcapacity warning
          if (overcapacity > 0) ...[
            const SizedBox(height: 24),
            Card(
              color: Colors.amber.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.orange.shade200),
              ),
              child: ListTile(
                leading:
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                title: Text(
                    '$overcapacity session(s) exceed room capacity'),
                subtitle: const Text(
                    'View timetable to see highlighted entries'),
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 200.ms),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
