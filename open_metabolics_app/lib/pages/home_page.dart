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
import 'feedback_form_page.dart';

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

  StreamSubscription? _accelerometerSubscription;
  StreamSubscription? _gyroscopeSubscription;
  DateTime? _startTime; // Variable to hold the start time

  // List to store CSV data for displaying in ListView
  List<List<dynamic>> _csvData = [];

  // Create an instance of the sensor data recorderR
  final SensorDataRecorder _sensorDataRecorder = SensorDataRecorder();

  final AuthService _authService = AuthService();
  UserProfile? _userProfile;
  bool _isLoading = true;
  String? _errorMessage;

  int _selectedIndex = 0;

  static const List<String> _titles = [
    'Open Metabolics',
    'User Profile',
    'Past Sessions',
    'User Survey',
  ];

  @override
  void initState() {
    super.initState();
    // Fetch profile when the page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProfileProvider>().fetchUserProfile();
    });
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
    } finally {
      setState(() {
        _isLoading = false;
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
    super.dispose();
  }

  void _startTracking() {
    final profileProvider = context.read<UserProfileProvider>();

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

    // Reset all states and buffers
    _sensorDataRecorder
        .startRecording(); // Reset the CSV file and recording state
    _startTime = DateTime.now(); // Reset start time

    setState(() {
      _isTracking = true;
      _csvData.clear(); // Clear any previously displayed CSV data
      _gyroscopeNorms.clear(); // Clear gyroscope norms
      _rowCount = 0; // Reset row count
      _isAboveThreshold = false; // Reset threshold flag
    });

    // Start sensors
    SensorChannel.startSensors().then((_) {}).catchError((error) {
      print('Error starting sensors: $error');
      // Show error message to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting sensors: $error'),
          backgroundColor: Colors.red,
        ),
      );
    });

    // Accelerometer subscription
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
        // Show error message to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting gyroscope data: $error'),
            backgroundColor: Colors.red,
          ),
        );
      });
    }, onError: (error) {
      print('Error getting accelerometer data: $error');
      // Show error message to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error getting accelerometer data: $error'),
          backgroundColor: Colors.red,
        ),
      );
    });

    // We don't need a separate gyroscope subscription anymore
    // as we're getting gyroscope data along with accelerometer data
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
    SensorChannel.stopSensors(); // Stop sensors via platform channel
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();

    setState(() {
      _isTracking = false;
    });

    // Stop recording and save data
    await _sensorDataRecorder.stopRecording();
    await _loadCSVData(); // Load CSV data to display in ListView

    // Only proceed with processing if we have data
    if (_csvData.isEmpty) {
      print("No data collected during tracking session");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'No data was collected during this session. Please try again.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show loading dialog since we have data to process
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Container(
            constraints: BoxConstraints(maxWidth: 300),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Processing Session Data...',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 8),
                Column(
                  children: [
                    Text(
                      'Saving sensor data',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      'Uploading to server',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      'Calculating energy expenditure',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    await _uploadCSVToServer(); // Upload CSV to AWS Lambda
  }

  Future<void> _uploadCSVToServer() async {
    try {
      // Get the current user's email
      final authService = Provider.of<AuthService>(context, listen: false);
      final userEmail = await authService.getCurrentUserEmail();

      if (userEmail == null) {
        print("❌ No user email found. Please ensure user is logged in.");
        return;
      }

      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/sensor_data.csv';
      final file = File(path);

      if (!await file.exists()) {
        print('CSV file does not exist');
        return;
      }

      // Read CSV file line-by-line
      List<String> csvLines = await file.readAsLines();

      if (csvLines.length <= 1) {
        print("❌ CSV file contains no data.");
        return;
      }

      // Extract header and data separately
      String header = csvLines.first;
      List<String> dataRows = csvLines.sublist(1); // Skip header row

      // Print total number of rows
      print("📊 Total rows in CSV (excluding header): ${dataRows.length}");

      // Define batch size
      int batchSize = 200;
      int totalBatches = (dataRows.length / batchSize).ceil();

      // Generate a unique session ID using timestamp and user email
      final String sessionId =
          '${DateTime.now().millisecondsSinceEpoch}_${userEmail.replaceAll('@', '_').replaceAll('.', '_')}';

      for (int i = 0; i < dataRows.length; i += batchSize) {
        List<String> batch =
            dataRows.sublist(i, (i + batchSize).clamp(0, dataRows.length));
        String batchCsv =
            "$header\n${batch.join("\n")}"; // Add header to each batch

        // Include session_id in the payload
        final Map<String, dynamic> payload = {
          "csv_data": batchCsv,
          "user_email": userEmail,
          "session_id": sessionId
        };

        // AWS Lambda API Gateway endpoint
        final String lambdaEndpoint = ApiConfig.saveRawSensorData;

        print(
            "📤 Uploading batch ${i ~/ batchSize + 1}/$totalBatches with ${batch.length} rows");

        // Send the structured JSON payload
        final response = await http.post(
          Uri.parse(lambdaEndpoint),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        );

        if (response.statusCode == 200) {
          print("✅ Batch ${i ~/ batchSize + 1} uploaded successfully!");
        } else {
          print(
              "❌ Failed to upload batch ${i ~/ batchSize + 1}: ${response.body}");
          break; // Stop on failure
        }
      }

      // After all raw data is uploaded, trigger energy expenditure processing
      await _processEnergyExpenditure(sessionId, userEmail);
    } catch (e) {
      print("⚠️ Error uploading CSV: $e");
    }
  }

  Future<void> _processEnergyExpenditure(
      String sessionId, String userEmail) async {
    try {
      print(
          "🔄 Starting energy expenditure processing for session: $sessionId");

      final Map<String, dynamic> payload = {
        "session_id": sessionId,
        "user_email": userEmail
      };

      // Get the Fargate service URL from the environment
      final String fargateEndpoint = ApiConfig.energyExpenditureServiceUrl;

      final response = await http.post(
        Uri.parse(fargateEndpoint),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

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

        // Show results in a dialog with a scrollable list
        if (mounted) {
          showDialog(
            context: context,
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
                                'Total Windows: ${responseData['total_windows_processed']}',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              Text(
                                'Basal Rate: ${basalRate.toStringAsFixed(2)} W',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              Text(
                                'Gait Cycles: $gaitCycles',
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
                            itemCount: responseData['results'].length,
                            itemBuilder: (context, index) {
                              final result = responseData['results'][index];
                              final timestamp =
                                  DateTime.parse(result['timestamp']);
                              final isGaitCycle =
                                  (result['energyExpenditure'] as num) >
                                      basalRate;
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
          );
        }
      } else {
        print("❌ Failed to process energy expenditure: ${response.body}");
        throw Exception('Failed to process energy expenditure');
      }
    } catch (e) {
      print("⚠️ Error processing energy expenditure: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing energy expenditure data'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildHomeTab(BuildContext context, Color lightPurple, Color textGray,
      UserProfileProvider profileProvider) {
    List<Widget> content = [];
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
      content.add(SizedBox(height: 16));
    }
    if (_csvData.isNotEmpty) {
      content.add(Text(
        'Captured Data',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: textGray,
        ),
      ));
      content.add(SizedBox(height: 8));
      content.add(
        Card(
          elevation: 2,
          color: Colors.grey.shade100,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView.separated(
            padding: EdgeInsets.all(16),
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: _csvData.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Colors.grey.shade300,
            ),
            itemBuilder: (context, index) {
              final row = _csvData[index];
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  row.join(', '),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: index == 0
                        ? Colors.grey.shade800
                        : Colors.grey.shade600,
                    fontWeight:
                        index == 0 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            },
          ),
        ),
      );
    } else if (!_isTracking) {
      content.add(
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.25,
        ),
      );
      content.add(
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.sensors_off,
                size: 64,
                color: Colors.grey.shade400,
              ),
              SizedBox(height: 16),
              Text(
                'No Sensor Data',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Press the Start button to begin recording',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      );
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
      UserProfilePage(
        userProfile: profileProvider.userProfile,
        onProfileUpdated: (profile) {
          profileProvider.updateProfile(profile);
        },
      ),
      PastSessionsPage(),
      FeedbackFormPage(),
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
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.question_answer),
            label: 'Survey',
          ),
        ],
      ),
    );
  }
}
