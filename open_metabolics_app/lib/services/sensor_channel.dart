import 'package:flutter/services.dart';
import 'dart:io' show Platform;

class SensorChannel {
  static const MethodChannel _channel = MethodChannel('sensor_channel');

  // Method to start the sensors
  static Future<void> startSensors(String sessionId) async {
    if (Platform.isAndroid || Platform.isIOS) {
      await _channel.invokeMethod('startSensors', {'sessionId': sessionId});
    } else {
      throw PlatformException(
        code: 'UNSUPPORTED_PLATFORM',
        message: 'This platform does not support sensor functionality',
      );
    }
  }

  // Method to stop the sensors
  static Future<void> stopSensors() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await _channel.invokeMethod('stopSensors');
    } else {
      throw PlatformException(
        code: 'UNSUPPORTED_PLATFORM',
        message: 'This platform does not support sensor functionality',
      );
    }
  }

  // Method to get accelerometer data
  // On Android, this returns both accelerometer and gyroscope data
  static Future<List<double>> getAccelerometerData() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final result =
          await _channel.invokeMethod<List<dynamic>>('getAccelerometerData');

      // Check if we're on Android and the result has 6 elements (3 for accel, 3 for gyro)
      if (Platform.isAndroid && result!.length == 6) {
        // Return just the accelerometer part (first 3 elements)
        return result.sublist(0, 3).map((e) => e as double).toList();
      } else {
        // For iOS or other cases, return the full result
        return result!.map((e) => e as double).toList();
      }
    } else {
      throw PlatformException(
        code: 'UNSUPPORTED_PLATFORM',
        message: 'This platform does not support sensor functionality',
      );
    }
  }

  // Method to get gyroscope data
  // On Android, this returns just the gyroscope part from the combined data
  static Future<List<double>> getGyroscopeData() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final result =
          await _channel.invokeMethod<List<dynamic>>('getAccelerometerData');

      // Check if we're on Android and the result has 6 elements (3 for accel, 3 for gyro)
      if (Platform.isAndroid && result!.length == 6) {
        // Return just the gyroscope part (last 3 elements)
        return result.sublist(3, 6).map((e) => e as double).toList();
      } else {
        // For iOS or other cases, use the dedicated gyroscope method
        final gyroResult =
            await _channel.invokeMethod<List<dynamic>>('getGyroscopeData');
        return gyroResult!.map((e) => e as double).toList();
      }
    } else {
      throw PlatformException(
        code: 'UNSUPPORTED_PLATFORM',
        message: 'This platform does not support sensor functionality',
      );
    }
  }

  // Method to get the current session's file path
  static Future<String?> getCurrentSessionFilePath() async {
    if (Platform.isAndroid) {
      return await _channel.invokeMethod<String>('getCurrentSessionFilePath');
    }
    return null;
  }
}
