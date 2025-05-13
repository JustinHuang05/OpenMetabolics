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
import kotlin.math.abs

class SensorRecordingService : Service(), SensorEventListener {
    private lateinit var sensorManager: SensorManager
    private var accelerometer: Sensor? = null
    private var gyroscope: Sensor? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var stopLatch: CountDownLatch? = null
    private var methodChannel: io.flutter.plugin.common.MethodChannel? = null
    private var isRecording = false
    private var sessionId: String? = null
    private var targetInterval: Long = 20000000 // 20ms in nanoseconds
    private var lastSampleTime: Long = 0
    private var sampleCount: Int = 0
    private var lastLogTime: Long = 0
    private var sessionStartTime: Long = 0
    private var totalSamples: Int = 0
    private var totalTime: Long = 0
    private var lastAdjustmentTime: Long = 0
    private var currentInterval: Long = 20000000 // Start with 20ms
    private val adjustmentThreshold = 0.1 // 10% deviation threshold
    private val minInterval = 15000000L // 15ms minimum
    private val maxInterval = 25000000L // 25ms maximum
    private val adjustmentInterval = 1000000000L // Check every second

    // Variables to store the latest sensor data
    private var accelerometerData: FloatArray = FloatArray(3)
    private var gyroscopeData: FloatArray = FloatArray(3)

    // CSV writing variables
    private var csvFile: File? = null
    private var csvWriter: FileWriter? = null
    private val dataBuffer = mutableListOf<String>()
    private val bufferSize = 200 // Save every 200 readings
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    // Sampling rate tracking
    private var lastGyroTimestamp: Long = 0
    private var samplingRate: Int = 50 // Default sampling rate

    // Binder given to clients
    private val binder = LocalBinder()

    private var nextSampleTime: Long = 0
    private var timer: Timer? = null
    private var timerTask: TimerTask? = null
    private val timerLock = Object()

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
        isRecording = true
        sessionStartTime = System.nanoTime()
        lastSampleTime = sessionStartTime
        nextSampleTime = sessionStartTime
        lastAdjustmentTime = sessionStartTime
        lastLogTime = sessionStartTime

        // Start timer for precise timing
        timer = Timer()
        timerTask =
                object : TimerTask() {
                    override fun run() {
                        synchronized(timerLock) {
                            val currentTime = System.nanoTime()
                            if (currentTime >= nextSampleTime) {
                                // Process sensor data
                                processSensorData()
                                // Schedule next sample
                                nextSampleTime += currentInterval
                            }
                        }
                    }
                }
        timer?.scheduleAtFixedRate(
                timerTask,
                0,
                1
        ) // Run as fast as possible, we'll control timing manually
    }

    private fun processSensorData() {
        if (!isRecording) return

        val currentTime = System.nanoTime()

        // Calculate actual sampling rate
        val timeSinceLastSample = currentTime - lastSampleTime
        val currentRate =
                if (timeSinceLastSample > 0) {
                    1_000_000_000.0 / timeSinceLastSample
                } else {
                    0.0
                }

        // Update statistics
        sampleCount++
        totalSamples++
        totalTime += timeSinceLastSample

        // Check if it's time to adjust the sampling rate
        if (currentTime - lastAdjustmentTime >= adjustmentInterval) {
            val averageRate =
                    if (totalTime > 0) {
                        totalSamples * 1_000_000_000.0 / totalTime
                    } else {
                        0.0
                    }

            // Calculate adjustment needed
            val rateError = (averageRate - 50.0) / 50.0 // Normalized error

            if (abs(rateError) > adjustmentThreshold) {
                // Adjust the interval to compensate
                val adjustment = (currentInterval * rateError * 0.1).toLong() // 10% adjustment
                currentInterval = (currentInterval - adjustment).coerceIn(minInterval, maxInterval)

                // Log the adjustment
                android.util.Log.d(
                        "SensorRecording",
                        "Adjusting sampling rate: " +
                                "Current: ${String.format("%.2f", averageRate)} Hz, " +
                                "Target: 50.00 Hz, " +
                                "New interval: ${currentInterval / 1_000_000.0} ms"
                )
            }

            // Reset statistics for next adjustment period
            sampleCount = 0
            totalSamples = 0
            totalTime = 0
            lastAdjustmentTime = currentTime
        }

        // Log every 5 seconds
        if (currentTime - lastLogTime >= 5_000_000_000) {
            val rate =
                    if (currentTime - lastLogTime > 0) {
                        sampleCount * 1_000_000_000.0 / (currentTime - lastLogTime)
                    } else {
                        0.0
                    }

            val totalRate =
                    if (currentTime - sessionStartTime > 0) {
                        totalSamples * 1_000_000_000.0 / (currentTime - sessionStartTime)
                    } else {
                        0.0
                    }

            // Send detailed stats to Flutter
            methodChannel?.invokeMethod(
                    "onSamplingStatsUpdate",
                    mapOf(
                            "currentRate" to rate,
                            "averageRate" to totalRate,
                            "totalSamples" to totalSamples,
                            "timeElapsed" to (currentTime - sessionStartTime) / 1_000_000_000.0,
                            "wakeLockActive" to (wakeLock?.isHeld ?: false),
                            "targetInterval" to currentInterval / 1_000_000.0
                    )
            )

            sampleCount = 0
            lastLogTime = currentTime
        }

        // Send real-time rate to Flutter
        methodChannel?.invokeMethod(
                "onSamplingRateUpdate",
                mapOf("rate" to currentRate, "totalSamples" to totalSamples)
        )

        lastSampleTime = currentTime
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    override fun onDestroy() {
        isRecording = false
        timerTask?.cancel()
        timer?.cancel()
        timer = null
        timerTask = null
        android.util.Log.d("SensorRecording", "Service onDestroy")
        super.onDestroy()
        sensorManager.unregisterListener(this)
        saveBufferedData()
        csvWriter?.close()
        wakeLock?.release()
        stopLatch?.countDown()
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (!isRecording) return

        val currentTime = System.nanoTime()

        // Calculate actual sampling rate
        val timeSinceLastSample = currentTime - lastSampleTime
        val currentRate =
                if (timeSinceLastSample > 0) {
                    1_000_000_000.0 / timeSinceLastSample
                } else {
                    0.0
                }

        // Update statistics
        sampleCount++
        totalSamples++
        totalTime += timeSinceLastSample

        // Check if it's time to adjust the sampling rate
        if (currentTime - lastAdjustmentTime >= adjustmentInterval) {
            val averageRate =
                    if (totalTime > 0) {
                        totalSamples * 1_000_000_000.0 / totalTime
                    } else {
                        0.0
                    }

            // Calculate adjustment needed
            val rateError = (averageRate - 50.0) / 50.0 // Normalized error

            if (abs(rateError) > adjustmentThreshold) {
                // Adjust the interval to compensate
                val adjustment = (currentInterval * rateError * 0.1).toLong() // 10% adjustment
                currentInterval = (currentInterval - adjustment).coerceIn(minInterval, maxInterval)

                // Log the adjustment
                android.util.Log.d(
                        "SensorRecording",
                        "Adjusting sampling rate: " +
                                "Current: ${String.format("%.2f", averageRate)} Hz, " +
                                "Target: 50.00 Hz, " +
                                "New interval: ${currentInterval / 1_000_000.0} ms"
                )
            }

            // Reset statistics for next adjustment period
            sampleCount = 0
            totalSamples = 0
            totalTime = 0
            lastAdjustmentTime = currentTime
        }

        // Log every 5 seconds
        if (currentTime - lastLogTime >= 5_000_000_000) {
            val rate =
                    if (currentTime - lastLogTime > 0) {
                        sampleCount * 1_000_000_000.0 / (currentTime - lastLogTime)
                    } else {
                        0.0
                    }

            val totalRate =
                    if (currentTime - sessionStartTime > 0) {
                        totalSamples * 1_000_000_000.0 / (currentTime - sessionStartTime)
                    } else {
                        0.0
                    }

            // Send detailed stats to Flutter
            methodChannel?.invokeMethod(
                    "onSamplingStatsUpdate",
                    mapOf(
                            "currentRate" to rate,
                            "averageRate" to totalRate,
                            "totalSamples" to totalSamples,
                            "timeElapsed" to (currentTime - sessionStartTime) / 1_000_000_000.0,
                            "wakeLockActive" to (wakeLock?.isHeld ?: false),
                            "targetInterval" to currentInterval / 1_000_000.0
                    )
            )

            sampleCount = 0
            lastLogTime = currentTime
        }

        // Send real-time rate to Flutter
        methodChannel?.invokeMethod(
                "onSamplingRateUpdate",
                mapOf("rate" to currentRate, "totalSamples" to totalSamples)
        )

        lastSampleTime = currentTime
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
