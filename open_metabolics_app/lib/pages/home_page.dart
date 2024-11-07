import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math'; // To calculate the second norm
import 'dart:io'; // To read the CSV file
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import '../sensor_channel.dart';
import '../services/sensor_data_recorder.dart'; // Import the channel class

class SensorScreen extends StatefulWidget {
  @override
  _SensorScreenState createState() => _SensorScreenState();
}

class _SensorScreenState extends State<SensorScreen> {
  String _accelerometerData = 'Accelerometer: (0, 0, 0)';
  String _gyroscopeData = 'Gyroscope: (0, 0, 0)';
  bool _isTracking = false;
  bool _isAboveThreshold = false;
  double _threshold = 5; // Example threshold value for the average second norm
  int _samplesPerSecond = 100; // Desired samples per second
  int _rowCount = 0; // Count the number of rows saved
  final int _batchSize = 500; // Compare after 500 rows
  List<double> _gyroscopeNorms = []; // Store gyroscope second norms

  StreamSubscription? _accelerometerSubscription;
  StreamSubscription? _gyroscopeSubscription;
  DateTime? _startTime; // Variable to hold the start time

  // List to store CSV data for displaying in ListView
  List<List<dynamic>> _csvData = [];

  // Create an instance of the sensor data recorder
  final SensorDataRecorder _sensorDataRecorder = SensorDataRecorder();

  @override
  void dispose() {
    // Cancel any active subscriptions when the widget is disposed
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    super.dispose();
  }

  void _startTracking() {
    print('Start button pressed');
    _startTime = DateTime.now();

    // Ensure UI updates when tracking starts
    setState(() {
      _isTracking = true;
      _csvData.clear(); // Clear previous CSV data when starting new tracking
      _gyroscopeNorms.clear(); // Clear gyroscope norms
      _rowCount = 0; // Reset row count
    });

    SensorChannel.startSensors().then((_) {}).catchError((error) {
      print('Error starting sensors: $error');
    });

    // Accelerometer subscription
    _accelerometerSubscription = Stream.periodic(
      Duration(milliseconds: (1000 / _samplesPerSecond).round()),
    ).asyncMap((_) => SensorChannel.getAccelerometerData()).listen((data) {
      setState(() {
        _accelerometerData =
            'Accelerometer: (${data[0].toStringAsFixed(2)}, ${data[1].toStringAsFixed(2)}, ${data[2].toStringAsFixed(2)})';
      });

      // Save the accelerometer data to buffer, but don't write to CSV yet
      final elapsedTime = DateTime.now().difference(_startTime!).inMilliseconds;
      _sensorDataRecorder.bufferData(elapsedTime / 1000.0, data[0], data[1],
          data[2], 0, 0, 0 // Placeholder for gyroscope data
          );
    });

// Gyroscope subscription
    _gyroscopeSubscription = Stream.periodic(
      Duration(milliseconds: (1000 / _samplesPerSecond).round()),
    ).asyncMap((_) => SensorChannel.getGyroscopeData()).listen((data) {
      setState(() {
        _gyroscopeData =
            'Gyroscope: (${data[0].toStringAsFixed(2)}, ${data[1].toStringAsFixed(2)}, ${data[2].toStringAsFixed(2)})';

        double secondNorm =
            sqrt(data[0] * data[0] + data[1] * data[1] + data[2] * data[2]);

        // Save second norm for later averaging
        _gyroscopeNorms.add(secondNorm);

        final elapsedTime =
            DateTime.now().difference(_startTime!).inMilliseconds;

        // Save the gyroscope data to buffer, but don't write to CSV yet
        _sensorDataRecorder.bufferData(
            elapsedTime / 1000.0,
            0,
            0,
            0, // Placeholder for accelerometer data
            data[0],
            data[1],
            data[2]);

        _rowCount++; // Increment row count

        // If 500 rows have been recorded, process the batch
        if (_rowCount >= _batchSize) {
          _processGyroscopeDataBatch();
        }
      });
    });
  }

  void _processGyroscopeDataBatch() {
    // Calculate the average of the second norms
    double sumNorms = _gyroscopeNorms.fold(0, (sum, norm) => sum + norm);
    double averageNorm = sumNorms / _gyroscopeNorms.length;

    print('Average second norm of 500 rows: $averageNorm');

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

    // Ensure UI updates when tracking stops
    setState(() {
      _isTracking = false;
    });

    // Stop recording and read the CSV file content
    await _sensorDataRecorder.stopRecording();
    _loadCSVData();
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

  @override
  Widget build(BuildContext context) {
    Color lightPurple = Color.fromRGBO(216, 194, 251, 1);
    Color textGray = Color.fromRGBO(66, 66, 66, 1);

    return Scaffold(
      appBar: AppBar(
        title: Text('OpenMetabolics'),
        backgroundColor: lightPurple,
      ),
      body: Padding(
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
            if (_isTracking && _isAboveThreshold) SizedBox(height: 16),
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
                  _sensorDataRecorder.startRecording();
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
