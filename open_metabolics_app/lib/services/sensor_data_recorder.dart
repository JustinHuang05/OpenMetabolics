import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
// import 'package:csv/csv.dart'; // ListToCsvConverter not strictly needed for simple row writing
import 'package:path/path.dart' as p;
import 'dart:math'; // ✅ Import math for L2 norm calculation

class SensorDataRecorder {
  late File _file; // Will be initialized for the instance
  IOSink? _sink; // Made nullable, will be initialized in startRecording
  bool _isRecording = false;
  final String sessionId; // Session ID is now final and set by constructor

  // Buffer to hold rows of data for this instance
  List<List<double>> _dataBuffer = [];

  // Constructor takes a session ID
  SensorDataRecorder({required this.sessionId});

  // Initialize and create a CSV file (overwrite mode)
  Future<void> _initializeFile() async {
    // No longer takes sessionId as param
    final directory = await getApplicationDocumentsDirectory();
    // Use the instance's sessionId
    final path = p.join(directory.path, 'sensor_data_$sessionId.csv');
    _file = File(path);

    // Open the file in write mode to overwrite any existing content
    try {
      _sink = _file.openWrite(mode: FileMode.write);
      // ✅ Add "L2_Norm" to the header
      _sink!.writeln(
        'Timestamp,Accelerometer_X,Accelerometer_Y,Accelerometer_Z,Gyroscope_X,Gyroscope_Y,Gyroscope_Z,L2_Norm,Platform',
      );
    } catch (e) {
      print("Error initializing file/sink for session $sessionId: $e");
      _isRecording = false; // Ensure recording doesn't proceed if sink fails
      rethrow; // Rethrow to allow caller to handle
    }
  }

  // Start recording data (reset file, buffer, and state for this instance)
  Future<bool> startRecording() async {
    // No longer takes sessionId as param
    if (_isRecording) {
      // This instance is already recording, which shouldn't happen if managed correctly.
      // Or, it means stopRecording wasn't called or completed from a previous attempt on this instance.
      print(
          "Warning: startRecording called on an already active recorder instance for session $sessionId. Attempting to stop first.");
      await stopRecording();
    }

    try {
      await _initializeFile(); // Initializes _file and _sink for this.sessionId
      _dataBuffer.clear(); // Clear any previous buffered data
      _isRecording = true;
      print(
          'Recording started. CSV file reset for session $sessionId at path ${_file.path}');
      return true; // Indicate success
    } catch (e) {
      print(
          "Failed to start recording for session $sessionId due to file initialization error: $e");
      _isRecording = false;
      return false; // Indicate failure
    }
  }

  // Stop recording data for this instance
  Future<void> stopRecording() async {
    if (!_isRecording && _sink == null) {
      // Not recording and sink is already null, nothing to do.
      _isRecording = false; // Ensure state is consistent
      return;
    }

    if (_isRecording && _sink != null) {
      try {
        await _sink!.flush();
        await _sink!.close();
        print(
            'CSV file saved successfully for session $sessionId at: ${_file.path}');
      } catch (e) {
        print("Error flushing/closing sink for session $sessionId: $e");
      } finally {
        _sink = null; // Release the sink
        _isRecording = false;
      }
    } else if (_sink != null) {
      // If not recording but sink exists (e.g. error during start), try to close it.
      print("Attempting to close orphaned sink for session $sessionId");
      try {
        await _sink!.close();
      } catch (e) {
        print("Error closing orphaned sink for session $sessionId: $e");
      } finally {
        _sink = null;
      }
    }
    _isRecording = false; // Ensure it's consistently false after stopping
  }

  // Get this instance's session file path
  // This should ideally only be called after startRecording has successfully created _file.
  Future<String> getCurrentSessionFilePath() async {
    // _file is not nullable and is initialized in _initializeFile, which is called by startRecording.
    // If startRecording failed and _file wasn't set, this would throw.
    // A check can be added, or ensure usage flow is correct.
    if (_file == null) {
      // This should ideally not be hit if used correctly
      print(
          "Warning: getCurrentSessionFilePath called before file was initialized for session $sessionId. Constructing path on the fly.");
      final directory = await getApplicationDocumentsDirectory();
      return p.join(directory.path, 'sensor_data_$sessionId.csv');
    }
    return _file.path;
  }

  // Buffer data instead of saving it immediately
  void bufferData(double timestamp, double accX, double accY, double accZ,
      double gyroX, double gyroY, double gyroZ) {
    if (!_isRecording) return; // Use this instance's _isRecording

    final absoluteTimestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final platform =
        Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : 'Unknown');
    double l2Norm = sqrt(gyroX * gyroX + gyroY * gyroY + gyroZ * gyroZ);
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
          ? 1.0
          : 0.0 // Ensure double, and use 1.0/0.0 for clarity with CSV
    ]);
  }

  void saveBufferedData() {
    if (!_isRecording || _dataBuffer.isEmpty || _sink == null)
      return; // Check _sink != null

    try {
      for (List<double> row in _dataBuffer) {
        // Convert row to CSV format string
        final csvRowString =
            row.map((value) => value.toStringAsFixed(2)).join(',');
        _sink!.writeln(csvRowString);
      }
      _dataBuffer.clear(); // Clear buffer after writing
    } catch (e) {
      print("Error writing buffered data for session $sessionId: $e");
      // Decide if we need to stop recording or handle error in a specific way
    }
  }

  // Clear the buffer (discard unsaved data)
  void clearBuffer() {
    _dataBuffer.clear();
  }

  // Save a message to the CSV file
  void saveMessage(double timestamp, String message) {
    if (!_isRecording || _sink == null) return; // Check _sink != null

    final absoluteTimestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final platform =
        Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : 'Unknown');
    // Ensure message is properly formatted for CSV if it contains commas etc.
    // For simplicity, assuming message doesn't contain characters that break CSV structure.
    try {
      _sink!.writeln('$absoluteTimestamp,$message,$platform');
    } catch (e) {
      print("Error writing message for session $sessionId: $e");
    }
  }
}
