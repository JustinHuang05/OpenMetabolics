import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/session.dart';
import 'session_details_page.dart';

class DaySessionsPage extends StatelessWidget {
  final DateTime selectedDay;
  final List<Map<String, dynamic>> sessions;

  const DaySessionsPage({
    Key? key,
    required this.selectedDay,
    required this.sessions,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final DateFormat dateFormat = DateFormat('MMMM d, y');
    final DateFormat timeFormat = DateFormat('HH:mm:ss');

    return Scaffold(
      appBar: AppBar(
        title: Text(dateFormat.format(selectedDay)),
        backgroundColor: Colors.white,
        foregroundColor: Color.fromRGBO(66, 66, 66, 1),
        elevation: 0,
      ),
      body: sessions.isEmpty
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
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                final timestamp =
                    DateTime.parse(session['timestamp']).toLocal();
                final sessionId = session['sessionId']?.toString() ?? '';
                // Debug print to verify sessionId and surveyResponses keys
                print('Session card: sessionId = ' +
                    sessionId +
                    ', surveyResponses keys = ' +
                    session.keys.join(','));

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
                              sessionId: session['sessionId'],
                              timestamp: session['timestamp'],
                            ),
                          ),
                        );
                      },
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
                                    timeFormat.format(timestamp),
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '${session['measurementCount']} measurements',
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
                            if (!(session['hasSurveyResponse'] ?? false))
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
