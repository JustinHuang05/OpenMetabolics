package com.openmetabolics.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileWriter
import java.text.DecimalFormat
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.sqrt

class SensorRecordingService : Service(), SensorEventListener {
    private lateinit var sensorManager: SensorManager
    private var accelerometer: Sensor? = null
    private var gyroscope: Sensor? = null

    // Variables to store the latest sensor data
    private val accelerometerData = FloatArray(3)
    private val gyroscopeData = FloatArray(3)

    // CSV writing variables
    private var csvFile: File? = null
    private var csvWriter: FileWriter? = null
    private var sessionId: String? = null
    private var startTime: Long = 0
    private val dataBuffer = mutableListOf<String>()
    private val bufferSize = 200 // Save every 200 readings
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    // Monitoring variables
    private var sampleCount: Long = 0
    private var lastReportTime: Long = 0
    private val reportInterval: Long = 1000 // Report every second
    private var lastBufferSaveTime: Long = 0
    private var totalSamples: Long = 0

    // Binder given to clients
    private val binder = LocalBinder()

    // Add these as class variables
    private val stringBuilder = StringBuilder(256) // Pre-allocate buffer for CSV rows
    private val timestampFormat = DecimalFormat("0.000")
    private val valueFormat = DecimalFormat("0.00")
    private var lastGyroTimestamp: Long = 0
    private var lastAccelTimestamp: Long = 0

    inner class LocalBinder : Binder() {
        fun getService(): SensorRecordingService = this@SensorRecordingService
    }

    companion object {
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "sensor_recording_channel"
        private const val CHANNEL_NAME = "Sensor Recording"

        fun startService(context: Context, sessionId: String) {
            val intent =
                    Intent(context, SensorRecordingService::class.java).apply {
                        putExtra("sessionId", sessionId)
                    }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            val intent = Intent(context, SensorRecordingService::class.java)
            context.stopService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())

        // Initialize sensor manager
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        gyroscope = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

        // Start sensor listeners at 50Hz
        startSensors()

        // Initialize monitoring variables
        lastReportTime = System.currentTimeMillis()
        lastBufferSaveTime = System.currentTimeMillis()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let {
            sessionId = it.getStringExtra("sessionId")
            startTime = System.currentTimeMillis()
            initializeCSV()
        }
        return START_STICKY
    }

    private fun initializeCSV() {
        try {
            val directory = getExternalFilesDir(null)
            csvFile = File(directory, "sensor_data_${sessionId}.csv")
            csvWriter = FileWriter(csvFile, true)

            // Write header if file is new
            if (csvFile?.length() == 0L) {
                csvWriter?.write(
                        "Timestamp,Accelerometer_X,Accelerometer_Y,Accelerometer_Z,Gyroscope_X,Gyroscope_Y,Gyroscope_Z,L2_Norm,Platform\n"
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel =
                    NotificationChannel(
                            CHANNEL_ID,
                            CHANNEL_NAME,
                            NotificationManager.IMPORTANCE_LOW
                    )
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)

        return NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("Sensor Recording")
                .setContentText("Recording sensor data in background")
                .setSmallIcon(android.R.drawable.ic_menu_compass)
                .setContentIntent(pendingIntent)
                .build()
    }

    private fun startSensors() {
        accelerometer?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }

        gyroscope?.let { sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    override fun onDestroy() {
        super.onDestroy()
        sensorManager.unregisterListener(this)
        saveBufferedData()
        csvWriter?.close()
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                System.arraycopy(event.values, 0, accelerometerData, 0, 3)
                lastAccelTimestamp = event.timestamp
            }
            Sensor.TYPE_GYROSCOPE -> {
                System.arraycopy(event.values, 0, gyroscopeData, 0, 3)
                lastGyroTimestamp = event.timestamp

                // Calculate L2 norm for gyroscope data
                val l2Norm =
                        sqrt(
                                gyroscopeData[0] * gyroscopeData[0] +
                                        gyroscopeData[1] * gyroscopeData[1] +
                                        gyroscopeData[2] * gyroscopeData[2]
                        )

                // Create CSV row using StringBuilder
                stringBuilder.setLength(0) // Clear the buffer
                stringBuilder
                        .append(timestampFormat.format(System.currentTimeMillis() / 1000.0))
                        .append(',')
                        .append(valueFormat.format(accelerometerData[0]))
                        .append(',')
                        .append(valueFormat.format(accelerometerData[1]))
                        .append(',')
                        .append(valueFormat.format(accelerometerData[2]))
                        .append(',')
                        .append(valueFormat.format(gyroscopeData[0]))
                        .append(',')
                        .append(valueFormat.format(gyroscopeData[1]))
                        .append(',')
                        .append(valueFormat.format(gyroscopeData[2]))
                        .append(',')
                        .append(valueFormat.format(l2Norm))
                        .append(",0\n")

                dataBuffer.add(stringBuilder.toString())
                sampleCount++
                totalSamples++

                // Save data if buffer is full
                if (dataBuffer.size >= bufferSize) {
                    val now = System.currentTimeMillis()
                    val timeSinceLastSave = now - lastBufferSaveTime
                    println(
                            "Buffer full - Time since last save: ${timeSinceLastSave}ms, Total samples: $totalSamples"
                    )
                    saveBufferedData()
                    lastBufferSaveTime = now
                }

                // Report sampling rate every second
                val now = System.currentTimeMillis()
                if (now - lastReportTime >= reportInterval) {
                    val actualRate = sampleCount * 1000.0 / (now - lastReportTime)
                    println("Current sampling rate: $actualRate Hz (Target: 50Hz)")
                    sampleCount = 0
                    lastReportTime = now
                }
            }
        }
    }

    private fun saveBufferedData() {
        try {
            val writer = csvWriter ?: return
            for (row in dataBuffer) {
                writer.write(row)
            }
            writer.flush()
            dataBuffer.clear()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Not needed for this implementation
    }

    fun getSensorData(): List<Double> {
        return listOf(
                accelerometerData[0].toDouble(),
                accelerometerData[1].toDouble(),
                accelerometerData[2].toDouble(),
                gyroscopeData[0].toDouble(),
                gyroscopeData[1].toDouble(),
                gyroscopeData[2].toDouble()
        )
    }

    fun getCurrentSessionFilePath(): String? {
        return csvFile?.absolutePath
    }
}
