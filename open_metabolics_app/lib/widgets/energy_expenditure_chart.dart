import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/session.dart';

class EnergyExpenditureChart extends StatefulWidget {
  final List<SessionResult> results;
  final double basalRate;

  const EnergyExpenditureChart({
    Key? key,
    required this.results,
    required this.basalRate,
  }) : super(key: key);

  @override
  State<EnergyExpenditureChart> createState() => _EnergyExpenditureChartState();
}

class _EnergyExpenditureChartState extends State<EnergyExpenditureChart> {
  final dateFormat = DateFormat('HH:mm:ss');

  List<FlSpot> _getSpots() {
    // Sort results by timestamp to match card order
    final sortedResults = List<SessionResult>.from(widget.results);
    sortedResults.sort((a, b) => DateTime.parse(a.timestamp)
        .toLocal()
        .compareTo(DateTime.parse(b.timestamp).toLocal()));

    return sortedResults.asMap().entries.map((entry) {
      return FlSpot(
        entry.key.toDouble(),
        entry.value.energyExpenditure,
      );
    }).toList();
  }

  String _getTimeLabel(double value) {
    final index = value.toInt();
    if (index >= 0 && index < widget.results.length) {
      // Sort results to match the spots
      final sortedResults = List<SessionResult>.from(widget.results);
      sortedResults.sort((a, b) => DateTime.parse(a.timestamp)
          .toLocal()
          .compareTo(DateTime.parse(b.timestamp).toLocal()));

      final timestamp =
          DateTime.parse(sortedResults[index].timestamp).toLocal();
      return dateFormat.format(timestamp);
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final spots = _getSpots();
    if (spots.isEmpty) return const SizedBox.shrink();

    final minY = 0.0; // Energy expenditure cannot be negative
    final maxY = spots.map((spot) => spot.y).reduce((a, b) => a > b ? a : b);
    final range = maxY - minY;
    final padding = range * 0.15; // Increased padding for better visibility

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          height: 300,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  axisNameWidget: const Text(
                    'EE (Watts)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  axisNameSize: 25,
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 10),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  axisNameWidget: const Text(
                    'Time',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  axisNameSize: 25,
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 35, // Increased to accommodate rotated text
                    getTitlesWidget: (value, meta) {
                      if (value % 5 != 0) return const Text('');
                      return Transform.rotate(
                        angle: -0.785398, // -45 degrees in radians
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8.0, right: 15.0),
                          child: Text(
                            _getTimeLabel(value),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: true),
              minX: 0,
              maxX: (spots.length - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              lineBarsData: [
                // Energy expenditure line
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  color: Colors.blue,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
                // Basal rate line
                LineChartBarData(
                  spots: [
                    FlSpot(0, widget.basalRate),
                    FlSpot((spots.length - 1).toDouble(), widget.basalRate),
                  ],
                  isCurved: false,
                  color: Colors.red.withOpacity(0.5),
                  barWidth: 1,
                  dotData: const FlDotData(show: false),
                  dashArray: [5, 5], // Make it a dashed line
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  tooltipBgColor: Colors.blueGrey.withOpacity(0.8),
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final time = _getTimeLabel(spot.x);
                      return LineTooltipItem(
                        '${spot.y.toStringAsFixed(2)} W\n$time',
                        const TextStyle(color: Colors.white),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
