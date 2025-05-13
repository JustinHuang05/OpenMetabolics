import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import '../config/api_config.dart';
import '../models/session.dart';
import 'session_details_page.dart';
import '../auth/auth_service.dart';
import 'package:provider/provider.dart';
import 'dart:io' show SocketException;
import 'package:amplify_flutter/amplify_flutter.dart' as amplify;

class PastSessionsPage extends StatefulWidget {
  @override
  _PastSessionsPageState createState() => _PastSessionsPageState();
}

class _PastSessionsPageState extends State<PastSessionsPage> {
  List<SessionSummary> _sessions = [];
  Map<String, bool> _surveyResponses = {};
  bool _isLoading = true;
  String? _errorMessage;
  bool _isNetworkError = false;
  final DateFormat _dateFormat = DateFormat('MMMM d, y');
  final DateFormat _timeFormat = DateFormat('HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _fetchPastSessions();
  }

  Future<void> _fetchPastSessions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isNetworkError = false;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);

      // First try to get user email - this will throw SocketException if no network
      final userEmail = await authService.getCurrentUserEmail();

      // If we get here, we have network connection, now check if user is logged in
      if (userEmail == null) {
        // Check if user is actually signed in
        final isSignedIn = await authService.isSignedIn();
        if (!isSignedIn) {
          throw Exception('User not logged in');
        }
        // If we get here, user is signed in but we couldn't get their email
        throw Exception('Unable to get user information');
      }

      // First get the sessions
      final sessionsResponse = await http.post(
        Uri.parse(ApiConfig.getPastSessionsSummary),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_email': userEmail,
        }),
      );

      if (sessionsResponse.statusCode == 200) {
        final data = jsonDecode(sessionsResponse.body);
        if (mounted) {
          setState(() {
            _sessions = (data['sessions'] as List)
                .map((session) => SessionSummary.fromJson(session))
                .toList();
          });
        }

        // Then check survey responses with the actual session IDs
        final surveyResponse = await http.post(
          Uri.parse(ApiConfig.checkSurveyResponses),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_email': userEmail,
            'session_ids': _sessions.map((s) => s.sessionId).toList(),
          }),
        );

        if (surveyResponse.statusCode == 200) {
          final surveyData = jsonDecode(surveyResponse.body);
          if (mounted) {
            setState(() {
              _surveyResponses =
                  Map<String, bool>.from(surveyData['surveyResponses']);
              _isLoading = false;
            });
          }
        } else {
          final errorData = jsonDecode(surveyResponse.body);
          throw Exception(
              'Failed to check survey responses: ${errorData['error']}${errorData['details'] != null ? '\nDetails: ${errorData['details']}' : ''}');
        }
      } else {
        final errorData = jsonDecode(sessionsResponse.body);
        throw Exception(
            'Failed to fetch past sessions: ${errorData['error']}${errorData['details'] != null ? '\nDetails: ${errorData['details']}' : ''}');
      }
    } on SocketException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isNetworkError = true;
          _errorMessage = 'No internet connection';
        });
      }
    } on amplify.NetworkException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isNetworkError = true;
          _errorMessage = 'No internet connection';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (e.toString().contains('User not logged in')) {
            _errorMessage = 'Please log in to view your past sessions';
          } else if (e.toString().contains('Unable to get user information')) {
            _errorMessage = 'Unable to get user information. Please try again.';
          } else {
            _errorMessage = e.toString();
          }
        });
      }
      print('Error fetching past sessions: $e');
    }
  }

  Future<void> _checkSurveyResponses(String userEmail) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.checkSurveyResponses),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_email': userEmail,
          'session_ids': _sessions.map((s) => s.sessionId).toList(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _surveyResponses = Map<String, bool>.from(data['surveyResponses']);
          });
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
            'Failed to check survey responses: ${errorData['error']}${errorData['details'] != null ? '\nDetails: ${errorData['details']}' : ''}');
      }
    } catch (e) {
      print('Error checking survey responses: $e');
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
      return Center(child: CircularProgressIndicator(color: lightPurple));
    } else if (_isNetworkError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                color: Colors.grey[600],
                size: 64,
              ),
              SizedBox(height: 16),
              Text(
                'No Internet Connection',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Please check your connection and try again',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: _fetchPastSessions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: lightPurple,
                  foregroundColor: textGray,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else if (_errorMessage != null) {
      return Center(
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
                onPressed: _fetchPastSessions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: lightPurple,
                  foregroundColor: textGray,
                ),
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 48,
              color: lightPurple,
            ),
            SizedBox(height: 16),
            Text(
              'No past sessions found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    } else {
      return RefreshIndicator(
        color: lightPurple,
        onRefresh: _fetchPastSessions,
        child: ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: _sessions.length,
          itemBuilder: (context, index) {
            final session = _sessions[index];
            final date = DateTime.parse(session.timestamp);
            final hasFeedback = _surveyResponses[session.sessionId] ?? false;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Card(
                elevation: 2,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SessionDetailsPage(
                          sessionId: session.sessionId,
                          timestamp: session.timestamp,
                        ),
                      ),
                    ).then((_) {
                      // Refresh survey responses when returning from session details
                      _checkSurveyResponses(session.sessionId);
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: textGray, size: 24),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatTimestamp(session.timestamp),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              SizedBox(height: 4),
                              Text(
                                '${session.measurementCount} measurements',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                              ),
                            ],
                          ),
                        ),
                        if (!hasFeedback)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 20,
                            ),
                          ),
                        Icon(Icons.chevron_right, color: Colors.grey[400]),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }
  }
}
