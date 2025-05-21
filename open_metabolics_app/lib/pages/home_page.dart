import 'dart:convert';

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math'; // To calculate the second norm
import 'dart:io'; // To read the CSV file and check platform
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import '../services/sensor_channel.dart';
import '../services/sensor_data_recorder.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../auth/auth_service.dart';
import '../auth/login_page.dart';
import 'user_profile_page.dart';
import '../models/user_profile.dart';
import '../providers/user_profile_provider.dart';
import '../config/api_config.dart';
import 'past_sessions_page.dart';
import '../widgets/energy_expenditure_card.dart';
import '../widgets/feedback_bottom_drawer.dart';
import 'package:flutter/services.dart'; // Add this import for PlatformException
import 'package:hive/hive.dart';

// Session status class to track session state
class SessionStatus {
  final String sessionId;
  final DateTime startTime;
  final DateTime? endTime;
  double uploadProgress;
  bool isProcessing;
  bool isComplete;
  bool isWaitingForNetwork;
  Map<String, dynamic>? results;
  int lastUploadedBatchIndex; // Track which batch was last uploaded
  List<String>? csvLines; // Store CSV data for resuming uploads
  bool
      isProcessingEnergyExpenditure; // Track if we're in the energy expenditure phase
  String? filePath; // Add file path to track which file belongs to this session

  SessionStatus({
    required this.sessionId,
    required this.startTime,
    this.endTime,
    this.uploadProgress = 0.0,
    this.isProcessing = false,
    this.isComplete = false,
    this.isWaitingForNetwork = false,
    this.results,
    this.lastUploadedBatchIndex = 0,
    this.csvLines,
    this.isProcessingEnergyExpenditure = false,
    this.filePath,
  });
}

// Widget to display session status
class SessionStatusWidget extends StatelessWidget {
  final SessionStatus session;
  final VoidCallback? onDismiss;

  const SessionStatusWidget({
    Key? key,
    required this.session,
    this.onDismiss,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              Colors.grey.shade50,
            ],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _getStatusColor(session).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getStatusIcon(session),
                          color: _getStatusColor(session),
                          size: 24,
                        ),
                      ),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getStatusTitle(session),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            session.startTime.toString().substring(0, 19),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (session.isComplete && onDismiss != null)
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.grey[400]),
                      onPressed: onDismiss,
                    ),
                ],
              ),
              SizedBox(height: 16),
              if (!session.isComplete) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: session.isProcessing ? null : session.uploadProgress,
                    backgroundColor: Colors.grey[200],
                    valueColor:
                        AlwaysStoppedAnimation<Color>(_getStatusColor(session)),
                    minHeight: 8,
                  ),
                ),
                SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _getStatusText(session),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    if (session.isProcessing || session.isWaitingForNetwork)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              _getStatusColor(session)),
                        ),
                      ),
                  ],
                ),
              ] else ...[
                if (session.results != null &&
                    session.results!['error'] != null) ...[
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            session.results!['error'],
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Session complete',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(SessionStatus session) {
    if (session.isComplete) {
      if (session.results?['error'] != null) {
        return Colors.red;
      }
      return Colors.green;
    }
    if (session.isWaitingForNetwork) {
      return Colors.orange;
    }
    if (session.isProcessingEnergyExpenditure) {
      return Colors.deepPurple;
    }
    if (session.isProcessing) {
      return Colors.orange;
    }
    return Colors.blue;
  }

  IconData _getStatusIcon(SessionStatus session) {
    if (session.isComplete) {
      if (session.results?['error'] != null) {
        return Icons.error_outline;
      }
      return Icons.check_circle;
    }
    if (session.isWaitingForNetwork) {
      return Icons.wifi_off;
    }
    return session.isProcessing ? Icons.sync : Icons.cloud_upload;
  }

  String _getStatusTitle(SessionStatus session) {
    if (session.isComplete) {
      if (session.results?['error'] != null) {
        if (session.results!['error']
            .toString()
            .startsWith('Session too short')) {
          return 'Upload Failed';
        }
        return 'Upload Failed';
      }
      return 'Session Complete';
    }
    if (session.isWaitingForNetwork) {
      return 'Waiting for Network';
    }
    return session.isProcessing ? 'Processing' : 'Uploading';
  }

  String _getStatusText(SessionStatus session) {
    if (session.isWaitingForNetwork) {
      return 'Waiting for network connection...';
    }
    if (session.isProcessing) {
      return 'Processing data...';
    }
    return 'Uploading: ${(session.uploadProgress * 100).toStringAsFixed(0)}%';
  }
}

// Widget to display when no sessions are active
class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height -
          200, // Account for app bar and bottom nav
      child: Center(
        child: Container(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.sensors_off,
                  size: 64,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: 24),
              Text(
                'No Active Sessions',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SensorScreen extends StatefulWidget {
  @override
  _SensorScreenState createState() => _SensorScreenState();
}

class _SensorScreenState extends State<SensorScreen> {
  String _accelerometerData = 'Accelerometer: (0, 0, 0)';
  String _gyroscopeData = 'Gyroscope: (0, 0, 0)';
  bool _isTracking = false;
  double _threshold = 0; // Threshold value for the average second norm
  int _samplesPerSecond = 50; // Desired samples per second
  int _rowCount = 0; // Count the number of rows saved
  final int _batchSize = 200; // Compare after 500 rows
  List<double> _gyroscopeNorms = []; // Store gyroscope second norms

  // Add list to track multiple sessions
  List<SessionStatus> _sessions = [];

  StreamSubscription? _accelerometerSubscription;
  StreamSubscription? _gyroscopeSubscription;
  StreamSubscription? _connectivitySubscription;
  DateTime? _startTime; // Variable to hold the start time

  // List to store CSV data for displaying in ListView
  List<List<dynamic>> _csvData = [];

  // Create an instance of the sensor data recorderR
  Map<String, SensorDataRecorder> _activeRecorders =
      {}; // NEW: Map of recorders by sessionId

  final AuthService _authService = AuthService();
  UserProfile? _userProfile;
  String? _errorMessage;

  int _selectedIndex = 0;
  bool _hasNetworkConnection = true;

  String?
      _currentSessionId; // <-- ADDED: To store the session ID from startTracking
  int _currentSessionLinesWritten =
      0; // <-- ADDED: To track lines written to current CSV

  static const List<String> _titles = [
    'Open Metabolics',
    'Past Sessions',
    'User Profile',
  ];

  @override
  void initState() {
    super.initState();
    // Initialize connectivity listener
    _initConnectivity();
    // Check network state immediately
    _verifyNetworkState();
    // Fetch profile when the page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProfileProvider>().fetchUserProfile();
    });
  }

  Future<void> _verifyNetworkState() async {
    print("Verifying network state on app start...");
    // Assume network is available unless proven otherwise
    bool hasConnection = true;

    try {
      final result = await InternetAddress.lookup('google.com');
      hasConnection = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (e) {
      // Only mark as disconnected if we get a clear network error
      // Ignore "Lost connection to device" errors
      if (!e.toString().contains("Lost connection to device")) {
        hasConnection = false;
      }
    }

    print(
        "Final network state: ${hasConnection ? 'Connected' : 'Disconnected'}");
    print("Current sessions: ${_sessions.length}");
    for (var session in _sessions) {
      print(
          "Session ${session.sessionId}: waiting=${session.isWaitingForNetwork}, complete=${session.isComplete}");
    }

    if (mounted) {
      setState(() {
        _hasNetworkConnection = hasConnection;
        // If we have connection, update any sessions that were waiting
        if (hasConnection) {
          for (var session in _sessions) {
            if (session.isWaitingForNetwork) {
              print(
                  "Resuming session ${session.sessionId} that was waiting for network");
              session.isWaitingForNetwork = false;
              session.isProcessing =
                  true; // Set processing to true to show upload progress
              if (!session.isComplete) {
                // Use Future.microtask to ensure state is updated before starting upload
                Future.microtask(() => _uploadCSVToServer(session));
              }
            }
          }
        }
      });
    }
  }

  Future<void> _initConnectivity() async {
    // Initial check - assume network is available unless proven otherwise
    bool hasConnection = true;
    try {
      final result = await InternetAddress.lookup('google.com');
      hasConnection = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (e) {
      // Ignore "Lost connection to device" errors
      if (!e.toString().contains("Lost connection to device")) {
        hasConnection = false;
      }
    }

    _hasNetworkConnection = hasConnection;

    // Listen for connectivity changes
    _connectivitySubscription =
        Stream.periodic(Duration(seconds: 5)).listen((_) async {
      bool hasConnection = true;
      try {
        final result = await InternetAddress.lookup('google.com');
        hasConnection = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      } on SocketException catch (e) {
        // Ignore "Lost connection to device" errors
        if (!e.toString().contains("Lost connection to device")) {
          hasConnection = false;
        }
      }

      if (hasConnection != _hasNetworkConnection) {
        setState(() {
          _hasNetworkConnection = hasConnection;
        });

        if (hasConnection) {
          // Resume any waiting uploads
          _resumeWaitingUploads();
        } else {
          // Only pause if we're certain there's no connection
          _pauseActiveUploads();
        }
      }
    });
  }

  void _pauseActiveUploads() {
    setState(() {
      for (var session in _sessions) {
        if (!session.isComplete && !session.isWaitingForNetwork) {
          // Only pause if not already waiting
          session.isWaitingForNetwork = true;
          // If it was uploading, it will be implicitly paused.
          // If it was in the _processEnergyExpenditure HTTP call, that call will either complete or timeout.
          // The retry logic in _processEnergyExpenditure handles network loss during its own operation.
        }
      }
    });
  }

  void _resumeWaitingUploads() async {
    // First verify network connection
    bool hasConnection = false;
    for (int i = 0; i < 3; i++) {
      try {
        final result = await InternetAddress.lookup('google.com');
        if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
          hasConnection = true;
          break;
        }
      } on SocketException catch (_) {
        await Future.delayed(Duration(seconds: 1));
      }
    }

    // Update network state
    if (mounted) {
      setState(() {
        _hasNetworkConnection = hasConnection;
      });
    }

    // If we have connection, resume uploads
    if (hasConnection) {
      for (var session in _sessions) {
        if (session.isWaitingForNetwork) {
          // Find the authoritative SessionStatus object from the _sessions list
          final sessionStatusToResume = _sessions.firstWhere(
              (s) => s.sessionId == session.sessionId,
              orElse: () => session /* Should always find itself */);

          if (mounted) {
            setState(() {
              sessionStatusToResume.isWaitingForNetwork = false;
            });
          } else {
            continue;
          }

          if (sessionStatusToResume.isProcessingEnergyExpenditure &&
              !sessionStatusToResume.isComplete) {
            print(
                "Resuming energy expenditure for ${sessionStatusToResume.sessionId}");
            String? userEmail;
            try {
              userEmail = await Provider.of<AuthService>(context, listen: false)
                  .getCurrentUserEmail();
              if (userEmail == null) throw Exception("User email is null");
            } catch (e) {
              print(
                  "Error getting user email for EE resumption of ${sessionStatusToResume.sessionId}: $e");
              if (mounted) {
                setState(() {
                  sessionStatusToResume.isWaitingForNetwork =
                      true; // Needs network for email
                  sessionStatusToResume.isProcessing = false;
                  sessionStatusToResume.isProcessingEnergyExpenditure = false;
                });
              }
              continue;
            }

            // Resume polling for results if previously waiting for network
            final results = await _processEnergyExpenditure(
                sessionStatusToResume.sessionId, userEmail);
            if (results['waitingForNetwork'] == true) {
              // Still waiting for network, do not mark as complete
              continue;
            }
            if (results['error'] != null) {
              // Only mark as complete if it's a real error (not just waiting for network)
              if (mounted) {
                setState(() {
                  sessionStatusToResume.isComplete = true;
                  sessionStatusToResume.isProcessing = false;
                  sessionStatusToResume.isProcessingEnergyExpenditure = false;
                  sessionStatusToResume.results = results;
                  _activeRecorders.remove(sessionStatusToResume.sessionId);
                });
              }
              continue;
            }
            // Only here, for real results, mark as complete
            if (mounted) {
              setState(() {
                sessionStatusToResume.isComplete = true;
                sessionStatusToResume.isProcessing = false;
                sessionStatusToResume.isProcessingEnergyExpenditure = false;
                sessionStatusToResume.results = results;
                _activeRecorders.remove(sessionStatusToResume.sessionId);
              });
            }
          } else if (!sessionStatusToResume.isComplete) {
            print(
                "Attempting/Resuming CSV upload for ${sessionStatusToResume.sessionId}.");
            _uploadCSVToServer(sessionStatusToResume);
          } else {
            print(
                "Session ${sessionStatusToResume.sessionId} was waiting but is already complete. No action taken.");
          }
        }
      }
    }
  }

  Future<void> _fetchUserProfile() async {
    try {
      final userEmail = await _authService.getCurrentUserEmail();
      if (userEmail == null) {
        throw Exception('User not logged in');
      }

      final response = await http.post(
        Uri.parse(ApiConfig.getUserProfile),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_email': userEmail,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _userProfile = UserProfile.fromJson(data);
        });
      } else if (response.statusCode == 404) {
        // Profile not found, this is okay
        setState(() {
          _userProfile = null;
        });
      } else {
        throw Exception('Failed to fetch profile: ${response.body}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    }
  }

  void _updateUserProfile(UserProfile profile) {
    setState(() {
      _userProfile = profile;
    });
  }

  @override
  void dispose() {
    // Cancel any active subscriptions when the widget is disposed
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _connectivitySubscription?.cancel();
    // Ensure all active recorders are stopped and cleaned up if necessary
    _activeRecorders.forEach((sessionId, recorder) async {
      await recorder.stopRecording();
    });
    _activeRecorders.clear();
    super.dispose();
  }

  void _startTracking() async {
    final profileProvider = context.read<UserProfileProvider>();
    if (profileProvider.isLoading || !profileProvider.hasProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(profileProvider.isLoading
              ? 'Please wait while your profile loads'
              : 'Please complete your profile before starting tracking'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check if another session is currently being recorded by this UI instance.
    if (_isTracking) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('A session is already being recorded. Please stop it first.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    print('Start button pressed');

    String? userEmail;
    try {
      userEmail = await _authService.getCurrentUserEmail();
    } catch (e) {
      print('Error getting user email (likely offline): $e');
      userEmail =
          null; // Ensure userEmail is null to trigger offline session ID
    }

    final String newSessionId = userEmail != null
        ? '${DateTime.now().millisecondsSinceEpoch}_${userEmail.replaceAll('@', '_').replaceAll('.', '_')}'
        : '${DateTime.now().millisecondsSinceEpoch}_offline';

    // Create and store a new recorder for this session
    final newRecorder = SensorDataRecorder(sessionId: newSessionId);
    _activeRecorders[newSessionId] = newRecorder;

    // Set current recording session ID for the UI
    _currentSessionId = newSessionId;

    // Start the Dart-side recording (file initialization)
    bool recordingStarted = await newRecorder.startRecording();
    if (!recordingStarted) {
      print(
          'Error: SensorDataRecorder failed to start for session $newSessionId.');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Error initializing recording. Please try again.'),
        backgroundColor: Colors.red,
      ));
      _activeRecorders.remove(newSessionId); // Clean up failed recorder
      _currentSessionId = null;
      return;
    }

    // Start native sensors AFTER Dart recorder is ready
    try {
      await SensorChannel.startSensors(
          newSessionId); // Pass newSessionId to native

      // Add a small delay to allow service binding
      await Future.delayed(Duration(milliseconds: 500));

      // Now try to set active sessions
      try {
        await SensorChannel.setHasActiveSessions(true);
      } catch (e) {
        print('Warning: Could not set active sessions state: $e');
        // Continue anyway as the service is still running
      }
    } catch (e) {
      print('Error starting native sensors for session $newSessionId: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error starting device sensors: $e'),
        backgroundColor: Colors.red,
      ));
      await newRecorder
          .stopRecording(); // Clean up Dart recorder if native part fails
      _activeRecorders.remove(newSessionId);
      _currentSessionId = null;
      return;
    }

    _startTime = DateTime.now(); // Set start time for this new session

    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = Stream.periodic(
      Duration(milliseconds: (1000 / _samplesPerSecond).round()),
    ).asyncMap((_) => SensorChannel.getAccelerometerData()).listen((data) {
      if (data.length < 3) return;

      if (_currentSessionId == null ||
          _activeRecorders[_currentSessionId] == null) {
        // If no active recording session or recorder is found, stop listening.
        _accelerometerSubscription?.cancel();
        return;
      }
      final currentRecorder = _activeRecorders[_currentSessionId!];

      setState(() {
        _accelerometerData =
            'Accelerometer: (${data[0].toStringAsFixed(2)}, ${data[1].toStringAsFixed(2)}, ${data[2].toStringAsFixed(2)})';
      });

      SensorChannel.getGyroscopeData().then((gyroData) {
        if (gyroData.length < 3) return;

        setState(() {
          _gyroscopeData =
              'Gyroscope: (${gyroData[0].toStringAsFixed(2)}, ${gyroData[1].toStringAsFixed(2)}, ${gyroData[2].toStringAsFixed(2)})';
          if (_currentSessionId != null && _startTime != null) {
            double secondNorm = sqrt(gyroData[0] * gyroData[0] +
                gyroData[1] * gyroData[1] +
                gyroData[2] * gyroData[2]);
            _gyroscopeNorms.add(secondNorm);

            final elapsedTime =
                DateTime.now().difference(_startTime!).inMilliseconds;
            currentRecorder!.bufferData(elapsedTime / 1000.0, data[0], data[1],
                data[2], gyroData[0], gyroData[1], gyroData[2]);
            _rowCount++;
            if (_rowCount >= _batchSize) {
              _processGyroscopeDataBatch(_currentSessionId!);
            }
          }
        });
      }).catchError((error) {
        print('Error getting gyroscope data: $error');
      });
    }, onError: (error) {
      print('Error getting accelerometer data: $error');
    });

    setState(() {
      _isTracking = true; // General flag indicating app is in tracking mode
      _gyroscopeNorms.clear();
      _rowCount = 0;
      _currentSessionLinesWritten = 0; // Initialize for new session
    });
  }

  void _processGyroscopeDataBatch(String sessionId) {
    // Takes sessionId
    final recorder = _activeRecorders[sessionId];
    if (recorder == null || _gyroscopeNorms.isEmpty) return;

    double sumNorms = _gyroscopeNorms.fold(0, (sum, norm) => sum + norm);
    double averageNorm = sumNorms / _gyroscopeNorms.length;
    print(
        'Session $sessionId: Average second norm of $_batchSize rows: $averageNorm');

    if (averageNorm > _threshold) {
      print(
          'Session $sessionId: Average gyroscope movement exceeded threshold!');
    } else {
      print('Session $sessionId: Average gyroscope movement below threshold.');
    }
    recorder.saveBufferedData();

    // Update lines written count
    bool firstSave = _currentSessionLinesWritten == 0;
    if (firstSave) {
      // Assuming header is written by SensorDataRecorder on first save.
      // If recorder.saveBufferedData() writes a header + _batchSize rows on first call,
      // this logic is correct.
      _currentSessionLinesWritten += 1; // For the header
    }
    _currentSessionLinesWritten +=
        _batchSize; // Add the number of data rows in a batch

    _gyroscopeNorms.clear();
    _rowCount = 0;

    if (mounted) {
      setState(() {
        // This setState is to update the UI for the new indicator based on _currentSessionLinesWritten
      });
    }
  }

  Future<void> _loadCSVData() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/sensor_data.csv';
      final file = File(path);

      if (!await file.exists()) {
        print('CSV file does not exist');
        setState(() {
          _csvData = [];
        });
        return;
      }

      // Read CSV file line-by-line
      List<String> csvLines = await file.readAsLines();

      if (csvLines.length <= 1) {
        print("CSV file contains no data.");
        setState(() {
          _csvData = [];
        });
        return;
      }

      // Convert lines to CSV table format
      List<List<dynamic>> csvTable =
          csvLines.map((line) => line.split(',')).toList();

      // Update the state with the loaded CSV data
      setState(() {
        _csvData = csvTable;
      });
    } catch (e) {
      print('Error loading CSV data: $e');
      setState(() {
        _csvData = [];
      });
    }
  }

  void _stopTracking() async {
    print('Stop button pressed');
    if (_currentSessionId == null) {
      print('Error: No current recording session ID to stop.');
      setState(() {
        _isTracking = false;
      });
      return;
    }

    final sessionIdToStop = _currentSessionId!;
    final recorder = _activeRecorders[sessionIdToStop];

    if (recorder == null) {
      print('Error: No active recorder found for session $sessionIdToStop.');
      setState(() {
        _isTracking = false;
        _currentSessionId = null;
      });
      return;
    }

    // Create the session status first
    final session = SessionStatus(
      sessionId: sessionIdToStop,
      startTime: _startTime!, // Use the start time for this specific session
      endTime: DateTime.now(),
      isWaitingForNetwork: !_hasNetworkConnection,
      filePath: null, // Will be set after getting file path
      csvLines: null, // Will be read in _uploadCSVToServer if needed
      lastUploadedBatchIndex: 0,
    );

    // Get file path before stopping recording
    final filePath = await recorder.getCurrentSessionFilePath();
    session.filePath = filePath;

    // Update wake lock state based on active sessions BEFORE stopping service
    try {
      // Add this session to the list first so it's counted in active sessions
      setState(() {
        _sessions.insert(0, session);
        _isTracking = false;
        _currentSessionId = null;
        _startTime = null;
        _currentSessionLinesWritten = 0;
      });

      // Now set active sessions state while service is still bound
      await SensorChannel.setHasActiveSessions(_sessions.isNotEmpty);
    } catch (e) {
      print('Warning: Could not update active sessions state: $e');
      // Continue anyway as we're stopping the service
    }

    // Stop the recording and sensors
    await recorder.stopRecording();
    SensorChannel.stopSensors();
    _accelerometerSubscription?.cancel();

    // Initiate upload if network is available
    if (_hasNetworkConnection) {
      await _uploadCSVToServer(session);
    } else {
      print("No network. Session $sessionIdToStop will wait for upload.");
    }
  }

  Future<void> _uploadCSVToServer(SessionStatus session) async {
    print("Starting upload for session ${session.sessionId}");
    print(
        "Network state: ${_hasNetworkConnection ? 'Connected' : 'Disconnected'}");
    print(
        "Session state: waiting=${session.isWaitingForNetwork}, complete=${session.isComplete}");

    // Start the upload service
    try {
      await SensorChannel.startUpload();
      await SensorChannel.setHasActiveUploads(true);
    } catch (e) {
      print("Warning: Could not start upload service: $e");
      // Continue anyway as the upload might still work
    }

    // Only mark as waiting if we're certain there's no network
    if (!_hasNetworkConnection) {
      print("No network connection, marking session as waiting");
      if (session != null && mounted) {
        setState(() {
          session!.isWaitingForNetwork = true;
        });
      }
      return;
    }

    // Clear waiting status and ensure we're processing
    if (session.isWaitingForNetwork) {
      print("Clearing waiting status for session ${session.sessionId}");
      if (session != null && mounted) {
        setState(() {
          session.isWaitingForNetwork = false;
          session.isProcessing = true;
        });
      }
    }

    String? userEmail;
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      userEmail = await authService.getCurrentUserEmail();
    } catch (e) {
      print(
          "❌ Network error getting user email for session ${session.sessionId}: $e");
      if (session != null && mounted) {
        setState(() {
          session!.isWaitingForNetwork = true; // Set to wait for network
          session!.isProcessing = false;
          session!.isProcessingEnergyExpenditure = false;
        });
      }
      return; // Exit if email cannot be fetched due to network
    }

    if (userEmail == null) {
      print(
          "❌ No user email retrieved for session ${session.sessionId}. Cannot upload.");
      if (session != null && mounted) {
        setState(() {
          session!.isComplete = true;
          session!.results = {
            'error': 'User not logged in or email not available, cannot upload.'
          };
          _activeRecorders.remove(session.sessionId);
          session!.isProcessing = false;
          session!.isProcessingEnergyExpenditure = false;
        });
      }
      return;
    }

    try {
      // Ensure filePath exists in session object
      if (session.filePath == null) {
        print(
            "❌ File path is null for session ${session.sessionId}. Cannot upload.");
        setState(() {
          session!.isComplete = true;
          session!.results = {'error': 'File path missing, cannot upload.'};
          _activeRecorders.remove(session.sessionId); // Clean up recorder
        });
        return;
      }

      final file = File(session.filePath!); // Use the path from SessionStatus
      if (!await file.exists()) {
        print(
            'CSV file does not exist at ${session.filePath} for session ${session.sessionId}');
        setState(() {
          session!.isComplete = true;
          session!.results = {'error': 'No data file found for upload.'};
          _activeRecorders.remove(session.sessionId); // Clean up recorder
        });
        return;
      }

      if (session.csvLines == null) {
        // Read lines if not already in SessionStatus (e.g. on resume)
        session.csvLines = await file.readAsLines();
      }

      // Check if the session is too short (less than 250 total lines, including header)
      if (session.csvLines!.length < 250) {
        print(
            "❌ CSV file for session ${session.sessionId} is too short (less than 250 rows). Actual: ${session.csvLines!.length} rows.");
        if (session != null && mounted) {
          // Ensure widget is still mounted
          setState(() {
            session!.isComplete = true;
            session!.results = {'error': 'Session too short for analysis'};
            _activeRecorders.remove(session.sessionId);
            // Ensure other processing flags are false
            session!.isProcessing = false;
            session!.isProcessingEnergyExpenditure = false;
            session!.uploadProgress = 0.0; // Reset progress
          });
        }
        return; // Exit before attempting any network upload
      }

      String header = session.csvLines!.first;
      List<String> dataRows = session.csvLines!.sublist(1);
      int batchSize = 200;
      int totalBatches = (dataRows.length / batchSize).ceil();

      setState(() {
        // Initial state for upload start
        session.isProcessing = false; // Explicitly false for pure upload phase
        session.uploadProgress = 0.0;
        session.isProcessingEnergyExpenditure = false; // Not yet in this phase
      });

      for (int batchStartIndex = session.lastUploadedBatchIndex * batchSize;
          batchStartIndex < dataRows.length;
          batchStartIndex += batchSize) {
        if (!_hasNetworkConnection) {
          setState(() {
            session.isWaitingForNetwork = true;
            session.lastUploadedBatchIndex = batchStartIndex ~/ batchSize;
            session.isProcessing = false; // Paused processing/uploading
          });
          print("Network lost during upload of ${session.sessionId}. Pausing.");
          return;
        }

        List<String> batch = dataRows.sublist(batchStartIndex,
            (batchStartIndex + batchSize).clamp(0, dataRows.length));
        String batchCsv = "$header\n${batch.join("\n")}";
        final Map<String, dynamic> payload = {
          "csv_data": batchCsv,
          "user_email": userEmail,
          "session_id": session.sessionId
        };
        final String lambdaEndpoint = ApiConfig.saveRawSensorData;

        print(
            "📤 Uploading batch ${batchStartIndex ~/ batchSize + 1}/$totalBatches for ${session.sessionId}");
        final response = await http.post(Uri.parse(lambdaEndpoint),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(payload));

        if (response.statusCode == 200) {
          print(
              "✅ Batch ${batchStartIndex ~/ batchSize + 1} for ${session.sessionId} uploaded successfully!");
          if (mounted)
            setState(() {
              session.uploadProgress =
                  (batchStartIndex ~/ batchSize + 1) / totalBatches;
              session.lastUploadedBatchIndex = batchStartIndex ~/ batchSize + 1;
            });
        } else {
          print(
              "❌ Failed to upload batch ${batchStartIndex ~/ batchSize + 1} for ${session.sessionId}: ${response.body}");
          if (session != null && mounted)
            setState(() {
              session!.isWaitingForNetwork =
                  true; // Assume network or temp server issue
              session!.lastUploadedBatchIndex = batchStartIndex ~/ batchSize;
              session!.isProcessing = false;
            });
          return;
        }
      }

      // Mark upload as 100% complete and allow UI to render this state
      if (mounted) {
        setState(() {
          session.uploadProgress = 1.0;
          session.isProcessing =
              false; // Keep isProcessing false for this frame
          session.isProcessingEnergyExpenditure =
              false; // Not yet processing EE
        });
      }

      // Add a small delay to allow the 100% progress bar to render
      await Future.delayed(const Duration(
          milliseconds: 100)); // e.g., 50-100ms, adjusted to 100ms

      // Now, transition to the energy expenditure processing state
      if (mounted) {
        setState(() {
          session.isProcessing = true; // Now true for actual processing phase
          session.isProcessingEnergyExpenditure = true;
          // uploadProgress remains 1.0, but isProcessing=true will make bar indeterminate
        });
      }

      if (!_hasNetworkConnection) {
        if (session != null && mounted)
          setState(() {
            session!.isWaitingForNetwork = true;
            session!.isProcessing = false; // EE processing paused
            session!.isProcessingEnergyExpenditure =
                false; // Ensure this is false if waiting
          });
        print(
            "Network lost before starting energy expenditure for ${session.sessionId}. Pausing.");
        return;
      }

      final results =
          await _processEnergyExpenditure(session.sessionId, userEmail);
      if (results['waitingForNetwork'] == true) {
        // Still waiting for network, do not mark as complete
        return;
      }
      if (results['error'] != null) {
        // Only mark as complete if it's a real error (not just waiting for network)
        if (mounted) {
          setState(() {
            session.isComplete = true;
            session.isProcessing = false;
            session.isProcessingEnergyExpenditure = false;
            session.results = results;
            _activeRecorders.remove(session.sessionId);
          });
        }
        return;
      }
      // Only here, for real results, mark as complete
      if (mounted) {
        setState(() {
          session.isComplete = true;
          session.isProcessing = false;
          session.isProcessingEnergyExpenditure = false;
          session.results = results;
          _activeRecorders.remove(session.sessionId);
        });

        // Update session summaries cache
        try {
          final box = Hive.box('session_summaries');
          final cachedSummaries =
              box.get('all_sessions', defaultValue: []) as List;
          final updatedSummaries = cachedSummaries.map((item) {
            if (item is Map) {
              return Map<String, dynamic>.from(item);
            }
            return <String, dynamic>{};
          }).toList();

          // Add new session summary
          updatedSummaries.add({
            'sessionId': session.sessionId,
            'timestamp': session.startTime.toUtc().toIso8601String(),
            'measurementCount': results.length
          });

          // Sort by timestamp (most recent first)
          updatedSummaries.sort((a, b) => DateTime.parse(b['timestamp'])
              .compareTo(DateTime.parse(a['timestamp'])));

          // Update cache
          await box.put('all_sessions', updatedSummaries);
          await box.put('last_update_timestamp',
              DateTime.now().toUtc().toIso8601String());
        } catch (e) {
          print('Error updating session summaries cache: $e');
        }
      }

      // --- Show dialog and survey logic remains same ---
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => Dialog(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.9,
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Processing Complete',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Session Statistics',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Total Windows: ${(results['total_windows_processed'] ?? 0)}',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            Text(
                              'Basal Rate: ${(results['basal_metabolic_rate'] ?? 0.0).toStringAsFixed(2)} W',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            Text(
                              'Gait Cycles: ${(results['gait_cycles'] ?? 0)}',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Energy Expenditure Results',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: 8),
                    Flexible(
                      child: Scrollbar(
                        thickness: 8,
                        radius: Radius.circular(4),
                        thumbVisibility: true,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: (results['results'] ?? []).length,
                          itemBuilder: (context, index) {
                            final result = (results['results'] ?? [])[index];
                            print('Result: $result'); // Debug print
                            final timestampStr = result['timestamp'] ?? '';
                            DateTime? timestamp;
                            try {
                              timestamp = DateTime.tryParse(timestampStr);
                            } catch (_) {
                              timestamp = null;
                            }
                            // Use the correct field name from backend: 'EnergyExpenditure'
                            final eeStr = result['EnergyExpenditure']?['N'];
                            final eeValue = (eeStr is String)
                                ? double.tryParse(eeStr) ?? 0.0
                                : 0.0;
                            final bmr = results['basal_metabolic_rate'] ?? 0.0;
                            final isGaitCycle = eeValue > bmr;

                            return EnergyExpenditureCard(
                              timestamp: timestamp ??
                                  DateTime.fromMillisecondsSinceEpoch(0),
                              energyExpenditure: eeValue.toDouble(),
                              isGaitCycle: isGaitCycle,
                            );
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text('Close'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ).then((_) {
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
              builder: (context, scrollController) =>
                  FeedbackBottomDrawer(sessionId: session.sessionId),
            ),
          );
        });
      }

      // At the end of successful upload and processing
      if (session.isComplete) {
        try {
          await SensorChannel.setHasActiveUploads(false);
          await SensorChannel.stopUpload();
        } catch (e) {
          print('Warning: Could not stop upload service: $e');
        }
      }
    } catch (e) {
      print(
          "⚠️ Error in _uploadCSVToServer for session ${session.sessionId}: $e");
      if (mounted) {
        setState(() {
          if (e.toString().contains('network') ||
              e.toString().contains('connection') ||
              e.toString().contains('host lookup') ||
              e.toString().contains('SocketException') ||
              e.toString().contains('Failed host lookup')) {
            session.isWaitingForNetwork = true;
            session.isProcessing = false;
            session.isProcessingEnergyExpenditure = false;
            print(
                "Network error detected, waiting for connection: ${e.toString()}");
          } else {
            // Generic error during upload/processing, mark as failed
            session.isComplete = true;
            session.isProcessing = false;
            session.isProcessingEnergyExpenditure = false;
            session.results = {
              'error': 'Failed to upload/process session: ${e.toString()}'
            };
            _activeRecorders.remove(session.sessionId);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('Error processing session ${session.sessionId}: $e'),
              backgroundColor: Colors.red,
            ));
          }
        });
      }
    }
  }

  Future<Map<String, dynamic>> _processEnergyExpenditure(
      String sessionId, String userEmail) async {
    // New async Fargate flow
    final String fargateBaseUrl = ApiConfig.energyExpenditureServiceUrl;
    final String processUrl = fargateBaseUrl.endsWith('/')
        ? fargateBaseUrl + 'process'
        : fargateBaseUrl + '/process';
    final String statusUrl = fargateBaseUrl.endsWith('/')
        ? fargateBaseUrl + 'status/'
        : fargateBaseUrl + '/status/';
    final String resultsUrl = fargateBaseUrl.endsWith('/')
        ? fargateBaseUrl + 'results/'
        : fargateBaseUrl + '/results/';

    // Find the session object if it exists
    SessionStatus? session;
    try {
      session = _sessions.firstWhere((s) => s.sessionId == sessionId);
    } catch (_) {
      session = null;
    }

    try {
      // 1. Queue the job
      final response = await http.post(
        Uri.parse(processUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "session_id": sessionId,
          "user_email": userEmail,
        }),
      );

      if (response.statusCode != 202) {
        final responseBody = response.body;
        print("❌ Failed to queue processing: $responseBody");
        throw Exception('Failed to queue processing: $responseBody');
      }

      // 2. Start polling status
      bool isComplete = false;
      bool isFailed = false;
      String? errorMsg;
      double progress = 0.0;
      int pollCount = 0;
      const int maxPolls = 8800; // 7 hours 20 minutes max (26400 seconds)
      const Duration pollInterval = Duration(seconds: 3);
      Map<String, dynamic>? statusData;

      while (!isComplete && !isFailed && pollCount < maxPolls) {
        try {
          await Future.delayed(pollInterval);
          pollCount++;
          final statusResp = await http.get(Uri.parse(statusUrl + sessionId));
          if (statusResp.statusCode == 200) {
            statusData = jsonDecode(statusResp.body);
            if (statusData != null) {
              final status = statusData['status'];
              progress = (statusData['progress'] ?? 0.0).toDouble();
              errorMsg = statusData['error'];

              if (status == 'completed') {
                isComplete = true;
                break;
              } else if (status == 'failed') {
                isFailed = true;
                break;
              }
            } else {
              print(
                  'Status response body was null or not JSON: \\${statusResp.body}');
            }
          } else {
            print('Error polling status: \\${statusResp.body}');
          }
        } catch (e) {
          // Network error during polling
          if (e is SocketException ||
              e.toString().contains('Failed host lookup') ||
              e.toString().contains('SocketException')) {
            print('Network lost during polling for $sessionId. Pausing.');
            if (session != null && mounted) {
              setState(() {
                session!.isWaitingForNetwork = true;
                session!.isProcessing = false;
                session!.isProcessingEnergyExpenditure = false;
              });
            }
            // Exit polling loop, but do NOT mark as failed
            return {'waitingForNetwork': true};
          } else {
            // Other errors: handle as before
            print("⚠️ Error in _processEnergyExpenditure polling: $e");
            return {'error': 'Failed to process energy expenditure: $e'};
          }
        }
      }

      if (isFailed) {
        return {'error': errorMsg ?? 'Processing failed. Please try again.'};
      }
      if (!isComplete) {
        return {'error': 'Processing timed out. Please try again.'};
      }

      // 3. Fetch results
      final resultsResp = await http.get(Uri.parse(resultsUrl + sessionId));
      if (resultsResp.statusCode == 200) {
        final responseData = jsonDecode(resultsResp.body);
        final basalRate = responseData['results'] != null &&
                responseData['results'].isNotEmpty
            ? (responseData['results'][0]['BasalMetabolicRate']?['N'] is String
                ? double.tryParse(responseData['results'][0]
                        ['BasalMetabolicRate']?['N']) ??
                    0.0
                : 0.0)
            : 0.0;
        final gaitCycles = responseData['results'] != null
            ? responseData['results'].where((result) {
                final n = result['EnergyExpenditure']?['N'];
                final nStr = (n is String && n != null) ? n : '0';
                return (double.tryParse(nStr) ?? 0) > basalRate;
              }).length
            : 0;
        return {
          'results': responseData['results'],
          'basal_metabolic_rate': basalRate,
          'gait_cycles': gaitCycles,
          'total_windows_processed': responseData['results']?.length ?? 0,
        };
      } else {
        return {'error': 'Failed to fetch results: ${resultsResp.body}'};
      }
    } catch (e) {
      // Network error during initial queueing
      if (e is SocketException ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('SocketException')) {
        print('Network lost during initial queueing for $sessionId. Pausing.');
        if (session != null && mounted) {
          setState(() {
            session!.isWaitingForNetwork = true;
            session!.isProcessing = false;
            session!.isProcessingEnergyExpenditure = false;
          });
        }
        return {'waitingForNetwork': true};
      }
      print("⚠️ Error in _processEnergyExpenditure: $e");
      return {'error': 'Failed to process energy expenditure: $e'};
    }
  }

  Widget _buildHomeTab(BuildContext context, Color lightPurple, Color textGray,
      UserProfileProvider profileProvider) {
    List<Widget> content = [];

    // Add current tracking session if active
    if (_isTracking) {
      content.add(
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.sensors, color: lightPurple),
                        SizedBox(width: 8),
                        Text(
                          'Live Sensor Data',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: textGray,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.blue.withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.speed,
                                        color: Colors.blue, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Accelerometer',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8),
                                Text(
                                  _accelerometerData.split(': ')[1],
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontFamily: 'monospace',
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.rotate_right,
                                        color: Colors.green, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Gyroscope',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8),
                                Text(
                                  _gyroscopeData.split(': ')[1],
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontFamily: 'monospace',
                                    color: Colors.green.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_currentSessionLinesWritten >= 400)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Icon(
                    Icons.check_box_outlined,
                    color: lightPurple,
                    size: 24,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Add all session status widgets
    for (var session in _sessions) {
      content.add(
        SessionStatusWidget(
          session: session,
          onDismiss: session.isComplete
              ? () {
                  setState(() {
                    _sessions.remove(session);
                  });
                }
              : null,
        ),
      );
    }

    // If no content, show empty state
    if (content.isEmpty) {
      return const EmptyStateWidget();
    }

    return ListView(
      padding: const EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: 16.0,
        bottom: 120.0, // Add extra padding at bottom to account for FAB
      ),
      children: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    Color lightPurple = Color.fromRGBO(216, 194, 251, 1);
    Color textGray = Color.fromRGBO(66, 66, 66, 1);
    final profileProvider = context.watch<UserProfileProvider>();

    Future<void> _showLogoutDialog() async {
      final shouldLogout = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Log out'),
          content: Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Log out', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (shouldLogout == true) {
        final authService = Provider.of<AuthService>(context, listen: false);
        try {
          await authService.signOut();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => LoginPage()),
            (Route<dynamic> route) => false,
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error signing out. Please try again.')),
          );
        }
      }
    }

    final List<Widget> _pages = [
      _buildHomeTab(context, lightPurple, textGray, profileProvider),
      PastSessionsPage(),
      UserProfilePage(
        onProfileUpdated: (profile) {
          profileProvider.updateProfile(profile);
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_selectedIndex],
          style: TextStyle(color: textGray),
        ),
        backgroundColor: lightPurple,
        iconTheme: IconThemeData(color: textGray),
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: textGray),
            tooltip: 'Log out',
            onPressed: _showLogoutDialog,
          ),
        ],
      ),
      body: profileProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : profileProvider.errorMessage != null
              ? Center(child: Text(profileProvider.errorMessage!))
              : _selectedIndex == 0
                  ? _buildHomeTab(
                      context, lightPurple, textGray, profileProvider)
                  : _pages[_selectedIndex],
      floatingActionButton: _selectedIndex == 0
          ? Container(
              height: 95,
              width: 95,
              child: FittedBox(
                child: FloatingActionButton.extended(
                  foregroundColor: lightPurple,
                  backgroundColor: lightPurple,
                  onPressed: () {
                    setState(() {
                      if (_isTracking) {
                        _stopTracking();
                      } else {
                        _startTracking();
                      }
                    });
                  },
                  label: Text(
                    _isTracking ? 'Stop' : 'Start',
                    style: TextStyle(color: textGray),
                  ),
                  shape: CircleBorder(),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
