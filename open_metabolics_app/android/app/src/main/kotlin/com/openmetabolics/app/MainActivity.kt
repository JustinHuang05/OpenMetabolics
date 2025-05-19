package com.openmetabolics.app

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
    private var uploadService: UploadService? = null
    private var isBound = false
    private var isUploadServiceBound = false

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

    private val uploadConnection =
            object : ServiceConnection {
                override fun onServiceConnected(className: ComponentName, service: IBinder) {
                    val binder = service as UploadService.LocalBinder
                    uploadService = binder.getService()
                    isUploadServiceBound = true
                }

                override fun onServiceDisconnected(arg0: ComponentName) {
                    isUploadServiceBound = false
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
                    if (sessionId != null) {
                        SensorRecordingService.startService(this, sessionId)
                        Intent(this, SensorRecordingService::class.java).also { intent ->
                            bindService(intent, connection, Context.BIND_AUTO_CREATE)
                        }
                        result.success(null)
                    } else {
                        result.error("INVALID_SESSION", "Session ID is required", null)
                    }
                }
                "stopSensors" -> {
                    if (isBound) {
                        unbindService(connection)
                        isBound = false
                    }
                    SensorRecordingService.stopService(this)
                    result.success(null)
                }
                "startUpload" -> {
                    UploadService.startService(this)
                    Intent(this, UploadService::class.java).also { intent ->
                        bindService(intent, uploadConnection, Context.BIND_AUTO_CREATE)
                    }
                    result.success(null)
                }
                "stopUpload" -> {
                    if (isUploadServiceBound) {
                        unbindService(uploadConnection)
                        isUploadServiceBound = false
                    }
                    UploadService.stopService(this)
                    result.success(null)
                }
                "setHasActiveUploads" -> {
                    if (isUploadServiceBound && uploadService != null) {
                        val hasActive = call.argument<Boolean>("hasActive") ?: false
                        uploadService!!.setHasActiveUploads(hasActive)
                        result.success(null)
                    } else {
                        result.error("SERVICE_NOT_BOUND", "Upload service not bound", null)
                    }
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
                "setHasActiveSessions" -> {
                    if (isBound && sensorService != null) {
                        val hasActive = call.argument<Boolean>("hasActive") ?: false
                        sensorService!!.setHasActiveSessions(hasActive)
                        result.success(null)
                    } else {
                        result.error("SERVICE_NOT_BOUND", "Service not bound", null)
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
        if (isUploadServiceBound) {
            unbindService(uploadConnection)
            isUploadServiceBound = false
        }
    }
}
