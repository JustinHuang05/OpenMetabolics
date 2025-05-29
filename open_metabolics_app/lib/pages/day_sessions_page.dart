import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/session.dart';
import 'session_details_page.dart';

class DaySessionCard extends StatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback onTap;
  final DateFormat timeFormat;

  const DaySessionCard({
    Key? key,
    required this.session,
    required this.onTap,
    required this.timeFormat,
  }) : super(key: key);

  @override
  _DaySessionCardState createState() => _DaySessionCardState();
}

class _DaySessionCardState extends State<DaySessionCard> {
  bool _showErrorIndicator = false;

  @override
  void initState() {
    super.initState();
    _showErrorIndicator = !(widget.session['hasSurveyResponse'] ?? false);
  }

  @override
  void didUpdateWidget(DaySessionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If survey was just completed, animate the indicator out
    final oldHasSurvey = oldWidget.session['hasSurveyResponse'] ?? false;
    final newHasSurvey = widget.session['hasSurveyResponse'] ?? false;

    print(
        'DaySessionCard didUpdateWidget: oldHasSurvey=$oldHasSurvey, newHasSurvey=$newHasSurvey, _showErrorIndicator=$_showErrorIndicator');

    // Animate out if survey was completed OR if we have a survey response but still showing error
    if ((!oldHasSurvey && newHasSurvey && _showErrorIndicator) ||
        (newHasSurvey && _showErrorIndicator)) {
      print('Triggering animation for session ${widget.session['sessionId']}');
      Future.delayed(Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _showErrorIndicator = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final timestamp = DateTime.parse(widget.session['timestamp']).toLocal();

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(Icons.access_time,
                  color: Color.fromRGBO(66, 66, 66, 1), size: 24),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.timeFormat.format(timestamp),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${widget.session['measurementCount']} measurements',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: AnimatedSwitcher(
                  duration: Duration(milliseconds: 600),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: _showErrorIndicator
                      ? Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 20,
                          key: ValueKey('error_icon'),
                        )
                      : SizedBox.shrink(key: ValueKey('no_error')),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

class DaySessionsPage extends StatefulWidget {
  final DateTime selectedDay;
  final List<Map<String, dynamic>> sessions;

  const DaySessionsPage({
    Key? key,
    required this.selectedDay,
    required this.sessions,
  }) : super(key: key);

  @override
  _DaySessionsPageState createState() => _DaySessionsPageState();
}

class _DaySessionsPageState extends State<DaySessionsPage> {
  late List<Map<String, dynamic>> _sessions;

  @override
  void initState() {
    super.initState();
    _sessions = List.from(widget.sessions);
  }

  @override
  Widget build(BuildContext context) {
    final DateFormat dateFormat = DateFormat('MMMM d, y');
    final DateFormat timeFormat = DateFormat('HH:mm:ss');

    return Scaffold(
      appBar: AppBar(
        title: Text(dateFormat.format(widget.selectedDay)),
        backgroundColor: Colors.white,
        foregroundColor: Color.fromRGBO(66, 66, 66, 1),
        elevation: 0,
      ),
      body: _sessions.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_busy,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No sessions on this day',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final session = _sessions[index];
                final sessionId = session['sessionId']?.toString() ?? '';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: DaySessionCard(
                    session: session,
                    timeFormat: timeFormat,
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SessionDetailsPage(
                            sessionId: session['sessionId'],
                            timestamp: session['timestamp'],
                          ),
                        ),
                      );

                      if (result == true) {
                        setState(() {
                          final sessionIndex = _sessions
                              .indexWhere((s) => s['sessionId'] == sessionId);
                          if (sessionIndex != -1) {
                            // Create a completely new Map to ensure widget rebuilding
                            final updatedSession = <String, dynamic>{};
                            updatedSession.addAll(_sessions[sessionIndex]);
                            updatedSession['hasSurveyResponse'] = true;
                            _sessions[sessionIndex] = updatedSession;

                            print(
                                'Updated session ${sessionId} with hasSurveyResponse=true');
                          }
                        });
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}
