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
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.sqrt

class SensorRecordingService : Service(), SensorEventListener {
    private lateinit var sensorManager: SensorManager
    private var accelerometer: Sensor? = null
    private var gyroscope: Sensor? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var stopLatch: CountDownLatch? = null

    // Variables to store the latest sensor data
    private var accelerometerData: FloatArray = FloatArray(3)
    private var gyroscopeData: FloatArray = FloatArray(3)

    // CSV writing variables
    private var csvFile: File? = null
    private var csvWriter: FileWriter? = null
    private var sessionId: String? = null
    private var startTime: Long = 0
    private val dataBuffer = mutableListOf<String>()
    private val bufferSize = 200 // Save every 200 readings
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    // Sampling rate tracking
    private var lastGyroTimestamp: Long = 0
    private var lastLogTime = System.currentTimeMillis()
    private var sampleCount = 0
    private var totalSamples = 0
    private var sessionStartTime = System.currentTimeMillis()
    private var samplingRate: Int = 50 // Default sampling rate

    // Binder given to clients
    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): SensorRecordingService = this@SensorRecordingService
    }

    companion object {
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "sensor_recording_channel"
        private const val CHANNEL_NAME = "Sensor Recording"
        private const val WAKE_LOCK_TAG = "OpenMetabolics:SensorRecording"

        fun startService(context: Context, sessionId: String, samplingRate: Int) {
            val intent =
                    Intent(context, SensorRecordingService::class.java).apply {
                        putExtra("sessionId", sessionId)
                        putExtra("samplingRate", samplingRate)
                    }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context): Boolean {
            val intent = Intent(context, SensorRecordingService::class.java)
            val service = context.getSystemService(Context.BIND_SERVICE) as? SensorRecordingService
            if (service != null) {
                // Wait for the service to finish writing
                return service.waitForCompletion()
            }
            context.stopService(intent)
            return true
        }
    }

    private fun waitForCompletion(): Boolean {
        stopLatch = CountDownLatch(1)
        try {
            // Wait up to 5 seconds for the service to finish writing
            return stopLatch?.await(5, TimeUnit.SECONDS) ?: true
        } catch (e: InterruptedException) {
            return false
        }
    }

    override fun onCreate() {
        super.onCreate()
        android.util.Log.d("SensorRecording", "Service onCreate")
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())

        // Initialize sensor manager
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        gyroscope = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

        // Acquire wake lock with more aggressive settings
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock =
                powerManager.newWakeLock(
                                PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ON_AFTER_RELEASE,
                                WAKE_LOCK_TAG
                        )
                        .apply {
                            setReferenceCounted(false)
                            acquire(10 * 60 * 1000L /*10 minutes*/)
                        }

        // Start sensor listeners
        startSensors()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        android.util.Log.d("SensorRecording", "Service onStartCommand")
        intent?.let {
            sessionId = it.getStringExtra("sessionId")
            samplingRate = it.getIntExtra("samplingRate", 50)
            startTime = System.currentTimeMillis()
            sessionStartTime = startTime
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
        val delay = (1000000 / samplingRate).toInt() // Convert Hz to microseconds
        accelerometer?.let { sensorManager.registerListener(this, it, delay) }

        gyroscope?.let { sensorManager.registerListener(this, it, delay) }
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    override fun onDestroy() {
        android.util.Log.d("SensorRecording", "Service onDestroy")
        super.onDestroy()
        sensorManager.unregisterListener(this)
        saveBufferedData()
        csvWriter?.close()
        wakeLock?.release()
        stopLatch?.countDown()
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                System.arraycopy(event.values, 0, accelerometerData, 0, 3)
            }
            Sensor.TYPE_GYROSCOPE -> {
                System.arraycopy(event.values, 0, gyroscopeData, 0, 3)

                // Track sampling rate
                val currentTime = System.currentTimeMillis()
                sampleCount++
                totalSamples++

                if (currentTime - lastLogTime >= 5000) {
                    val rate = sampleCount * 1000.0 / (currentTime - lastLogTime)
                    val totalRate = totalSamples * 1000.0 / (currentTime - sessionStartTime)
                    android.util.Log.d(
                            "SensorRecording",
                            """
                        Current sampling rate: $rate Hz
                        Average sampling rate: $totalRate Hz
                        Total samples: $totalSamples
                        Time elapsed: ${(currentTime - sessionStartTime) / 1000.0} seconds
                        Wake lock active: ${wakeLock?.isHeld ?: false}
                    """.trimIndent()
                    )
                    sampleCount = 0
                    lastLogTime = currentTime
                }

                // Calculate L2 norm for gyroscope data
                val l2Norm =
                        sqrt(
                                gyroscopeData[0] * gyroscopeData[0] +
                                        gyroscopeData[1] * gyroscopeData[1] +
                                        gyroscopeData[2] * gyroscopeData[2]
                        )

                // Create CSV row
                val timestamp = System.currentTimeMillis() / 1000.0
                val row =
                        String.format(
                                "%.3f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,0\n",
                                timestamp,
                                accelerometerData[0],
                                accelerometerData[1],
                                accelerometerData[2],
                                gyroscopeData[0],
                                gyroscopeData[1],
                                gyroscopeData[2],
                                l2Norm
                        )

                dataBuffer.add(row)

                // Save data if buffer is full
                if (dataBuffer.size >= bufferSize) {
                    saveBufferedData()
                }
            }
        }
    }

    private fun saveBufferedData() {
        try {
            dataBuffer.forEach { row -> csvWriter?.write(row) }
            csvWriter?.flush()
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
