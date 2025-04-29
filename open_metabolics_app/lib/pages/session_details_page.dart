import 'package:flutter/material.dart';
import '../models/session.dart';
import '../widgets/energy_expenditure_card.dart';

class SessionDetailsPage extends StatelessWidget {
  final Session session;

  SessionDetailsPage({required this.session});

  @override
  Widget build(BuildContext context) {
    final Color lightPurple = Color.fromRGBO(216, 194, 251, 1);
    final Color textGray = Color.fromRGBO(66, 66, 66, 1);

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
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title section with icon
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today, color: textGray),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      DateTime.parse(session.timestamp)
                          .toString()
                          .split('.')[0],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            // Stats section
            Card(
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session Statistics',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Total Windows: ${session.results.length}',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Text(
                      'Basal Rate: ${basalRate.toStringAsFixed(2)} W${session.basalMetabolicRate == null ? ' (estimated)' : ''}',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Text(
                      'Gait Cycles: $gaitCycles',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Energy Expenditure Results',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: 8),
            // Results list
            Expanded(
              child: Scrollbar(
                thickness: 8,
                radius: Radius.circular(4),
                thumbVisibility: true,
                child: ListView.builder(
                  itemCount: session.results.length,
                  itemBuilder: (context, index) {
                    final result = session.results[index];
                    final timestamp = DateTime.parse(result.timestamp);
                    final isGaitCycle = result.energyExpenditure > basalRate;

                    return EnergyExpenditureCard(
                      timestamp: timestamp,
                      energyExpenditure: result.energyExpenditure,
                      isGaitCycle: isGaitCycle,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
