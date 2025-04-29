import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/session.dart';
import '../widgets/energy_expenditure_card.dart';
import '../widgets/energy_expenditure_chart.dart';
import '../config/api_config.dart';
import '../auth/auth_service.dart';
import 'package:provider/provider.dart';

class SessionDetailsPage extends StatefulWidget {
  final String sessionId;
  final String timestamp;

  SessionDetailsPage({
    required this.sessionId,
    required this.timestamp,
  });

  @override
  _SessionDetailsPageState createState() => _SessionDetailsPageState();
}

class _SessionDetailsPageState extends State<SessionDetailsPage> {
  Session? _session;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isChartVisible = false;

  @override
  void initState() {
    super.initState();
    _fetchSessionDetails();
  }

  Future<void> _fetchSessionDetails() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userEmail = await authService.getCurrentUserEmail();

      if (userEmail == null) {
        throw Exception('User not logged in');
      }

      final response = await http.post(
        Uri.parse(ApiConfig.getSessionDetails),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_email': userEmail,
          'session_id': widget.sessionId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _session = Session.fromJson(data['session']);
          _isLoading = false;
        });
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
            'Failed to fetch session details: ${errorData['error']}${errorData['details'] != null ? '\nDetails: ${errorData['details']}' : ''}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
      print('Error fetching session details: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color lightPurple = Color.fromRGBO(216, 194, 251, 1);
    final Color textGray = Color.fromRGBO(66, 66, 66, 1);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Session Details', style: TextStyle(color: textGray)),
          backgroundColor: lightPurple,
        ),
        body: Center(
          child: CircularProgressIndicator(color: lightPurple),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Session Details', style: TextStyle(color: textGray)),
          backgroundColor: lightPurple,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 48,
                ),
                SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red),
                ),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _fetchSessionDetails,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: lightPurple,
                    foregroundColor: textGray,
                  ),
                  child: Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_session == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Session Details', style: TextStyle(color: textGray)),
          backgroundColor: lightPurple,
        ),
        body: Center(
          child: Text('No session data available'),
        ),
      );
    }

    // Use the actual basal metabolic rate from the session, or calculate it if not available
    final basalRate = _session!.basalMetabolicRate ??
        _session!.results
            .map((r) => r.energyExpenditure)
            .reduce((a, b) => a < b ? a : b);

    // Count gait cycles (EE values above basal rate)
    final gaitCycles = _session!.results
        .where((result) => result.energyExpenditure > basalRate)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Session Details', style: TextStyle(color: textGray)),
        backgroundColor: lightPurple,
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
                      DateTime.parse(widget.timestamp).toString().split('.')[0],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            // Stats section
            Card(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Session Statistics',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Total Windows: ${_session!.results.length}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Basal Rate: ${basalRate.toStringAsFixed(2)} W${_session!.basalMetabolicRate == null ? ' (estimated)' : ''}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Gait Cycles: $gaitCycles',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            // Replace this section
            Padding(
              padding: EdgeInsets.only(right: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Energy Expenditure Results',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: lightPurple,
                        width: 2,
                      ),
                      color: _isChartVisible ? lightPurple : Colors.transparent,
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      icon: Icon(
                        Icons.bar_chart,
                        color: _isChartVisible ? Colors.white : lightPurple,
                      ),
                      onPressed: () {
                        setState(() {
                          _isChartVisible = !_isChartVisible;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 8),
            if (_isChartVisible) ...[
              EnergyExpenditureChart(
                results: _session!.results,
                basalRate: basalRate,
              ),
              SizedBox(height: 8),
            ],
            // Results list
            Expanded(
              child: Scrollbar(
                thickness: 8,
                radius: Radius.circular(4),
                thumbVisibility: true,
                child: ListView.builder(
                  itemCount: _session!.results.length,
                  itemBuilder: (context, index) {
                    final result = _session!.results[index];
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
