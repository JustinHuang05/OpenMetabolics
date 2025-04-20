package com.example.open_metabolics_app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
                    SensorRecordingService.startService(this)
                    Intent(this, SensorRecordingService::class.java).also { intent ->
                        bindService(intent, connection, Context.BIND_AUTO_CREATE)
                    }
                    result.success(null)
                }
                "stopSensors" -> {
                    if (isBound) {
                        unbindService(connection)
                        isBound = false
                    }
                    SensorRecordingService.stopService(this)
                    result.success(null)
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
                else -> {
                    result.notImplemented()
                }
            }
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
