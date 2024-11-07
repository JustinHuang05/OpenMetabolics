import 'package:flutter/services.dart';

class SensorChannel {
  static const MethodChannel _channel = MethodChannel('sensor_channel');

  // Method to start the sensors
  static Future<void> startSensors() async {
    await _channel.invokeMethod('startSensors');
  }

  // Method to stop the sensors
  static Future<void> stopSensors() async {
    await _channel.invokeMethod('stopSensors');
  }

  // Method to get accelerometer data
  static Future<List<double>> getAccelerometerData() async {
    final result =
        await _channel.invokeMethod<List<dynamic>>('getAccelerometerData');
    return result!.map((e) => e as double).toList();
  }

  // Method to get gyroscope data
  static Future<List<double>> getGyroscopeData() async {
    final result =
        await _channel.invokeMethod<List<dynamic>>('getGyroscopeData');
    return result!.map((e) => e as double).toList();
  }
}
