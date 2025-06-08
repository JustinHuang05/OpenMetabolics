import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/session.dart';

// Data class for isolate computation
class ChartDataInput {
  final List<SessionResult> results;
  final double basalRate;

  ChartDataInput(this.results, this.basalRate);
}

class ChartDataOutput {
  final List<FlSpot> spots;
  final List<SessionResult> sortedResults;
  final double maxY;

  ChartDataOutput(this.spots, this.sortedResults, this.maxY);
}

// Function to run in isolate
ChartDataOutput _computeChartData(ChartDataInput input) {
  final sortedResults = List<SessionResult>.from(input.results);
  sortedResults.sort((a, b) => DateTime.parse(a.timestamp)
      .toLocal()
      .compareTo(DateTime.parse(b.timestamp).toLocal()));

  final spots = sortedResults.asMap().entries.map((entry) {
    return FlSpot(
      entry.key.toDouble(),
      entry.value.energyExpenditure,
    );
  }).toList();

  final maxY = spots.isEmpty
      ? 0.0
      : spots.map((spot) => spot.y).reduce((a, b) => a > b ? a : b);

  return ChartDataOutput(spots, sortedResults, maxY);
}

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

class _EnergyExpenditureChartState extends State<EnergyExpenditureChart>
    with SingleTickerProviderStateMixin {
  final dateFormat = DateFormat('HH:mm:ss');
  bool _dataReady = false;
  bool _chartLoaded = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  ChartDataOutput? _chartData;

  @override
  void initState() {
    super.initState();

    // Fade animation controller
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _prepareChart();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _prepareChart() async {
    try {
      // Compute chart data in isolate to avoid blocking UI
      final chartData = await compute(
          _computeChartData, ChartDataInput(widget.results, widget.basalRate));

      if (!mounted) return;

      setState(() {
        _chartData = chartData;
        _dataReady = true;
      });

      // Wait for the chart to be rendered
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _chartLoaded = true;
          });

          // Start fade out animation
          _fadeController.forward();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _chartLoaded = true;
        });
      }
    }
  }

  String _getTimeLabel(double value) {
    if (_chartData == null) return '';
    final index = value.toInt();
    if (index >= 0 && index < _chartData!.sortedResults.length) {
      final timestamp =
          DateTime.parse(_chartData!.sortedResults[index].timestamp).toLocal();
      return dateFormat.format(timestamp);
    }
    return '';
  }

  Widget _buildLoadingSpinner() {
    final Color lightPurple = Color.fromRGBO(216, 194, 251, 1);
    final Color textGray = Color.fromRGBO(66, 66, 66, 1);

    return Card(
      elevation: 2,
      child: Container(
        height: 332,
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: lightPurple),
              SizedBox(height: 16),
              Text(
                'Loading graph...',
                style: TextStyle(
                  color: textGray,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChart() {
    if (_chartData == null || _chartData!.spots.isEmpty) {
      return const SizedBox.shrink();
    }

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
                    reservedSize: 35,
                    getTitlesWidget: (value, meta) {
                      if (value % 5 != 0) return const Text('');
                      return Transform.rotate(
                        angle: -0.785398,
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
              maxX: (_chartData!.spots.length - 1).toDouble(),
              minY: 0,
              maxY: _chartData!.maxY,
              lineBarsData: [
                LineChartBarData(
                  spots: _chartData!.spots,
                  isCurved: false,
                  color: Colors.blue,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: [
                    FlSpot(0, widget.basalRate),
                    FlSpot((_chartData!.spots.length - 1).toDouble(),
                        widget.basalRate),
                  ],
                  isCurved: false,
                  color: Colors.red.withOpacity(0.5),
                  barWidth: 1,
                  dotData: const FlDotData(show: false),
                  dashArray: [5, 5],
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 332,
      child: Stack(
        children: [
          // Chart layer
          if (_dataReady) _buildChart(),

          // Loading overlay
          if (!_chartLoaded)
            AnimatedBuilder(
              animation: _fadeAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: _chartLoaded ? _fadeAnimation.value : 1.0,
                  child: _buildLoadingSpinner(),
                );
              },
            ),
        ],
      ),
    );
  }
}
