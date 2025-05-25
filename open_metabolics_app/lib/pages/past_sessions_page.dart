import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import '../config/api_config.dart';
import '../models/session.dart';
import 'session_details_page.dart';
import '../auth/auth_service.dart';
import 'package:provider/provider.dart';
import 'dart:io' show SocketException, InternetAddress;
import 'package:amplify_flutter/amplify_flutter.dart' as amplify;
import 'package:scrollable_clean_calendar/scrollable_clean_calendar.dart';
import 'package:scrollable_clean_calendar/controllers/clean_calendar_controller.dart';
import 'package:scrollable_clean_calendar/utils/enums.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'day_sessions_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:sticky_headers/sticky_headers.dart';

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
    // Check network error state first
    _checkNetworkErrorState();
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

  Future<void> _checkNetworkErrorState() async {
    try {
      final preferencesBox = Hive.box('user_preferences');
      final hasNetworkError =
          preferencesBox.get('has_network_error', defaultValue: false);
      final hasInitializedCache =
          preferencesBox.get('has_initialized_cache', defaultValue: false);
      final box = Hive.box('session_summaries');
      final cachedData = box.get('all_sessions', defaultValue: []) as List;

      if (hasNetworkError) {
        // If we have cached data and cache was initialized, show it instead of network error
        if (cachedData.isNotEmpty && hasInitializedCache) {
          setState(() {
            _isNetworkError = false;
            _isLoading = false;
            _cachedSessionSummaries = cachedData.map((item) {
              if (item is Map) {
                return Map<String, dynamic>.from(item);
              }
              return <String, dynamic>{};
            }).toList();
            _sessions = _cachedSessionSummaries
                .map((item) => SessionSummary.fromJson(item))
                .whereType<SessionSummary>()
                .toList();
            _hasLoadedListViewData = true;
          });
          _updateCalendarController();
        } else {
          setState(() {
            _isNetworkError = true;
            _isLoading = false;
            _cachedSessionSummaries = [];
            _sessions = [];
            _hasLoadedListViewData = true;
          });
        }
      }
    } catch (e) {
      print('Error checking network error state: $e');
    }
  }

  Future<void> _saveNetworkErrorState(bool hasError) async {
    try {
      final preferencesBox = Hive.box('user_preferences');
      final box = Hive.box('session_summaries');
      final cachedData = box.get('all_sessions', defaultValue: []) as List;
      final hasInitializedCache =
          preferencesBox.get('has_initialized_cache', defaultValue: false);

      // Only save network error state if we don't have valid cached data
      if (!hasError ||
          (hasError && (cachedData.isEmpty || !hasInitializedCache))) {
        await preferencesBox.put('has_network_error', hasError);
      }
    } catch (e) {
      print('Error saving network error state: $e');
    }
  }

  Future<void> _loadCachedSessionSummaries() async {
    try {
      final box = Hive.box('session_summaries');
      final cached = box.get('all_sessions', defaultValue: []);
      final lastUpdateTimestamp = box.get('last_update_timestamp') as String?;
      final preferencesBox = Hive.box('user_preferences');
      final hasSuccessfullyLoadedCache = preferencesBox
          .get('has_successfully_loaded_cache', defaultValue: false);
      final hasInitializedCache =
          preferencesBox.get('has_initialized_cache', defaultValue: false);

      // If this is the first time accessing the page (no view preference saved)
      final hasAccessedBefore =
          preferencesBox.get('has_accessed_past_sessions', defaultValue: false);

      // If we haven't properly initialized the cache yet, we need to fetch all data
      if (!hasInitializedCache) {
        print('Cache not yet initialized, fetching all data');
        try {
          await fetchAllSessionSummaries();
          // Mark that we've accessed the page and initialized cache
          await preferencesBox.put('has_accessed_past_sessions', true);
          await preferencesBox.put('has_initialized_cache', true);
        } catch (e) {
          if (e is SocketException ||
              e.toString().contains('Failed host lookup')) {
            if (mounted) {
              setState(() {
                _isNetworkError = true;
                _isLoading = false;
                _cachedSessionSummaries = [];
                _sessions = [];
                _hasLoadedListViewData = true;
              });
            }
          }
        }
        return;
      }

      if (cached is List) {
        print('Loading cached data with ${cached.length} sessions');
        // Properly cast the cached data to the correct type
        final List<Map<String, dynamic>> typedCachedData = cached.map((item) {
          if (item is Map) {
            return Map<String, dynamic>.from(item);
          }
          return <String, dynamic>{};
        }).toList();

        if (mounted) {
          setState(() {
            _cachedSessionSummaries = typedCachedData;
            _isLoading = false;
            _isNetworkError = false;
            // Always update the sessions list regardless of view
            _sessions = typedCachedData
                .map((item) => SessionSummary.fromJson(item))
                .whereType<SessionSummary>()
                .toList();
            _hasLoadedListViewData = true;
          });
          _updateCalendarController();
          // Mark that we've successfully loaded cache
          await preferencesBox.put('has_successfully_loaded_cache', true);
        }

        // Check for updates in the background
        _checkForUpdates();
      } else if (lastUpdateTimestamp != null) {
        // We have a timestamp but no data - this means user has recorded before
        // but currently has no sessions
        if (mounted) {
          setState(() {
            _cachedSessionSummaries = [];
            _isLoading = false;
            _isNetworkError = false;
            _sessions = [];
            _hasLoadedListViewData = true;
          });
          _updateCalendarController();
          // Mark that we've successfully loaded cache
          await preferencesBox.put('has_successfully_loaded_cache', true);
        }
      } else {
        // No cache at all - need to fetch from network
        print('No cached data found, fetching fresh data');
        try {
          await fetchAllSessionSummaries();
          // Mark that we've initialized the cache
          await preferencesBox.put('has_initialized_cache', true);
        } catch (e) {
          if (e is SocketException ||
              e.toString().contains('Failed host lookup')) {
            if (mounted) {
              setState(() {
                _isNetworkError = true;
                _isLoading = false;
                _cachedSessionSummaries = [];
                _sessions = [];
                _hasLoadedListViewData = true;
              });
            }
          }
        }
      }
    } catch (e) {
      print('Error loading cached data: $e');
      if (e is SocketException || e.toString().contains('Failed host lookup')) {
        if (mounted) {
          setState(() {
            _isNetworkError = true;
            _isLoading = false;
            _cachedSessionSummaries = [];
            _sessions = [];
            _hasLoadedListViewData = true;
          });
        }
      } else {
        try {
          await fetchAllSessionSummaries();
          // Mark that we've initialized the cache
          final preferencesBox = Hive.box('user_preferences');
          await preferencesBox.put('has_initialized_cache', true);
        } catch (e) {
          if (e is SocketException ||
              e.toString().contains('Failed host lookup')) {
            if (mounted) {
              setState(() {
                _isNetworkError = true;
                _isLoading = false;
                _cachedSessionSummaries = [];
                _sessions = [];
                _hasLoadedListViewData = true;
              });
            }
          }
        }
      }
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
      _isNetworkError = false;
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
        final existingData = box.get('all_sessions', defaultValue: []) as List;

        // Merge new data with existing cache
        final updatedData = List<Map<String, dynamic>>.from(existingData);
        for (var newItem in data) {
          final typedNewItem = Map<String, dynamic>.from(newItem);
          // Remove any existing entry with the same sessionId
          updatedData.removeWhere(
              (item) => item['sessionId'] == typedNewItem['sessionId']);
          // Add the new item
          updatedData.add(typedNewItem);
        }

        // Sort by timestamp (most recent first)
        updatedData.sort((a, b) => DateTime.parse(b['timestamp'])
            .compareTo(DateTime.parse(a['timestamp'])));

        await box.put('all_sessions', updatedData);
        await box.put(
            'last_update_timestamp', DateTime.now().toUtc().toIso8601String());

        if (mounted) {
          setState(() {
            _cachedSessionSummaries = updatedData;
            _isLoading = false;
            _isNetworkError = false;
            // Replace the sessions list with fresh data
            _sessions = _cachedSessionSummaries
                .map((item) => SessionSummary.fromJson(item))
                .whereType<SessionSummary>()
                .toList();
            _hasLoadedListViewData = true;
          });
          _updateCalendarController();
          // Mark that we've successfully loaded cache
          final preferencesBox = Hive.box('user_preferences');
          await preferencesBox.put('has_successfully_loaded_cache', true);
          await preferencesBox.put('has_initialized_cache', true);
        }
      } else {
        print(
            'Error fetching session summaries: ${response.statusCode} - ${response.body}');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isNetworkError = true;
            _cachedSessionSummaries = [];
            _sessions = [];
            _hasLoadedListViewData = true;
          });
        }
      }
    } catch (e) {
      print('Error fetching session summaries: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isNetworkError = true;
          _cachedSessionSummaries = [];
          _sessions = [];
          _hasLoadedListViewData = true;
        });
      }
      // Re-throw the error to be caught by the caller
      rethrow;
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

    // If switching to list view, populate it with cached data
    if (!isCalendar) {
      setState(() {
        _sessions = _cachedSessionSummaries
            .map((item) => SessionSummary.fromJson(item))
            .whereType<SessionSummary>()
            .toList();
        _hasLoadedListViewData = true;
      });
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

    if (_isNetworkError) {
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
                onPressed: () async {
                  try {
                    // Check if cache was properly initialized
                    final preferencesBox = Hive.box('user_preferences');
                    final hasInitializedCache = preferencesBox
                        .get('has_initialized_cache', defaultValue: false);

                    if (!hasInitializedCache) {
                      // If cache wasn't properly initialized, fetch all data
                      await fetchAllSessionSummaries();
                    } else {
                      // If cache was initialized, try to fetch updates
                      await _checkForUpdates();
                    }
                  } catch (e) {
                    // If fetch fails, check if we have any cached data
                    final box = Hive.box('session_summaries');
                    final preferencesBox = Hive.box('user_preferences');
                    final hasInitializedCache = preferencesBox
                        .get('has_initialized_cache', defaultValue: false);
                    final cachedData =
                        box.get('all_sessions', defaultValue: []) as List;

                    if (cachedData.isNotEmpty && hasInitializedCache) {
                      // Only show cached data if cache was properly initialized
                      setState(() {
                        _isNetworkError = false;
                        _isLoading = false;
                        _cachedSessionSummaries = cachedData.map((item) {
                          if (item is Map) {
                            return Map<String, dynamic>.from(item);
                          }
                          return <String, dynamic>{};
                        }).toList();
                        _sessions = _cachedSessionSummaries
                            .map((item) => SessionSummary.fromJson(item))
                            .whereType<SessionSummary>()
                            .toList();
                        _hasLoadedListViewData = true;
                      });
                      _updateCalendarController();
                    }
                  }
                },
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
    }

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: lightPurple),
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
      );
    }

    // Check if we have any sessions
    final box = Hive.box('session_summaries');
    final lastUpdateTimestamp = box.get('last_update_timestamp') as String?;
    final cachedData = box.get('all_sessions', defaultValue: []) as List;

    if (cachedData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              lastUpdateTimestamp != null
                  ? Icons.event_busy
                  : Icons.sensors_off,
              size: 64,
              color: Colors.grey[600],
            ),
            SizedBox(height: 16),
            Text(
              lastUpdateTimestamp != null
                  ? 'No Sessions Recorded'
                  : 'Start Recording',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 8),
            Text(
              lastUpdateTimestamp != null
                  ? 'You haven\'t recorded any sessions yet'
                  : 'Begin tracking your energy expenditure',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

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
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(8),
                                        topRight: Radius.circular(0),
                                        bottomLeft: Radius.circular(8),
                                        bottomRight: Radius.circular(8),
                                      ),
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
                                if (hasSession)
                                  Positioned(
                                    top: -3,
                                    right: -3,
                                    child: Container(
                                      constraints: BoxConstraints(
                                        minWidth: 18,
                                        minHeight: 18,
                                      ),
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 5),
                                      decoration: BoxDecoration(
                                        color: darkPurple,
                                        shape: summaries.length > 99
                                            ? BoxShape.rectangle
                                            : BoxShape.circle,
                                        borderRadius: summaries.length > 99
                                            ? BorderRadius.circular(9)
                                            : null,
                                        border: Border.all(
                                          color: darkPurple,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${summaries.length}',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
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
        ],
      ),
    );
  }

  Widget _buildListView(Color lightPurple, Color textGray) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: lightPurple),
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
      );
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
                onPressed: () async {
                  try {
                    // Check if cache was properly initialized
                    final preferencesBox = Hive.box('user_preferences');
                    final hasInitializedCache = preferencesBox
                        .get('has_initialized_cache', defaultValue: false);

                    if (!hasInitializedCache) {
                      // If cache wasn't properly initialized, fetch all data
                      await fetchAllSessionSummaries();
                    } else {
                      // If cache was initialized, try to fetch updates
                      await _fetchPastSessions(page: 1, isRefresh: true);
                    }
                  } catch (e) {
                    // If fetch fails, check if we have any cached data
                    final box = Hive.box('session_summaries');
                    final preferencesBox = Hive.box('user_preferences');
                    final hasInitializedCache = preferencesBox
                        .get('has_initialized_cache', defaultValue: false);
                    final cachedData =
                        box.get('all_sessions', defaultValue: []) as List;

                    if (cachedData.isNotEmpty && hasInitializedCache) {
                      // Only show cached data if cache was properly initialized
                      setState(() {
                        _isNetworkError = false;
                        _isLoading = false;
                        _cachedSessionSummaries = cachedData.map((item) {
                          if (item is Map) {
                            return Map<String, dynamic>.from(item);
                          }
                          return <String, dynamic>{};
                        }).toList();
                        _sessions = _cachedSessionSummaries
                            .map((item) => SessionSummary.fromJson(item))
                            .whereType<SessionSummary>()
                            .toList();
                        _hasLoadedListViewData = true;
                      });
                    }
                  }
                },
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
    } else if (_sessions.isEmpty && !_isLoading && !_isFetchingMore) {
      // Check if we have a last update timestamp to determine if user has recorded before
      final box = Hive.box('session_summaries');
      final lastUpdateTimestamp = box.get('last_update_timestamp') as String?;
      final cachedData = box.get('all_sessions', defaultValue: []) as List;

      // If we have cached data but _sessions is empty, something went wrong with the conversion
      if (cachedData.isNotEmpty) {
        print(
            'Found ${cachedData.length} cached sessions but _sessions is empty, attempting to fix');
        setState(() {
          _sessions = cachedData
              .map((item) =>
                  SessionSummary.fromJson(Map<String, dynamic>.from(item)))
              .whereType<SessionSummary>()
              .toList();
          _hasLoadedListViewData = true;
        });
        return _buildListView(lightPurple, textGray);
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              lastUpdateTimestamp != null
                  ? Icons.event_busy
                  : Icons.sensors_off,
              size: 64,
              color: Colors.grey[600],
            ),
            SizedBox(height: 16),
            Text(
              lastUpdateTimestamp != null
                  ? 'No Sessions Recorded'
                  : 'Start Recording',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 8),
            Text(
              lastUpdateTimestamp != null
                  ? 'You haven\'t recorded any sessions yet'
                  : 'Begin tracking your energy expenditure',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    } else {
      // Group sessions by day
      Map<String, List<SessionSummary>> sessionsByDay = {};
      for (var session in _sessions) {
        final date = DateTime.parse(session.timestamp).toLocal();
        final dayKey = _dateFormat.format(date);
        if (!sessionsByDay.containsKey(dayKey)) {
          sessionsByDay[dayKey] = [];
        }
        sessionsByDay[dayKey]!.add(session);
      }

      // Sort days in descending order (most recent first)
      final sortedDays = sessionsByDay.keys.toList()
        ..sort((a, b) => _dateFormat.parse(b).compareTo(_dateFormat.parse(a)));

      return RefreshIndicator(
        color: lightPurple,
        onRefresh: () => _fetchPastSessions(page: 1, isRefresh: true),
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
          itemCount:
              sortedDays.length + (_hasNextPage && _isFetchingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == sortedDays.length && _hasNextPage && _isFetchingMore) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                    child: CircularProgressIndicator(color: lightPurple)),
              );
            }
            if (index >= sortedDays.length) {
              return SizedBox.shrink();
            }

            final dayKey = sortedDays[index];
            final daySessions = sessionsByDay[dayKey]!;

            return StickyHeader(
              header: Container(
                padding: const EdgeInsets.symmetric(vertical: 14.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18.0, vertical: 8.0),
                  decoration: BoxDecoration(
                    color: darkPurple.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    dayKey,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...daySessions.map((session) {
                    final hasFeedback =
                        _surveyResponses[session.sessionId] ?? false;
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
                              _refreshSingleSessionSurveyStatus(
                                  session.sessionId);
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Icon(Icons.access_time,
                                    color: textGray, size: 24),
                                SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _timeFormat.format(
                                            DateTime.parse(session.timestamp)
                                                .toLocal()),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
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
                                Icon(Icons.chevron_right,
                                    color: Colors.grey[400]),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                  // Divider between days
                  if (index < sortedDays.length - 1)
                    Divider(
                      color: Colors.grey[300],
                      thickness: 1,
                      height: 24,
                    ),
                ],
              ),
            );
          },
        ),
      );
    }
  }
}
