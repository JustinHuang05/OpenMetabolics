import UIKit
import Flutter
import CoreMotion

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    let motionManager = CMMotionManager()
    var channel: FlutterMethodChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window?.rootViewController as! FlutterViewController
        channel = FlutterMethodChannel(name: "sensor_channel", binaryMessenger: controller.binaryMessenger)
        
        channel?.setMethodCallHandler({ [weak self] (call, result) in
            switch call.method {
            case "startSensors":
                self?.startSensors(result: result)
            case "stopSensors":
                self?.stopSensors(result: result)
            case "getAccelerometerData":
                self?.getAccelerometerData(result: result)
            case "getGyroscopeData":
                self?.getGyroscopeData(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        })
        GeneratedPluginRegistrant.register(with: self) // Ensure this is included
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func startSensors(result: @escaping FlutterResult) {
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 1.0 / 100.0  // 100 Hz
            motionManager.startAccelerometerUpdates()
        }
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 1.0 / 100.0  // 100 Hz
            motionManager.startGyroUpdates()
        }
        result(nil)
    }

    func stopSensors(result: @escaping FlutterResult) {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        result(nil)
    }

    func getAccelerometerData(result: @escaping FlutterResult) {
        if let accelerometerData = motionManager.accelerometerData {
            let x = accelerometerData.acceleration.x
            let y = accelerometerData.acceleration.y
            let z = accelerometerData.acceleration.z
            result([x, y, z])
        } else {
            result(FlutterError(code: "UNAVAILABLE", message: "Accelerometer data not available", details: nil))
        }
    }

    func getGyroscopeData(result: @escaping FlutterResult) {
        if let gyroData = motionManager.gyroData {
            let x = gyroData.rotationRate.x
            let y = gyroData.rotationRate.y
            let z = gyroData.rotationRate.z
            result([x, y, z])
        } else {
            result(FlutterError(code: "UNAVAILABLE", message: "Gyroscope data not available", details: nil))
        }
    }
}
