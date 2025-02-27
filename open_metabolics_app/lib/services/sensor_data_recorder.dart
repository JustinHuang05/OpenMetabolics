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
      'Timestamp,Accelerometer_X,Accelerometer_Y,Accelerometer_Z,Gyroscope_X,Gyroscope_Y,Gyroscope_Z,L2_Norm',
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
      _dataBuffer.add([timestamp, accX, accY, accZ, gyroX, gyroY, gyroZ]);
    }
  }

  void saveBufferedData() {
    if (_isRecording && _dataBuffer.isNotEmpty) {
      // Process data in pairs of two rows
      for (int i = 0; i < _dataBuffer.length; i += 2) {
        List<double> row1 = _dataBuffer[i];

        if (i + 1 < _dataBuffer.length) {
          // Replace gyroscope data in the first row with that from the second row
          List<double> row2 = _dataBuffer[i + 1];

          row1[4] = row2[4]; // Gyroscope_X
          row1[5] = row2[5]; // Gyroscope_Y
          row1[6] = row2[6]; // Gyroscope_Z

          // ✅ Calculate L2 norm (Euclidean norm) for the updated gyroscope data
          double l2Norm =
              sqrt(row1[4] * row1[4] + row1[5] * row1[5] + row1[6] * row1[6]);

          // ✅ Append L2 norm to the row
          final csvRow = row1.map((value) => value.toStringAsFixed(2)).toList()
            ..add(l2Norm.toStringAsFixed(2));

          _sink.writeln(ListToCsvConverter().convert([csvRow]));
        } else {
          // If there's an odd row left, just save it as is
          double l2Norm =
              sqrt(row1[4] * row1[4] + row1[5] * row1[5] + row1[6] * row1[6]);

          final csvRow = row1.map((value) => value.toStringAsFixed(2)).toList()
            ..add(l2Norm.toStringAsFixed(2));

          _sink.writeln(ListToCsvConverter().convert([csvRow]));
        }
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
      _sink.writeln('$timestamp, $message');
    }
  }
}
