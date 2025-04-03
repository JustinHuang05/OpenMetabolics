import 'package:flutter/services.dart';
import 'dart:io' show Platform;

class SensorChannel {
  static const MethodChannel _channel = MethodChannel('sensor_channel');

  // Method to start the sensors
  static Future<void> startSensors() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await _channel.invokeMethod('startSensors');
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
  static Future<List<double>> getAccelerometerData() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final result =
          await _channel.invokeMethod<List<dynamic>>('getAccelerometerData');

      // Both platforms now return both accelerometer and gyroscope data together
      // Return only the accelerometer data (first 3 values)
      return result!.sublist(0, 3).map((e) => e as double).toList();
    } else {
      throw PlatformException(
        code: 'UNSUPPORTED_PLATFORM',
        message: 'This platform does not support sensor functionality',
      );
    }
  }

  // Method to get gyroscope data
  static Future<List<double>> getGyroscopeData() async {
    if (Platform.isAndroid || Platform.isIOS) {
      // For both platforms, we can get gyroscope data from the accelerometer call
      // This ensures we get the most recent gyroscope data
      final accResult =
          await _channel.invokeMethod<List<dynamic>>('getAccelerometerData');

      // Return only the gyroscope data (last 3 values)
      return accResult!.sublist(3, 6).map((e) => e as double).toList();
    } else {
      throw PlatformException(
        code: 'UNSUPPORTED_PLATFORM',
        message: 'This platform does not support sensor functionality',
      );
    }
  }
}
