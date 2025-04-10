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

class SensorScreen extends StatefulWidget {
  @override
  _SensorScreenState createState() => _SensorScreenState();
}

class _SensorScreenState extends State<SensorScreen> {
  String _accelerometerData = 'Accelerometer: (0, 0, 0)';
  String _gyroscopeData = 'Gyroscope: (0, 0, 0)';
  bool _isTracking = false;
  bool _isAboveThreshold = false;
  double _threshold = 0.5; // Threshold value for the average second norm
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
        Uri.parse(
            'https://b8e3dexk76.execute-api.us-east-1.amazonaws.com/dev/get-user-profile'),
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

      // Save the accumulated sensor data for the batch by flushing the buffer
      _sensorDataRecorder
          .saveBufferedData(); // Save only if threshold is exceeded
    } else {
      setState(() {
        _isAboveThreshold = false;
      });

      // Discard buffered data if the threshold is not exceeded
      _sensorDataRecorder.clearBuffer();

      // Log a message if the threshold is not exceeded
      final elapsedTime = DateTime.now().difference(_startTime!).inMilliseconds;
      _sensorDataRecorder.saveMessage(elapsedTime / 1000.0,
          'Threshold not exceeded for the last 500 samples');

      print(
          'Average gyroscope movement below threshold. Skipping data saving for this batch.');
    }

    // Clear the list for the next batch
    _gyroscopeNorms.clear();
    _rowCount = 0; // Reset row count for the next batch
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
    await _uploadCSVToServer(); // Upload CSV to AWS Lambda
  }

  Future<void> _loadCSVData() async {
    try {
      // Read the CSV file and parse its content
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/sensor_data.csv';
      final file = File(path);

      // Load CSV data from file
      final csvContent = await file.readAsString();
      List<List<dynamic>> csvTable = CsvToListConverter().convert(csvContent);

      // Update the state with the loaded CSV data
      setState(() {
        _csvData = csvTable;
      });
    } catch (e) {
      print('Error loading CSV data: $e');
    }
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
      int batchSize = 50;
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
        final String lambdaEndpoint =
            "https://b8e3dexk76.execute-api.us-east-1.amazonaws.com/dev/save-raw-sensor-data";

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

      // AWS Lambda API Gateway endpoint for energy expenditure processing
      final String lambdaEndpoint =
          "https://b8e3dexk76.execute-api.us-east-1.amazonaws.com/dev/process-energy-expenditure";

      final response = await http.post(
        Uri.parse(lambdaEndpoint),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print("✅ Energy expenditure processing completed!");
        print("📊 Results: ${responseData['results']}");

        // Show results in a dialog with a scrollable list
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Energy Expenditure Results'),
              content: Container(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                        'Total Windows Processed: ${responseData['total_windows_processed']}'),
                    SizedBox(height: 16),
                    Container(
                      height: 300, // Fixed height for the list
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: responseData['results'].length,
                        itemBuilder: (context, index) {
                          final result = responseData['results'][index];
                          // Parse the ISO timestamp string directly
                          final timestamp = DateTime.parse(result['timestamp']);
                          return ListTile(
                            title: Text(
                                'EE: ${result['energyExpenditure'].toStringAsFixed(2)} kcal'),
                            subtitle: Text(
                                'Time: ${timestamp.toString().split('.')[0]}'),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Close'),
                ),
              ],
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

  @override
  Widget build(BuildContext context) {
    Color lightPurple = Color.fromRGBO(216, 194, 251, 1);
    Color textGray = Color.fromRGBO(66, 66, 66, 1);

    final profileProvider = context.watch<UserProfileProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'OpenMetabolics',
          style: TextStyle(color: textGray),
        ),
        backgroundColor: lightPurple,
        actions: [
          IconButton(
            icon: Icon(
              Icons.person,
              color: textGray,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserProfilePage(
                    userProfile: profileProvider.userProfile,
                    onProfileUpdated: (profile) {
                      profileProvider.updateProfile(profile);
                    },
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(
              Icons.logout,
              color: textGray,
            ),
            onPressed: () async {
              final authService =
                  Provider.of<AuthService>(context, listen: false);
              try {
                await authService.signOut();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => LoginPage()),
                  (Route<dynamic> route) => false,
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Error signing out. Please try again.')),
                );
              }
            },
          ),
        ],
      ),
      body: profileProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : profileProvider.errorMessage != null
              ? Center(child: Text(profileProvider.errorMessage!))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (_isTracking)
                        Text(
                          _accelerometerData,
                          style: Theme.of(context).textTheme.headline6,
                        ),
                      if (_isTracking) SizedBox(height: 16),
                      if (_isTracking)
                        Text(
                          _gyroscopeData,
                          style: Theme.of(context).textTheme.headline6,
                        ),
                      if (_isTracking && _isAboveThreshold)
                        SizedBox(height: 16),
                      if (_isTracking && _isAboveThreshold)
                        Text(
                          'Gyroscope movement exceeded threshold!',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      SizedBox(height: 16),
                      // Display CSV data in a ListView
                      Expanded(
                        child: ListView.builder(
                          itemCount: _csvData.length,
                          itemBuilder: (context, index) {
                            final row = _csvData[index];
                            return ListTile(
                              title: Text(row.join(', ')),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
      floatingActionButton: Container(
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
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
