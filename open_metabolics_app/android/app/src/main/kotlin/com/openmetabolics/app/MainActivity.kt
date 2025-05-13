package com.openmetabolics.app

import android.content.ComponentName
import android.content.ServiceConnection
import android.os.Build
import android.os.IBinder
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result

class MainActivity : FlutterActivity() {
    private val CHANNEL = "sensor_channel"
    private var channel: MethodChannel? = null
    private var sensorService: SensorRecordingService? = null
    private var isBound = false

    private val connection =
            object : ServiceConnection {
                override fun onServiceConnected(className: ComponentName, service: IBinder) {
                    val binder = service as SensorRecordingService.LocalBinder
                    sensorService = binder.getService()
                    isBound = true
                }

                override fun onServiceDisconnected(arg0: ComponentName) {
                    isBound = false
                }
            }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize the method channel
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        // Set up method call handler
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startSensors" -> {
                    val sessionId = call.argument<String>("sessionId")
                    val samplingRate = call.argument<Int>("samplingRate")
                    if (sessionId != null && samplingRate != null) {
                        startSensors(sessionId, samplingRate)
                    } else {
                        result.error(
                                "INVALID_SESSION",
                                "Session ID and sampling rate are required",
                                null
                        )
                    }
                }
                "stopSensors" -> {
                    if (isBound) {
                        unbindService(connection)
                        isBound = false
                    }
                    stopSensors(result)
                }
                "getAccelerometerData" -> {
                    if (isBound && sensorService != null) {
                        val data = sensorService!!.getSensorData()
                        result.success(data)
                    } else {
                        result.success(listOf(0.0, 0.0, 0.0, 0.0, 0.0, 0.0))
                    }
                }
                "getGyroscopeData" -> {
                    if (isBound && sensorService != null) {
                        val data = sensorService!!.getSensorData().subList(3, 6)
                        result.success(data)
                    } else {
                        result.success(listOf(0.0, 0.0, 0.0))
                    }
                }
                "getCurrentSessionFilePath" -> {
                    if (isBound && sensorService != null) {
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

    @RequiresApi(Build.VERSION_CODES.O)
    private fun startSensors(sessionId: String, samplingRate: Int) {
        if (sessionId.isBlank()) {
            result.error("INVALID_SESSION", "Session ID is required", null)
            return
        }
        SensorRecordingService.startService(this, sessionId, samplingRate)
        result.success(null)
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun stopSensors(result: Result) {
        try {
            val success = SensorRecordingService.stopService(this)
            if (!success) {
                result.error(
                        "SERVICE_ERROR",
                        "Failed to stop service - data may be incomplete",
                        null
                )
                return
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("SERVICE_ERROR", "Failed to stop service: ${e.message}", null)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isBound) {
            unbindService(connection)
            isBound = false
        }
    }
}
