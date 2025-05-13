package com.openmetabolics.app

import android.content.ComponentName
import android.content.ServiceConnection
import android.os.IBinder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.openmetabolics.app/sensor_recording"
    private var sensorService: SensorRecordingService? = null
    private var methodChannel: MethodChannel? = null

    private val connection =
            object : ServiceConnection {
                override fun onServiceConnected(className: ComponentName, service: IBinder) {
                    val binder = service as SensorRecordingService.LocalBinder
                    sensorService = binder.getService()
                }

                override fun onServiceDisconnected(arg0: ComponentName) {
                    sensorService = null
                }
            }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startSensors" -> {
                    val sessionId = call.argument<String>("sessionId")
                    val samplingRate = call.argument<Int>("samplingRate") ?: 50

                    if (sessionId != null) {
                        SensorRecordingService.startService(this, sessionId, samplingRate)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Session ID is required", null)
                    }
                }
                "stopSensors" -> {
                    val success = SensorRecordingService.stopService(this)
                    result.success(success)
                }
                "setSensorService" -> {
                    val service = call.argument<SensorRecordingService>("service")
                    if (service != null) {
                        sensorService = service
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Service is required", null)
                    }
                }
                "getAccelerometerData" -> {
                    if (sensorService != null) {
                        val data = sensorService!!.getSensorData()
                        result.success(data)
                    } else {
                        result.success(listOf(0.0, 0.0, 0.0, 0.0, 0.0, 0.0))
                    }
                }
                "getGyroscopeData" -> {
                    if (sensorService != null) {
                        val data = sensorService!!.getSensorData().subList(3, 6)
                        result.success(data)
                    } else {
                        result.success(listOf(0.0, 0.0, 0.0))
                    }
                }
                "getCurrentSessionFilePath" -> {
                    if (sensorService != null) {
                        val path = sensorService!!.getCurrentSessionFilePath()
                        result.success(path)
                    } else {
                        result.success(null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        methodChannel?.setMethodCallHandler(null)
        super.onDestroy()
    }
}
