import 'package:flutter/material.dart';

class EnergyExpenditureCard extends StatelessWidget {
  final DateTime timestamp;
  final double energyExpenditure;
  final bool isGaitCycle;

  const EnergyExpenditureCard({
    Key? key,
    required this.timestamp,
    required this.energyExpenditure,
    required this.isGaitCycle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0, right: 8.0),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Activity indicator
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isGaitCycle
                        ? Colors.green.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isGaitCycle
                        ? Icons.directions_walk
                        : Icons.accessibility_new,
                    size: 20,
                    color: isGaitCycle ? Colors.green : Colors.grey,
                  ),
                ),
                SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isGaitCycle ? 'Active Movement' : 'Resting State',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isGaitCycle ? Colors.green : Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '${energyExpenditure.toStringAsFixed(2)} W',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        timestamp.toString().split('.')[0],
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
