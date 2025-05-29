import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import '../models/session.dart';
import '../widgets/energy_expenditure_card.dart';
import '../widgets/energy_expenditure_chart.dart';
import '../config/api_config.dart';
import '../auth/auth_service.dart';
import 'package:provider/provider.dart';
import '../widgets/feedback_bottom_drawer.dart';
import '../widgets/network_error_widget.dart';

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
  bool _hasSurveyResponse = false;
  bool _isSurveyButtonLoading = false;
  Map<String, dynamic>? _surveyResponse;
  final DateFormat _dateFormat = DateFormat('MMMM d, y');
  final DateFormat _timeFormat = DateFormat('HH:mm:ss');
  // Add a ScrollController for the results list
  final ScrollController resultsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchSessionDetails();
  }

  Future<void> _checkSurveyResponse() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userEmail = await authService.getCurrentUserEmail();

      if (userEmail == null) {
        throw Exception('User not logged in');
      }

      final response = await http.post(
        Uri.parse(ApiConfig.getSurveyResponse),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_email': userEmail,
          'session_id': widget.sessionId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Survey response data: $data');
        setState(() {
          _hasSurveyResponse = data['hasResponse'] ?? false;
          if (data['hasResponse'] && data['response'] != null) {
            _surveyResponse = Map<String, dynamic>.from(data['response']);
            print('Set survey response: $_surveyResponse');
          } else {
            _surveyResponse = null;
          }
        });
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
            'Failed to check survey response: ${errorData['error']}${errorData['details'] != null ? '\nDetails: ${errorData['details']}' : ''}');
      }
    } catch (e) {
      print('Error checking survey response: $e');
    }
  }

  Future<void> _fetchSessionDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

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
        // Check for survey response before updating the UI
        await _checkSurveyResponse();
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

  Future<void> _reloadSessionDetails() async {
    setState(() {
      _isSurveyButtonLoading = true;
    });

    try {
      await _fetchSessionDetails();
    } finally {
      if (mounted) {
        setState(() {
          _isSurveyButtonLoading = false;
        });
      }
    }
  }

  String _formatTimestamp(String timestamp) {
    final dateTime = DateTime.parse(timestamp).toLocal();
    return '${_dateFormat.format(dateTime)} at ${_timeFormat.format(dateTime)}';
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
        body: NetworkErrorWidget(
          onRetry: _fetchSessionDetails,
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title section with icon
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today, color: textGray),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _formatTimestamp(widget.timestamp),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
          // Stats section and Survey button in a row
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats Card
                Expanded(
                  child: Card(
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
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
                            'Measurements: ${_session!.results.length}',
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
                ),
                SizedBox(width: 12),
                // Survey Button
                Container(
                  width: 160,
                  child: ElevatedButton(
                    onPressed: _isSurveyButtonLoading
                        ? null
                        : () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              enableDrag: true,
                              isDismissible: true,
                              builder: (context) => DraggableScrollableSheet(
                                initialChildSize: 0.9,
                                minChildSize: 0.5,
                                maxChildSize: 0.95,
                                expand: false,
                                builder: (context, scrollController) {
                                  return FeedbackBottomDrawer(
                                    sessionId: widget.sessionId,
                                    existingResponse: _surveyResponse,
                                    onSurveySubmitted: () {
                                      setState(() {
                                        _hasSurveyResponse = true;
                                      });
                                    },
                                  );
                                },
                              ),
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _hasSurveyResponse ? lightPurple : Colors.red,
                      foregroundColor:
                          _hasSurveyResponse ? textGray : Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      disabledBackgroundColor: _hasSurveyResponse
                          ? lightPurple.withOpacity(0.5)
                          : Colors.red.withOpacity(0.5),
                      disabledForegroundColor: _hasSurveyResponse
                          ? textGray.withOpacity(0.5)
                          : Colors.white.withOpacity(0.5),
                    ),
                    child: _isSurveyButtonLoading
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _hasSurveyResponse ? textGray : Colors.white,
                              ),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _hasSurveyResponse
                                    ? Icons.visibility
                                    : Icons.assignment,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                _hasSurveyResponse
                                    ? 'View/Edit Survey'
                                    : 'Complete Survey',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          // Chart toggle and title
          Padding(
            padding: EdgeInsets.only(left: 16.0, right: 20.0),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: EnergyExpenditureChart(
                results: _session!.results,
                basalRate: basalRate,
              ),
            ),
            SizedBox(height: 8),
          ],
          // Results list
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: Scrollbar(
                controller: resultsScrollController,
                thickness: 8,
                radius: Radius.circular(4),
                thumbVisibility: true,
                interactive: true,
                child: ListView.builder(
                  controller: resultsScrollController,
                  itemExtent: 100.0,
                  padding: EdgeInsets.zero,
                  itemCount: _session!.results.length,
                  itemBuilder: (context, index) {
                    final result = _session!.results[index];
                    final timestamp = DateTime.parse(result.timestamp);
                    final isGaitCycle = result.energyExpenditure > basalRate;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: EnergyExpenditureCard(
                        timestamp: timestamp,
                        energyExpenditure: result.energyExpenditure,
                        isGaitCycle: isGaitCycle,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
