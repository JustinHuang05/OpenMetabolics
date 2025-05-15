package com.openmetabolics.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
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
    private var currentFilePath: String? = null
    private var isFileInitialized = false

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

    // Add SharedPreferences member
    private lateinit var sharedPreferences: SharedPreferences

    private var wakeLock: PowerManager.WakeLock? = null

    inner class LocalBinder : Binder() {
        fun getService(): SensorRecordingService = this@SensorRecordingService
    }

    companion object {
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "sensor_recording_channel"
        private const val CHANNEL_NAME = "Sensor Recording"
        private const val WAKE_LOCK_TAG = "OpenMetabolics::SensorWakeLock"

        // SharedPreferences constants
        private const val PREFS_NAME = "SensorServicePrefs"
        private const val KEY_SESSION_ID = "lastSessionId"
        private const val KEY_START_TIME = "lastStartTime"
        private const val KEY_FILE_PATH = "lastFilePath"

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

            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            with(prefs.edit()) {
                remove(KEY_SESSION_ID)
                remove(KEY_START_TIME)
                remove(KEY_FILE_PATH)
                apply()
            }
            println("SensorService: stopService called, cleared persisted state.")
        }
    }

    override fun onCreate() {
        super.onCreate()
        sharedPreferences = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())

        // Initialize PowerManager and WakeLock
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock =
                powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
                    setReferenceCounted(false)
                }

        // Initialize sensor manager
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        gyroscope = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

        // Start sensor listeners
        startSensors()

        // Initialize monitoring variables
        lastReportTime = System.currentTimeMillis()
        lastBufferSaveTime = System.currentTimeMillis()
        println("SensorService: onCreate, WakeLock initialized.")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        var explicitSessionId: String? = null
        var isRestart = false

        if (intent == null) {
            isRestart = true
            println("SensorService: Restarted by system.")
            explicitSessionId = sharedPreferences.getString(KEY_SESSION_ID, null)
            if (explicitSessionId != null) {
                println(
                        "SensorService: Restored sessionId $explicitSessionId from SharedPreferences."
                )
            } else {
                println("SensorService: Could not restore sessionId. Stopping service.")
                stopSelf()
                return START_NOT_STICKY
            }
        } else {
            explicitSessionId = intent.getStringExtra("sessionId")
            println("SensorService: Started with explicit sessionId $explicitSessionId.")
        }

        if (explicitSessionId != null) {
            if (this.sessionId != explicitSessionId || !isFileInitialized) {
                this.sessionId = explicitSessionId
                this.startTime =
                        if (isRestart) {
                            sharedPreferences.getLong(KEY_START_TIME, System.currentTimeMillis())
                        } else {
                            System.currentTimeMillis()
                        }
                initializeCSV()

                if (isFileInitialized) {
                    with(sharedPreferences.edit()) {
                        putString(KEY_SESSION_ID, this@SensorRecordingService.sessionId)
                        putLong(KEY_START_TIME, this@SensorRecordingService.startTime)
                        apply()
                    }
                    println("SensorService: Saved state for sessionId ${this.sessionId}.")

                    // Acquire WakeLock now that initialization is successful
                    if (wakeLock?.isHeld == false) {
                        wakeLock?.acquire()
                        println("SensorService: WakeLock acquired for session ${this.sessionId}.")
                    }
                } else {
                    println(
                            "SensorService: Failed to initialize CSV for sessionId ${this.sessionId}. State not saved. Stopping."
                    )
                    clearPersistedState()
                    stopSelf()
                    return START_NOT_STICKY
                }
            } else {
                println(
                        "SensorService: Already running with sessionId ${this.sessionId}. No re-initialization needed."
                )
                // Ensure WakeLock is held if service is already running for this session
                if (isFileInitialized && wakeLock?.isHeld == false) {
                    wakeLock?.acquire()
                    println(
                            "SensorService: WakeLock re-acquired for ongoing session ${this.sessionId}."
                    )
                }
            }
        } else {
            println("SensorService: No sessionId provided. Stopping service.")
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    private fun initializeCSV() {
        try {
            if (sessionId == null) {
                println("Error: sessionId is null for initializeCSV")
                isFileInitialized = false
                return
            }

            val directory = getExternalFilesDir(null)
            if (directory == null) {
                println("Error: Could not get external files directory")
                return
            }

            // Close any existing writer
            csvWriter?.close()

            // Create new file
            csvFile = File(directory, "sensor_data_${sessionId}.csv")
            currentFilePath = csvFile?.absolutePath

            if (currentFilePath == null) {
                println("Error: Could not get absolute path for CSV file")
                return
            }

            csvWriter = FileWriter(csvFile, true)

            // Write header if file is new
            if (csvFile?.length() == 0L) {
                csvWriter?.write(
                        "Timestamp,Accelerometer_X,Accelerometer_Y,Accelerometer_Z,Gyroscope_X,Gyroscope_Y,Gyroscope_Z,L2_Norm,Platform\n"
                )
            }

            isFileInitialized = true
            println("CSV file initialized at: $currentFilePath")
        } catch (e: Exception) {
            e.printStackTrace()
            println("Error initializing CSV: ${e.message}")
            isFileInitialized = false
            currentFilePath = null
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
        try {
            sensorManager.unregisterListener(this)
            if (isFileInitialized) {
                saveBufferedData()
                csvWriter?.close()
                println("Service destroyed. Final file path: $currentFilePath")
            } else {
                println("Service destroyed but no file was initialized")
            }
        } catch (e: Exception) {
            e.printStackTrace()
            println("Error in onDestroy: ${e.message}")
        }

        // Release WakeLock
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
            println("SensorService: WakeLock released.")
        }

        // The call to clearPersistedState() in stopService companion method is
        // generally preferred for explicit stops.
        // If you want to clear state when the service is destroyed for any reason:
        // clearPersistedState()
        println("SensorService: onDestroy called.")
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
                stringBuilder.setLength(0)
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
            if (!isFileInitialized) {
                println("Error: File not initialized, cannot save data")
                return
            }

            val writer =
                    csvWriter
                            ?: run {
                                println("Error: CSV writer is null, reinitializing...")
                                initializeCSV()
                                return
                            }

            if (dataBuffer.isNotEmpty()) {
                for (row in dataBuffer) {
                    writer.write(row)
                }
                writer.flush()
                println("Saved ${dataBuffer.size} rows to file: $currentFilePath")
                dataBuffer.clear()
            }
        } catch (e: Exception) {
            e.printStackTrace()
            println("Error saving buffered data: ${e.message}")
            // Try to recover by reinitializing
            isFileInitialized = false
            initializeCSV()
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
        if (!isFileInitialized) {
            println("Warning: Getting file path but file is not initialized")
            return null
        }
        val path = currentFilePath
        println("Getting current session file path: $path")
        return path
    }

    // Helper to clear persisted state if needed
    private fun clearPersistedState() {
        with(sharedPreferences.edit()) {
            remove(KEY_SESSION_ID)
            remove(KEY_START_TIME)
            remove(KEY_FILE_PATH)
            apply()
        }
        println("SensorService: Cleared persisted state.")
    }
}
