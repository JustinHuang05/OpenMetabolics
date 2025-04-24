import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';
import '../models/session.dart';
import 'session_details_page.dart';
import '../auth/auth_service.dart';
import 'package:provider/provider.dart';

class PastSessionsPage extends StatefulWidget {
  @override
  _PastSessionsPageState createState() => _PastSessionsPageState();
}

class _PastSessionsPageState extends State<PastSessionsPage> {
  List<Session> _sessions = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchPastSessions();
  }

  Future<void> _fetchPastSessions() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userEmail = await authService.getCurrentUserEmail();

      if (userEmail == null) {
        throw Exception('User not logged in');
      }

      final response = await http.post(
        Uri.parse(ApiConfig.getPastSessions),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_email': userEmail,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _sessions = (data['sessions'] as List)
              .map((session) => Session.fromJson(session))
              .toList();
          _isLoading = false;
        });
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
            'Failed to fetch past sessions: ${errorData['error']}${errorData['details'] != null ? '\nDetails: ${errorData['details']}' : ''}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
      print('Error fetching past sessions: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Past Sessions'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
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
                          child: Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _sessions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history,
                            size: 48,
                            color: Colors.grey,
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
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchPastSessions,
                      child: ListView.builder(
                        itemCount: _sessions.length,
                        itemBuilder: (context, index) {
                          final session = _sessions[index];
                          final date = DateTime.parse(session.timestamp);
                          return ListTile(
                            title: Text(
                                'Session ${date.toString().split('.')[0]}'),
                            subtitle:
                                Text('${session.results.length} measurements'),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SessionDetailsPage(
                                    session: session,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
    );
  }
}
