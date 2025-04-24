import 'package:flutter/material.dart';
import '../models/session.dart';

class SessionDetailsPage extends StatelessWidget {
  final Session session;

  SessionDetailsPage({required this.session});

  @override
  Widget build(BuildContext context) {
    // Use the actual basal metabolic rate from the session, or calculate it if not available
    final basalRate = session.basalMetabolicRate ??
        session.results
            .map((r) => r.energyExpenditure)
            .reduce((a, b) => a < b ? a : b);

    // Count gait cycles (EE values above basal rate)
    final gaitCycles = session.results
        .where((result) => result.energyExpenditure > basalRate)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Session Details'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Session Date: ${DateTime.parse(session.timestamp).toString().split('.')[0]}',
                  style: Theme.of(context).textTheme.headline6,
                ),
                SizedBox(height: 8),
                Text(
                  'Total Measurements: ${session.results.length}',
                  style: Theme.of(context).textTheme.subtitle1,
                ),
                SizedBox(height: 8),
                Text(
                  'Basal Metabolic Rate: ${basalRate.toStringAsFixed(2)} W${session.basalMetabolicRate == null ? ' (estimated)' : ''}',
                  style: Theme.of(context).textTheme.subtitle1,
                ),
                SizedBox(height: 8),
                Text(
                  'Total Gait Cycles: $gaitCycles',
                  style: Theme.of(context).textTheme.subtitle1,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: session.results.length,
              itemBuilder: (context, index) {
                final result = session.results[index];
                final timestamp = DateTime.parse(result.timestamp);
                final isGaitCycle = result.energyExpenditure > basalRate;
                return ListTile(
                  title: Text(
                      'EE: ${result.energyExpenditure.toStringAsFixed(2)} W'),
                  subtitle: Text(
                      'Time: ${timestamp.toString().split('.')[0]} ${isGaitCycle ? '(Gait Cycle)' : '(Resting)'}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
