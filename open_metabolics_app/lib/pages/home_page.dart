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
      return session.results?['error'] != null ? Colors.red : Colors.green;
    }
    if (session.isWaitingForNetwork) {
      return Colors.orange;
    }
    return session.isProcessing ? Colors.orange : Colors.blue;
  }

  IconData _getStatusIcon(SessionStatus session) {
    if (session.isComplete) {
      return session.results?['error'] != null
          ? Icons.error_outline
          : Icons.check_circle;
    }
    if (session.isWaitingForNetwork) {
      return Icons.wifi_off;
    }
    return session.isProcessing ? Icons.sync : Icons.cloud_upload;
  }

  String _getStatusTitle(SessionStatus session) {
    if (session.isComplete) {
      return session.results?['error'] != null
          ? 'Upload Failed'
          : 'Session Complete';
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
  bool _isAboveThreshold = false;
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
  final SensorDataRecorder _sensorDataRecorder = SensorDataRecorder();

  final AuthService _authService = AuthService();
  UserProfile? _userProfile;
  String? _errorMessage;

  int _selectedIndex = 0;
  bool _hasNetworkConnection = true;

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
    // Fetch profile when the page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProfileProvider>().fetchUserProfile();
    });
  }

  Future<void> _initConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      _hasNetworkConnection =
          result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      _hasNetworkConnection = false;
    }

    // Listen for connectivity changes
    _connectivitySubscription =
        Stream.periodic(Duration(seconds: 5)).listen((_) async {
      try {
        final result = await InternetAddress.lookup('google.com');
        final hasConnection =
            result.isNotEmpty && result[0].rawAddress.isNotEmpty;

        if (hasConnection != _hasNetworkConnection) {
          setState(() {
            _hasNetworkConnection = hasConnection;
          });

          if (hasConnection) {
            // Resume any waiting uploads
            _resumeWaitingUploads();
          } else {
            // Pause any active uploads
            _pauseActiveUploads();
          }
        }
      } on SocketException catch (_) {
        if (_hasNetworkConnection) {
          setState(() {
            _hasNetworkConnection = false;
          });
          _pauseActiveUploads();
        }
      }
    });
  }

  void _pauseActiveUploads() {
    setState(() {
      for (var session in _sessions) {
        if (!session.isComplete) {
          session.isWaitingForNetwork = true;
          session.isProcessing = false;
          session.isProcessingEnergyExpenditure = false;
        }
      }
    });
  }

  void _resumeWaitingUploads() {
    for (var session in _sessions) {
      if (session.isWaitingForNetwork) {
        session.isWaitingForNetwork = false;
        if (session.isProcessingEnergyExpenditure) {
          // If we were processing energy expenditure, retry that
          _processEnergyExpenditure(
                  session.sessionId,
                  Provider.of<AuthService>(context, listen: false)
                      .getCurrentUserEmail() as String)
              .then((results) {
            setState(() {
              session.isComplete = true;
              session.isProcessing = false;
              session.isProcessingEnergyExpenditure = false;
              session.results = results;
            });
          }).catchError((error) {
            if (error.toString().contains('network')) {
              setState(() {
                session.isWaitingForNetwork = true;
                session.isProcessing = false;
                session.isProcessingEnergyExpenditure = false;
              });
            }
          });
        } else {
          // Otherwise continue with the upload
          _uploadCSVToServer(session);
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
    super.dispose();
  }

  void _startTracking() async {
    final profileProvider = context.read<UserProfileProvider>();

    if (profileProvider.isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait while your profile loads'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!profileProvider.hasProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please complete your profile before starting tracking'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    print('Start button pressed');

    // Generate session ID first
    String? userEmail;
    try {
      userEmail = await _authService.getCurrentUserEmail();
    } catch (e) {
      print('Warning: Could not get user email (possibly offline): $e');
      // Continue without user email - we'll use a timestamp-only session ID
    }

    final sessionId = userEmail != null
        ? '${DateTime.now().millisecondsSinceEpoch}_${userEmail.replaceAll('@', '_').replaceAll('.', '_')}'
        : '${DateTime.now().millisecondsSinceEpoch}_offline';

    // Set up recording first
    try {
      await _sensorDataRecorder.startRecording(sessionId);
    } catch (e) {
      print('Error starting recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting recording: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Start sensors after recording is set up
    try {
      await SensorChannel.startSensors(sessionId, _samplesPerSecond);
    } catch (e) {
      print('Error starting sensors: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting sensors: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Set up sensor subscription
    _accelerometerSubscription?.cancel(); // Cancel any existing subscription
    _accelerometerSubscription = Stream.periodic(
      Duration(milliseconds: (1000 / _samplesPerSecond).round()),
    ).asyncMap((_) => SensorChannel.getAccelerometerData()).listen((data) {
      if (data.length < 3) {
        print('Error: Invalid accelerometer data length: ${data.length}');
        return;
      }

      setState(() {
        _accelerometerData =
            'Accelerometer: (${data[0].toStringAsFixed(2)}, ${data[1].toStringAsFixed(2)}, ${data[2].toStringAsFixed(2)})';
      });

      // Get gyroscope data
      SensorChannel.getGyroscopeData().then((gyroData) {
        if (gyroData.length < 3) {
          print('Error: Invalid gyroscope data length: ${gyroData.length}');
          return;
        }

        setState(() {
          _gyroscopeData =
              'Gyroscope: (${gyroData[0].toStringAsFixed(2)}, ${gyroData[1].toStringAsFixed(2)}, ${gyroData[2].toStringAsFixed(2)})';

          double secondNorm = sqrt(gyroData[0] * gyroData[0] +
              gyroData[1] * gyroData[1] +
              gyroData[2] * gyroData[2]);
          _gyroscopeNorms.add(secondNorm);

          final elapsedTime =
              DateTime.now().difference(_startTime!).inMilliseconds;

          // Buffer both accelerometer and gyroscope data together
          _sensorDataRecorder.bufferData(elapsedTime / 1000.0, data[0], data[1],
              data[2], gyroData[0], gyroData[1], gyroData[2]);

          _rowCount++;

          if (_rowCount >= _batchSize) {
            _processGyroscopeDataBatch();
          }
        });
      }).catchError((error) {
        print('Error getting gyroscope data: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting gyroscope data: $error'),
            backgroundColor: Colors.red,
          ),
        );
      });
    }, onError: (error) {
      print('Error getting accelerometer data: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error getting accelerometer data: $error'),
          backgroundColor: Colors.red,
        ),
      );
    });

    // Update UI state immediately
    setState(() {
      _isTracking = true;
      _csvData.clear(); // Clear any previously displayed CSV data
      _gyroscopeNorms.clear(); // Clear gyroscope norms
      _rowCount = 0; // Reset row count
      _isAboveThreshold = false; // Reset threshold flag
      _startTime = DateTime.now(); // Reset start time
    });
  }

  void _processGyroscopeDataBatch() {
    // Calculate the average of the second norms
    double sumNorms = _gyroscopeNorms.fold(0, (sum, norm) => sum + norm);
    double averageNorm = sumNorms / _gyroscopeNorms.length;

    print('Average second norm of $_batchSize rows: $averageNorm');

    if (averageNorm > _threshold) {
      setState(() {
        _isAboveThreshold = true;
      });

      print('Average gyroscope movement exceeded threshold!');
    } else {
      setState(() {
        _isAboveThreshold = false;
      });

      print('Average gyroscope movement below threshold.');
    }

    // Always save the accumulated sensor data for the batch by flushing the buffer
    _sensorDataRecorder.saveBufferedData();

    // Clear the list for the next batch
    _gyroscopeNorms.clear();
    _rowCount = 0; // Reset row count for the next batch
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

    // Stop sensors and update UI
    SensorChannel.stopSensors();
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();

    // Create new session status
    String? userEmail;
    try {
      userEmail = await _authService.getCurrentUserEmail();
    } catch (e) {
      print('Warning: Could not get user email (possibly offline): $e');
    }

    final sessionId = userEmail != null
        ? '${DateTime.now().millisecondsSinceEpoch}_${userEmail.replaceAll('@', '_').replaceAll('.', '_')}'
        : '${DateTime.now().millisecondsSinceEpoch}_offline';

    // Get the file path for this session before stopping recording
    final filePath = await _sensorDataRecorder.getCurrentSessionFilePath();

    final session = SessionStatus(
      sessionId: sessionId,
      startTime: _startTime!,
      endTime: DateTime.now(),
      isWaitingForNetwork: !_hasNetworkConnection,
      filePath: filePath, // Store the file path in the session
    );

    // Update UI state and add session card immediately
    setState(() {
      _isTracking = false;
      _sessions.insert(0, session);
    });

    // Always stop recording and save data, regardless of network state
    await _sensorDataRecorder.stopRecording();

    if (filePath == null) {
      setState(() {
        session.isComplete = true;
        session.results = {
          'error': 'No data file found',
          'total_windows_processed': 0,
          'basal_metabolic_rate': 0,
          'gait_cycles': 0,
          'results': []
        };
      });
      return;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      setState(() {
        session.isComplete = true;
        session.results = {
          'error': 'No data file found',
          'total_windows_processed': 0,
          'basal_metabolic_rate': 0,
          'gait_cycles': 0,
          'results': []
        };
      });
      return;
    }

    // Read CSV file line-by-line
    List<String> csvLines = await file.readAsLines();

    if (csvLines.length <= 1) {
      setState(() {
        session.isComplete = true;
        session.results = {
          'error': 'No data recorded',
          'total_windows_processed': 0,
          'basal_metabolic_rate': 0,
          'gait_cycles': 0,
          'results': []
        };
      });
      return;
    }

    // Store the CSV lines in the session
    session.csvLines = csvLines;

    // If no network connection, keep the session in waiting state and return early
    if (!_hasNetworkConnection) {
      setState(() {
        session.isWaitingForNetwork = true;
      });
      return;
    }

    // Start upload with progress bar
    await _uploadCSVToServer(session);
  }

  Future<void> _uploadCSVToServer(SessionStatus session) async {
    if (!_hasNetworkConnection) {
      setState(() {
        session.isWaitingForNetwork = true;
      });
      return;
    }

    try {
      // Get the current user's email
      final authService = Provider.of<AuthService>(context, listen: false);
      final userEmail = await authService.getCurrentUserEmail();

      if (userEmail == null) {
        print("❌ No user email found. Please ensure user is logged in.");
        return;
      }

      // If we don't have the CSV lines stored, read them from the file
      if (session.csvLines == null && session.filePath != null) {
        final file = File(session.filePath!);
        if (!await file.exists()) {
          print('CSV file does not exist');
          setState(() {
            session.isComplete = true;
            session.results = {
              'error': 'No data file found',
              'total_windows_processed': 0,
              'basal_metabolic_rate': 0,
              'gait_cycles': 0,
              'results': []
            };
          });
          return;
        }

        // Read CSV file line-by-line and store in session
        session.csvLines = await file.readAsLines();
      }

      if (session.csvLines!.length <= 1) {
        print("❌ CSV file contains no data.");
        setState(() {
          session.isComplete = true;
          session.results = {
            'error': 'No data recorded',
            'total_windows_processed': 0,
            'basal_metabolic_rate': 0,
            'gait_cycles': 0,
            'results': []
          };
        });
        return;
      }

      // Extract header and data separately
      String header = session.csvLines!.first;
      List<String> dataRows = session.csvLines!.sublist(1); // Skip header row

      // Define batch size
      int batchSize = 200;
      int totalBatches = (dataRows.length / batchSize).ceil();

      // Start from the last uploaded batch
      for (int i = session.lastUploadedBatchIndex * batchSize;
          i < dataRows.length;
          i += batchSize) {
        // Check network connection before each batch
        if (!_hasNetworkConnection) {
          setState(() {
            session.isWaitingForNetwork = true;
            session.lastUploadedBatchIndex =
                i ~/ batchSize; // Save current batch index
          });
          return;
        }

        List<String> batch =
            dataRows.sublist(i, (i + batchSize).clamp(0, dataRows.length));
        String batchCsv = "$header\n${batch.join("\n")}";

        final Map<String, dynamic> payload = {
          "csv_data": batchCsv,
          "user_email": userEmail,
          "session_id": session.sessionId
        };

        final String lambdaEndpoint = ApiConfig.saveRawSensorData;

        print(
            "📤 Uploading batch ${i ~/ batchSize + 1}/$totalBatches with ${batch.length} rows");

        final response = await http.post(
          Uri.parse(lambdaEndpoint),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        );

        if (response.statusCode == 200) {
          print("✅ Batch ${i ~/ batchSize + 1} uploaded successfully!");

          // Update session progress
          setState(() {
            session.uploadProgress = (i ~/ batchSize + 1) / totalBatches;
            session.lastUploadedBatchIndex = i ~/ batchSize + 1;
          });
        } else {
          print(
              "❌ Failed to upload batch ${i ~/ batchSize + 1}: ${response.body}");
          setState(() {
            session.isWaitingForNetwork = true;
            session.lastUploadedBatchIndex =
                i ~/ batchSize; // Save current batch index
          });
          return;
        }
      }

      // Update session to processing state
      setState(() {
        session.isProcessing = true;
        session.isProcessingEnergyExpenditure = true;
      });

      // Check network connection before processing energy expenditure
      if (!_hasNetworkConnection) {
        setState(() {
          session.isWaitingForNetwork = true;
          session.isProcessing = false;
          session.isProcessingEnergyExpenditure = false;
        });
        return;
      }

      // Process energy expenditure
      final results =
          await _processEnergyExpenditure(session.sessionId, userEmail);

      // Update session as complete
      setState(() {
        session.isComplete = true;
        session.isProcessing = false;
        session.isProcessingEnergyExpenditure = false;
        session.results = results;
      });

      // Delete the CSV file after successful upload and processing
      try {
        final filePath = await _sensorDataRecorder.getCurrentSessionFilePath();
        if (filePath != null) {
          final file = File(filePath);
          await file.delete();
          print("✅ Deleted CSV file for session ${session.sessionId}");
        }
      } catch (e) {
        print("⚠️ Error deleting CSV file: $e");
      }

      // Show results dialog
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
                    // Title section with icon
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
                    // Stats section
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
                              'Total Windows: ${results['total_windows_processed']}',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            Text(
                              'Basal Rate: ${results['basal_metabolic_rate'].toStringAsFixed(2)} W',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            Text(
                              'Gait Cycles: ${results['gait_cycles']}',
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
                    // Results list
                    Flexible(
                      child: Scrollbar(
                        thickness: 8,
                        radius: Radius.circular(4),
                        thumbVisibility: true,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: results['results'].length,
                          itemBuilder: (context, index) {
                            final result = results['results'][index];
                            final timestamp =
                                DateTime.parse(result['timestamp']);
                            final isGaitCycle =
                                (result['energyExpenditure'] as num) >
                                    results['basal_metabolic_rate'];
                            final ee = result['energyExpenditure'] as num;

                            return EnergyExpenditureCard(
                              timestamp: timestamp,
                              energyExpenditure: ee.toDouble(),
                              isGaitCycle: isGaitCycle,
                            );
                          },
                        ),
                      ),
                    ),
                    // Close button
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
          // Show survey when dialog is dismissed
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
    } catch (e) {
      print("⚠️ Error uploading CSV: $e");
      if (e.toString().contains('network') ||
          e.toString().contains('connection')) {
        setState(() {
          session.isWaitingForNetwork = true;
          session.isProcessing = false;
          session.isProcessingEnergyExpenditure = false;
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>> _processEnergyExpenditure(
      String sessionId, String userEmail) async {
    try {
      print(
          "🔄 Starting energy expenditure processing for session: $sessionId");

      final Map<String, dynamic> payload = {
        "session_id": sessionId,
        "user_email": userEmail
      };

      final String fargateEndpoint = ApiConfig.energyExpenditureServiceUrl;

      // Check network connection before making the request
      if (!_hasNetworkConnection) {
        throw Exception('No network connection');
      }

      final response = await http.post(
        Uri.parse(fargateEndpoint),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print("✅ Energy expenditure processing completed!");
        print("📊 Results: ${responseData['results']}");

        // Get basal metabolic rate from response
        final basalRate = responseData['basal_metabolic_rate'] as num;

        // Count actual gait cycles (EE values above basal rate)
        final gaitCycles = responseData['results']
            .where((result) => (result['energyExpenditure'] as num) > basalRate)
            .length;

        return {
          'results': responseData['results'],
          'basal_metabolic_rate': basalRate,
          'gait_cycles': gaitCycles,
          'total_windows_processed': responseData['results'].length,
        };
      } else {
        print("❌ Failed to process energy expenditure: ${response.body}");
        throw Exception('Failed to process energy expenditure');
      }
    } catch (e) {
      print("⚠️ Error processing energy expenditure: $e");
      // If it's a network error, we want to retry when network is restored
      if (e.toString().contains('network') ||
          e.toString().contains('connection')) {
        throw Exception('Network error during energy expenditure processing');
      }
      throw e;
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
          child: Padding(
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
                                Icon(Icons.speed, color: Colors.blue, size: 20),
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
                if (_isAboveThreshold) ...[
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.red),
                        SizedBox(width: 8),
                        Text(
                          'Movement threshold exceeded',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
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
      padding: const EdgeInsets.all(16.0),
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
                        _isAboveThreshold = false;
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
