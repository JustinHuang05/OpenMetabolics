import 'dart:io';
import 'package:flutter/services.dart';

class WorkoutService {
  static const MethodChannel _channel = MethodChannel('workout_mode_channel');

  // Start Workout Mode
  Future<void> startWorkoutMode() async {
    if (Platform.isIOS) {
      try {
        await _channel.invokeMethod('startWorkoutMode');
      } on PlatformException catch (e) {
        print("Failed to start workout mode: '${e.message}'.");
      }
    }
  }

  // Stop Workout Mode
  Future<void> stopWorkoutMode() async {
    if (Platform.isIOS) {
      try {
        await _channel.invokeMethod('stopWorkoutMode');
      } on PlatformException catch (e) {
        print("Failed to stop workout mode: '${e.message}'.");
      }
    }
  }
}
