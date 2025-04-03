import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'dart:math'; // ✅ Import math for L2 norm calculation

class SensorDataRecorder {
  late File _file;
  late IOSink _sink;
  bool _isRecording = false;

  // Buffer to hold rows of data
  List<List<double>> _dataBuffer = [];

  // Initialize and create a CSV file (overwrite mode)
  Future<void> _initializeFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, 'sensor_data.csv');

    _file = File(path);

    // Open the file in write mode to overwrite any existing content
    _sink = _file.openWrite(mode: FileMode.write);

    // ✅ Add "L2_Norm" to the header
    _sink.writeln(
      'Timestamp,Accelerometer_X,Accelerometer_Y,Accelerometer_Z,Gyroscope_X,Gyroscope_Y,Gyroscope_Z,L2_Norm,Platform',
    );
  }

  // Start recording data (reset file, buffer, and state)
  Future<void> startRecording() async {
    // Ensure any previous recording session is stopped
    await stopRecording();

    // Reinitialize the file and clear buffers
    await _initializeFile();
    _dataBuffer.clear(); // Clear any previous buffered data
    _isRecording = true;

    print('Recording started. CSV file reset.');
  }

  // Stop recording data
  Future<void> stopRecording() async {
    if (_isRecording) {
      await _sink.flush(); // Ensure all buffered data is written
      await _sink.close(); // Close the file
      _isRecording = false;

      print('CSV file saved successfully at: ${_file.path}');
    }
  }

  // Buffer data instead of saving it immediately
  void bufferData(double timestamp, double accX, double accY, double accZ,
      double gyroX, double gyroY, double gyroZ) {
    if (_isRecording) {
      // Convert relative timestamp to absolute timestamp (milliseconds since epoch)
      final absoluteTimestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

      // Add platform information
      final platform =
          Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : 'Unknown');

      // Calculate L2 norm for gyroscope data
      double l2Norm = sqrt(gyroX * gyroX + gyroY * gyroY + gyroZ * gyroZ);

      // Add data to buffer with L2 norm already calculated
      _dataBuffer.add([
        absoluteTimestamp,
        accX,
        accY,
        accZ,
        gyroX,
        gyroY,
        gyroZ,
        l2Norm,
        platform == 'iOS'
            ? 1
            : 0 // Add platform indicator (1 for iOS, 0 for Android)
      ]);
    }
  }

  void saveBufferedData() {
    if (_isRecording && _dataBuffer.isNotEmpty) {
      // Process each row in the buffer
      for (List<double> row in _dataBuffer) {
        // Convert row to CSV format
        final csvRow = row.map((value) => value.toStringAsFixed(2)).toList();
        _sink.writeln(ListToCsvConverter().convert([csvRow]));
      }

      // Clear buffer after writing
      _dataBuffer.clear();
    }
  }

  // Clear the buffer (discard unsaved data)
  void clearBuffer() {
    _dataBuffer.clear(); // Clear the buffer without saving the data
  }

  // Save a message to the CSV file
  void saveMessage(double timestamp, String message) {
    if (_isRecording) {
      final absoluteTimestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final platform =
          Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : 'Unknown');
      _sink.writeln('$absoluteTimestamp, $message, $platform');
    }
  }
}
