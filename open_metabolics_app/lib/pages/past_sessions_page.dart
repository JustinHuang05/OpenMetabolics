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
import 'package:scrollable_clean_calendar/scrollable_clean_calendar.dart';
import 'package:scrollable_clean_calendar/controllers/clean_calendar_controller.dart';
import 'package:scrollable_clean_calendar/utils/enums.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'day_sessions_page.dart';

class PastSessionsPage extends StatefulWidget {
  @override
  _PastSessionsPageState createState() => _PastSessionsPageState();
}

class _PastSessionsPageState extends State<PastSessionsPage> {
  List<SessionSummary> _sessions = [];
  Map<String, bool> _surveyResponses = {};
  bool _isLoading = true;
  bool _isFetchingMore = false;
  String? _errorMessage;
  bool _isNetworkError = false;
  final DateFormat _dateFormat = DateFormat('MMMM d, y');
  final DateFormat _timeFormat = DateFormat('HH:mm:ss');
  bool _isCalendarView = false;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  bool _hasLoadedListViewData = false;

  // Color definitions
  final Color lightPurple = Color.fromRGBO(216, 194, 251, 1);
  final Color darkPurple = Color.fromRGBO(147, 112, 219, 1);
  final Color textGray = Color.fromRGBO(66, 66, 66, 1);
  final Color darkGray = Color.fromRGBO(44, 44, 44, 1);
  final Color lighterPurple = Color.fromRGBO(235, 222, 255, 1);

  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  bool _hasNextPage = true;
  static const int _pageSize = 10;
  String? _lastSessionId;

  // Instead of _sessions, use a cached list of session dates for the calendar
  List<Map<String, dynamic>> _cachedSessionSummaries = [];

  DateTime get _lastDayOfCurrentMonth {
    final now = DateTime.now();
    final beginningNextMonth = (now.month < 12)
        ? DateTime(now.year, now.month + 1, 1)
        : DateTime(now.year + 1, 1, 1);
    return beginningNextMonth.subtract(const Duration(days: 1));
  }

  DateTime? _getEarliestSessionDate() {
    if (_cachedSessionSummaries.isEmpty) return null;

    DateTime? earliestDate;
    for (var summary in _cachedSessionSummaries) {
      final date = DateTime.parse(summary['timestamp']).toLocal();
      if (earliestDate == null || date.isBefore(earliestDate)) {
        earliestDate = date;
      }
    }
    // Return the first day of the month containing the earliest session
    return earliestDate != null
        ? DateTime(earliestDate.year, earliestDate.month, 1)
        : null;
  }

  late CleanCalendarController calendarController;

  @override
  void initState() {
    super.initState();
    // Initialize with default values first
    calendarController = CleanCalendarController(
      minDate: DateTime(2020, 1, 1),
      maxDate: _lastDayOfCurrentMonth,
      initialFocusDate: DateTime.now(),
      rangeMode: false,
    );
    _initializeHive();
    _loadViewPreference();
    // Load cached data first, then check for updates in background
    _loadCachedSessionSummaries();
    // Remove the redundant fetch since _loadCachedSessionSummaries will handle it
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _saveViewPreference(_isCalendarView);
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        _hasNextPage &&
        !_isLoading &&
        !_isFetchingMore) {
      _fetchPastSessions(page: _currentPage + 1);
    }
  }

  Future<void> _initializeHive() async {
    try {
      if (!Hive.isBoxOpen('user_preferences')) {
        await Hive.openBox('user_preferences');
        print('Opened user_preferences box');
      }
    } catch (e) {
      print('Error initializing Hive box: $e');
    }
  }

  void _updateCalendarController() {
    final earliestDate = _getEarliestSessionDate();
    if (earliestDate != null) {
      calendarController = CleanCalendarController(
        minDate: earliestDate,
        maxDate: _lastDayOfCurrentMonth,
        initialFocusDate: DateTime.now(),
        rangeMode: false,
      );
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _loadCachedSessionSummaries() async {
    try {
      final box = Hive.box('session_summaries');
      final cached = box.get('all_sessions', defaultValue: []);

      if (cached is List && cached.isNotEmpty) {
        print('Loading cached data with ${cached.length} sessions');
        // Properly cast the cached data to the correct type
        final List<Map<String, dynamic>> typedCachedData = cached.map((item) {
          if (item is Map) {
            return Map<String, dynamic>.from(item);
          }
          return <String, dynamic>{};
        }).toList();

        setState(() {
          _cachedSessionSummaries = typedCachedData;
          _isLoading = false;
          // Update sessions list if in list view
          if (!_isCalendarView) {
            _sessions = typedCachedData
                .map((item) => SessionSummary.fromJson(item))
                .whereType<SessionSummary>()
                .toList();
            _hasLoadedListViewData = true;
          }
        });
        _updateCalendarController();

        // Check for updates in the background
        _checkForUpdates();
      } else {
        print('No cached data found, fetching fresh data');
        await fetchAllSessionSummaries();
        // After fetching, update both views
        final updatedCache = box.get('all_sessions', defaultValue: []) as List;
        if (updatedCache.isNotEmpty) {
          setState(() {
            _cachedSessionSummaries =
                List<Map<String, dynamic>>.from(updatedCache);
            _isLoading = false;
            // If we're in list view, update the sessions list too
            if (!_isCalendarView) {
              _sessions = _cachedSessionSummaries
                  .map((item) => SessionSummary.fromJson(item))
                  .whereType<SessionSummary>()
                  .toList();
              _hasLoadedListViewData = true;
            }
          });
          _updateCalendarController();
        }
      }
    } catch (e) {
      print('Error loading cached data: $e');
      await fetchAllSessionSummaries();
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      final box = Hive.box('session_summaries');
      final lastUpdateTimestamp = box.get('last_update_timestamp') as String?;

      if (lastUpdateTimestamp != null) {
        final authService = Provider.of<AuthService>(context, listen: false);
        final userEmail = await authService.getCurrentUserEmail();

        final response = await http.post(
          Uri.parse(ApiConfig.getAllSessionSummaries),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_email': userEmail,
            'since_timestamp': lastUpdateTimestamp,
          }),
        );

        if (response.statusCode == 200) {
          final List<dynamic> newData = jsonDecode(response.body);
          if (newData.isNotEmpty) {
            print('Found ${newData.length} new sessions, updating cache');
            final cachedSummaries =
                box.get('all_sessions', defaultValue: []) as List;
            // Properly cast the cached data
            final updatedSummaries = cachedSummaries.map((item) {
              if (item is Map) {
                return Map<String, dynamic>.from(item);
              }
              return <String, dynamic>{};
            }).toList();

            for (var newSummary in newData) {
              final typedNewSummary = Map<String, dynamic>.from(newSummary);
              updatedSummaries.removeWhere((summary) =>
                  summary['sessionId'] == typedNewSummary['sessionId']);
              updatedSummaries.add(typedNewSummary);
            }

            updatedSummaries.sort((a, b) => DateTime.parse(b['timestamp'])
                .compareTo(DateTime.parse(a['timestamp'])));

            await box.put('all_sessions', updatedSummaries);
            await box.put('last_update_timestamp',
                DateTime.now().toUtc().toIso8601String());

            if (mounted) {
              setState(() {
                _cachedSessionSummaries = updatedSummaries;
              });
              _updateCalendarController();
            }
          }
        }
      }
    } catch (e) {
      print('Error checking for updates: $e');
    }
  }

  Future<void> fetchAllSessionSummaries() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userEmail = await authService.getCurrentUserEmail();

      final response = await http.post(
        Uri.parse(ApiConfig.getAllSessionSummaries),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_email': userEmail}),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        print('Received ${data.length} session summaries from API');

        // Update cache
        final box = Hive.box('session_summaries');
        await box.put('all_sessions', data);
        await box.put(
            'last_update_timestamp', DateTime.now().toUtc().toIso8601String());

        if (mounted) {
          setState(() {
            _cachedSessionSummaries = List<Map<String, dynamic>>.from(data);
            _isLoading = false;
          });
          _updateCalendarController();
        }
      } else {
        print(
            'Error fetching session summaries: ${response.statusCode} - ${response.body}');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error fetching session summaries: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchPastSessions(
      {int page = 1, bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _isNetworkError = false;
        _sessions.clear();
        _surveyResponses.clear();
        _currentPage = 1;
        _hasNextPage = true;
        _lastSessionId = null;
      });
    } else {
      setState(() {
        _isFetchingMore = true;
        _errorMessage = null;
      });
    }

    try {
      // Get cached data
      final box = Hive.box('session_summaries');
      final cachedSummaries = box.get('all_sessions', defaultValue: []) as List;

      // If cache is empty, fetch from Lambda first
      if (cachedSummaries.isEmpty) {
        print('Cache is empty, fetching from Lambda');
        await fetchAllSessionSummaries();
        // After fetching, get the updated cache
        final updatedCache = box.get('all_sessions', defaultValue: []) as List;
        if (updatedCache.isEmpty) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _isFetchingMore = false;
            });
          }
          return;
        }
      }

      // Convert cached data to SessionSummary objects
      final allSessions = cachedSummaries
          .map((item) {
            if (item is Map) {
              return SessionSummary.fromJson(Map<String, dynamic>.from(item));
            }
            return null;
          })
          .whereType<SessionSummary>()
          .toList();

      // Calculate pagination
      final startIndex = (page - 1) * _pageSize;
      final endIndex = startIndex + _pageSize;
      final hasNextPage = endIndex < allSessions.length;

      // Get sessions for current page
      final pageSessions = allSessions.sublist(startIndex,
          endIndex > allSessions.length ? allSessions.length : endIndex);

      if (mounted) {
        setState(() {
          if (isRefresh) {
            _sessions = pageSessions;
          } else {
            _sessions.addAll(pageSessions);
          }
          _currentPage = page;
          _hasNextPage = hasNextPage;
          _hasLoadedListViewData = true;
          _isLoading = false;
          _isFetchingMore = false;

          // Check survey responses for new sessions
          if (pageSessions.isNotEmpty) {
            final newSessionIds = pageSessions
                .where((s) => !_surveyResponses.containsKey(s.sessionId))
                .map((s) => s.sessionId)
                .toList();
            if (newSessionIds.isNotEmpty) {
              final authService =
                  Provider.of<AuthService>(context, listen: false);
              authService.getCurrentUserEmail().then((userEmail) {
                if (userEmail != null) {
                  _checkSurveyResponses(userEmail, newSessionIds);
                }
              });
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
          _isFetchingMore = false;
        });
      }
      print('Error fetching past sessions: $e');
    }
  }

  Future<void> _checkSurveyResponses(
      String userEmail, List<String> sessionIdsToCheck) async {
    if (sessionIdsToCheck.isEmpty) return;
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.checkSurveyResponses),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_email': userEmail,
          'session_ids': sessionIdsToCheck,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _surveyResponses
                .addAll(Map<String, bool>.from(data['surveyResponses']));
          });
        }
      } else {
        final errorData = jsonDecode(response.body);
        print(
            'Failed to check survey responses: ${errorData['error']}${errorData['details'] != null ? '\nDetails: ${errorData['details']}' : ''}');
      }
    } catch (e) {
      print('Error checking survey responses: $e');
    }
  }

  Future<void> _refreshSingleSessionSurveyStatus(String sessionId) async {
    if (_surveyResponses.containsKey(sessionId)) {
      // If we already have the response, no need to fetch again
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final userEmail = await authService.getCurrentUserEmail();
    if (userEmail != null && sessionId.isNotEmpty) {
      _checkSurveyResponses(userEmail, [sessionId]);
    }
  }

  String _formatTimestamp(String timestamp) {
    final dateTime = DateTime.parse(timestamp).toLocal();
    return '${_dateFormat.format(dateTime)} at ${_timeFormat.format(dateTime)}';
  }

  void _processSessionsForCalendar() {
    print('Processing ${_cachedSessionSummaries.length} sessions for calendar');
    print(
        'First few summaries to process: ${_cachedSessionSummaries.take(3).toList()}');
    _events.clear();
    for (var summary in _cachedSessionSummaries) {
      final date = DateTime.parse(summary['timestamp']).toLocal();
      final day = DateTime(date.year, date.month, date.day);
      if (_events[day] == null) {
        _events[day] = [];
      }
      _events[day]!.add(summary);
    }
    print('Calendar events map has ${_events.length} days with sessions');
    print('First few days with sessions: ${_events.keys.take(3).toList()}');
  }

  Future<void> _loadViewPreference() async {
    try {
      if (!Hive.isBoxOpen('user_preferences')) {
        await Hive.openBox('user_preferences');
      }
      final box = Hive.box('user_preferences');
      final isCalendarView = box.get('is_calendar_view', defaultValue: false);
      print('Loading view preference: isCalendarView = $isCalendarView');
      if (mounted) {
        setState(() {
          _isCalendarView = isCalendarView;
        });
      }
    } catch (e) {
      print('Error loading view preference: $e');
      // If there's an error, default to list view
      if (mounted) {
        setState(() {
          _isCalendarView = false;
        });
      }
    }
  }

  Future<void> _saveViewPreference(bool isCalendarView) async {
    try {
      if (!Hive.isBoxOpen('user_preferences')) {
        await Hive.openBox('user_preferences');
      }
      final box = Hive.box('user_preferences');
      await box.put('is_calendar_view', isCalendarView);
      await box.flush(); // Ensure the data is written to disk
      print('Saved view preference: isCalendarView = $isCalendarView');
    } catch (e) {
      print('Error saving view preference: $e');
    }
  }

  void _toggleView(bool isCalendar) {
    print('Toggling view to: ${isCalendar ? 'calendar' : 'list'}');
    setState(() {
      _isCalendarView = isCalendar;
    });
    _saveViewPreference(isCalendar);

    // Load list view data if we haven't already and we're switching to list view
    if (!isCalendar && !_hasLoadedListViewData) {
      _fetchPastSessions(page: 1, isRefresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: _isCalendarView
                  ? _buildCalendarView()
                  : _buildListView(lightPurple, textGray),
            ),
            // View toggle icons at the bottom
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: lightPurple,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 6),
                      Container(
                        decoration: !_isCalendarView
                            ? BoxDecoration(
                                color: lighterPurple,
                                borderRadius: BorderRadius.circular(18),
                              )
                            : null,
                        height: !_isCalendarView ? 36 : null,
                        padding: !_isCalendarView
                            ? EdgeInsets.symmetric(horizontal: 0)
                            : null,
                        child: IconButton(
                          icon: Icon(Icons.list, color: textGray),
                          onPressed: () => _toggleView(false),
                          iconSize: 24,
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(),
                        ),
                      ),
                      SizedBox(width: 20),
                      Container(
                        decoration: _isCalendarView
                            ? BoxDecoration(
                                color: lighterPurple,
                                borderRadius: BorderRadius.circular(18),
                              )
                            : null,
                        height: _isCalendarView ? 36 : null,
                        padding: _isCalendarView
                            ? EdgeInsets.symmetric(horizontal: 0)
                            : null,
                        child: IconButton(
                          icon: Icon(Icons.calendar_month, color: textGray),
                          onPressed: () => _toggleView(true),
                          iconSize: 24,
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(),
                        ),
                      ),
                      SizedBox(width: 6),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarView() {
    // Process the sessions for the calendar
    _processSessionsForCalendar();

    return Container(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Calendar fills all available space, with bottom padding for the pill
          Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ScrollableCleanCalendar(
                      calendarController: calendarController,
                      layout: Layout.BEAUTY,
                      spaceBetweenMonthAndCalendar: 0,
                      dayBuilder: (context, day) {
                        final date = day.day;
                        final dayKey =
                            DateTime(date.year, date.month, date.day);
                        final summaries = _events[dayKey] ?? [];
                        final hasSession = summaries.isNotEmpty;
                        return GestureDetector(
                          onTap: hasSession
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DaySessionsPage(
                                        selectedDay: dayKey,
                                        sessions: summaries,
                                      ),
                                    ),
                                  );
                                }
                              : null,
                          child: Container(
                            margin: const EdgeInsets.all(2),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (hasSession)
                                  Container(
                                    width: double.infinity,
                                    height: double.infinity,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: darkPurple, width: 2),
                                      borderRadius: BorderRadius.circular(8),
                                      color: Colors.transparent,
                                    ),
                                  ),
                                Text(
                                  '${date.day}',
                                  style: TextStyle(
                                    color: hasSession ? darkPurple : textGray,
                                    fontWeight: hasSession
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      weekdayTextStyle: TextStyle(
                        color: textGray,
                        fontWeight: FontWeight.w600,
                      ),
                      monthBuilder: (context, month) {
                        return Padding(
                          padding: const EdgeInsets.only(
                              left: 0.0, bottom: 0.0, top: 0.0),
                          child: Text(
                            month,
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: darkPurple,
                            ),
                          ),
                        );
                      },
                      footer: SizedBox(height: 30),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.white.withOpacity(0.8),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: lightPurple,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading sessions...',
                      style: TextStyle(
                        color: darkPurple,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildListView(Color lightPurple, Color textGray) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: lightPurple));
    } else if (_isNetworkError && _sessions.isEmpty) {
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
                onPressed: () => _fetchPastSessions(page: 1, isRefresh: true),
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
                onPressed: () => _fetchPastSessions(page: 1, isRefresh: true),
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
    } else if (_sessions.isEmpty && !_isLoading && !_isFetchingMore) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: lightPurple),
            SizedBox(height: 16),
            Text(
              'Loading sessions...',
              style: TextStyle(
                color: textGray,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    } else {
      return RefreshIndicator(
        color: lightPurple,
        onRefresh: () => _fetchPastSessions(page: 1, isRefresh: true),
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
          itemCount: _sessions.length + (_hasNextPage ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _sessions.length && _hasNextPage) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                    child: CircularProgressIndicator(color: lightPurple)),
              );
            }
            if (index >= _sessions.length) {
              return SizedBox.shrink();
            }

            final session = _sessions[index];
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
                      _refreshSingleSessionSurveyStatus(session.sessionId);
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
