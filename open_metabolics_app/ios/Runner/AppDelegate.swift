import UIKit
import Flutter
import CoreMotion

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    let motionManager = CMMotionManager()
    var channel: FlutterMethodChannel?
    
    // Variables to store the latest sensor data
    var accelerometerData: [Double] = [0, 0, 0]
    var gyroscopeData: [Double] = [0, 0, 0]
    
    // Timestamp of the last data sent to Flutter
    var lastDataSentTime: TimeInterval = 0
    
    // Minimum time between data sends (in seconds)
    let minDataSendInterval: TimeInterval = 0.02 // 50Hz sampling rate

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
        // Reset timestamp
        lastDataSentTime = 0
        
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 1.0 / 50.0  // 50 Hz
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
                guard let data = data else { return }
                self?.accelerometerData = [data.acceleration.x, data.acceleration.y, data.acceleration.z]
            }
        }
        
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 1.0 / 50.0  // 50 Hz
            motionManager.startGyroUpdates(to: .main) { [weak self] (data, error) in
                guard let data = data else { return }
                self?.gyroscopeData = [data.rotationRate.x, data.rotationRate.y, data.rotationRate.z]
            }
        }
        
        result(nil)
    }

    func stopSensors(result: @escaping FlutterResult) {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        result(nil)
    }

    func getAccelerometerData(result: @escaping FlutterResult) {
        let currentTime = Date().timeIntervalSince1970
        
        // Check if enough time has passed since the last data send
        if currentTime - lastDataSentTime >= minDataSendInterval {
            lastDataSentTime = currentTime
            
            // Return both accelerometer and gyroscope data together
            result([
                accelerometerData[0],
                accelerometerData[1],
                accelerometerData[2],
                gyroscopeData[0],
                gyroscopeData[1],
                gyroscopeData[2]
            ])
        } else {
            // If not enough time has passed, return the last data
            result([
                accelerometerData[0],
                accelerometerData[1],
                accelerometerData[2],
                gyroscopeData[0],
                gyroscopeData[1],
                gyroscopeData[2]
            ])
        }
    }

    func getGyroscopeData(result: @escaping FlutterResult) {
        // For backward compatibility, still return just gyroscope data
        result([
            gyroscopeData[0],
            gyroscopeData[1],
            gyroscopeData[2]
        ])
    }
}
