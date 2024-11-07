import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;

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

    // Always write headers when creating/overwriting the file
    _sink.writeln(
      'Timestamp,Accelerometer_X,Accelerometer_Y,Accelerometer_Z,Gyroscope_X,Gyroscope_Y,Gyroscope_Z',
    );
  }

  // Start recording data
  Future<void> startRecording() async {
    if (!_isRecording) {
      await _initializeFile(); // Overwrite the file at the start of recording
      _isRecording = true;
    }
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

          // Gyroscope values in row1 (4, 5, 6) replaced by those from row2
          row1[4] = row2[4]; // Gyroscope_X
          row1[5] = row2[5]; // Gyroscope_Y
          row1[6] = row2[6]; // Gyroscope_Z

          // Write the modified first row to the CSV
          final csvRow = row1.map((value) => value.toStringAsFixed(2)).toList();
          _sink.writeln(ListToCsvConverter().convert([csvRow]));

          // Skip the second row, as it's effectively merged with the first one
        } else {
          // If there's an odd row left, just save it as is
          final csvRow = row1.map((value) => value.toStringAsFixed(2)).toList();
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
