import 'dart:async';
import 'dart:io';
import 'dart:math'; // For L2 norm calculation
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;

class SensorDataRecorder {
  late File _file;
  late IOSink _sink;
  bool _isRecording = false;

  // Buffer to hold rows of data
  List<List<double>> _dataBuffer = [];
  List<double> _l2NormBuffer = []; // Store L2 norms

  // Initialize and create a CSV file (overwrite mode)
  Future<void> _initializeFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, 'sensor_data.csv');

    _file = File(path);

    // Open the file in write mode to overwrite any existing content
    _sink = _file.openWrite(mode: FileMode.write);

    // Always write headers when creating/overwriting the file
    _sink.writeln(
      'Timestamp,Accelerometer_X,Accelerometer_Y,Accelerometer_Z,Gyroscope_X,Gyroscope_Y,Gyroscope_Z,Gyro_L2_Norm',
    );
  }

  // Start recording data (reset file, buffer, and state)
  Future<void> startRecording() async {
    // Ensure any previous recording session is stopped
    await stopRecording();

    // Reinitialize the file and clear buffers
    await _initializeFile();
    _dataBuffer.clear(); // Clear previous buffered data
    _l2NormBuffer.clear(); // Clear L2 norm buffer
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
      // Compute the L2 norm for gyroscope data
      double l2Norm = sqrt(gyroX * gyroX + gyroY * gyroY + gyroZ * gyroZ);

      // Store the sensor data along with L2 norm
      _dataBuffer
          .add([timestamp, accX, accY, accZ, gyroX, gyroY, gyroZ, l2Norm]);
      _l2NormBuffer.add(l2Norm); // Store L2 norm separately for threshold check
    }
  }

  void saveBufferedData() {
    if (_isRecording && _dataBuffer.isNotEmpty) {
      for (int i = 0; i < _dataBuffer.length; i++) {
        List<double> row = _dataBuffer[i];

        // Format the row for CSV output
        final csvRow = row.map((value) => value.toStringAsFixed(2)).toList();
        _sink.writeln(ListToCsvConverter().convert([csvRow]));
      }

      // Clear buffer after writing
      _dataBuffer.clear();
      _l2NormBuffer.clear();
    }
  }

  // Clear the buffer (discard unsaved data)
  void clearBuffer() {
    _dataBuffer.clear(); // Clear the buffer without saving the data
    _l2NormBuffer.clear(); // Also clear the L2 norm buffer
  }

  // Save a message to the CSV file
  void saveMessage(double timestamp, String message) {
    if (_isRecording) {
      _sink.writeln('$timestamp, $message');
    }
  }
}
