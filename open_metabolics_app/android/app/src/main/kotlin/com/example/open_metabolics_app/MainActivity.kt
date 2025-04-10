package com.example.open_metabolics_app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity(), SensorEventListener {
    private val CHANNEL = "sensor_channel"
    private lateinit var sensorManager: SensorManager
    private var accelerometer: Sensor? = null
    private var gyroscope: Sensor? = null
    private var channel: MethodChannel? = null

    // Variables to store the latest sensor data
    private var accelerometerData: FloatArray = FloatArray(3)
    private var gyroscopeData: FloatArray = FloatArray(3)

    // Flag to track if we have new data from both sensors
    private val hasNewAccelerometerData = AtomicBoolean(false)
    private val hasNewGyroscopeData = AtomicBoolean(false)

    // Timestamp of the last data sent to Flutter
    private var lastDataSentTime: Long = 0

    // Minimum time between data sends (in milliseconds)
    private val minDataSendInterval: Long = 20 // 50Hz sampling rate

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize the method channel
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        // Initialize sensor manager
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        gyroscope = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

        // Set up method call handler
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startSensors" -> {
                    startSensors()
                    result.success(null)
                }
                "stopSensors" -> {
                    stopSensors()
                    result.success(null)
                }
                "getAccelerometerData" -> {
                    // Return both accelerometer and gyroscope data together
                    val currentTime = System.currentTimeMillis()
                    if (currentTime - lastDataSentTime >= minDataSendInterval) {
                        lastDataSentTime = currentTime
                        result.success(
                                listOf(
                                        accelerometerData[0].toDouble(),
                                        accelerometerData[1].toDouble(),
                                        accelerometerData[2].toDouble(),
                                        gyroscopeData[0].toDouble(),
                                        gyroscopeData[1].toDouble(),
                                        gyroscopeData[2].toDouble()
                                )
                        )
                    } else {
                        // If not enough time has passed, return the last data
                        result.success(
                                listOf(
                                        accelerometerData[0].toDouble(),
                                        accelerometerData[1].toDouble(),
                                        accelerometerData[2].toDouble(),
                                        gyroscopeData[0].toDouble(),
                                        gyroscopeData[1].toDouble(),
                                        gyroscopeData[2].toDouble()
                                )
                        )
                    }
                }
                "getGyroscopeData" -> {
                    // For backward compatibility, still return just gyroscope data
                    result.success(
                            listOf(
                                    gyroscopeData[0].toDouble(),
                                    gyroscopeData[1].toDouble(),
                                    gyroscopeData[2].toDouble()
                            )
                    )
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startSensors() {
        // Reset flags
        hasNewAccelerometerData.set(false)
        hasNewGyroscopeData.set(false)
        lastDataSentTime = 0

        // Register sensor listeners
        accelerometer?.let {
            sensorManager.registerListener(
                    this,
                    it,
                    SensorManager.SENSOR_DELAY_GAME // ~20ms between updates
            )
        }

        gyroscope?.let {
            sensorManager.registerListener(
                    this,
                    it,
                    SensorManager.SENSOR_DELAY_GAME // ~20ms between updates
            )
        }
    }

    private fun stopSensors() {
        // Unregister sensor listeners
        sensorManager.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                // Store accelerometer data
                System.arraycopy(event.values, 0, accelerometerData, 0, 3)
                hasNewAccelerometerData.set(true)
            }
            Sensor.TYPE_GYROSCOPE -> {
                // Store gyroscope data
                System.arraycopy(event.values, 0, gyroscopeData, 0, 3)
                hasNewGyroscopeData.set(true)

                // Add debug logging
                android.util.Log.d(
                        "Gyroscope",
                        "Raw gyro values - X: ${event.values[0]}, Y: ${event.values[1]}, Z: ${event.values[2]}"
                )
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Not needed for this implementation
    }

    override fun onDestroy() {
        super.onDestroy()
        // Make sure to unregister listeners when the activity is destroyed
        stopSensors()
    }
}
