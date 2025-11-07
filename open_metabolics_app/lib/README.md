# OpenMetabolics Flutter Application - Code Documentation

This directory contains the source code for the OpenMetabolics Flutter mobile application. The app enables users to record sensor data from their mobile devices, calculate energy expenditure, and view historical session data.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Directory Structure](#directory-structure)
- [Core Components](#core-components)
- [Data Flow](#data-flow)
- [Configuration](#configuration)
- [Key Features](#key-features)
- [Dependencies](#dependencies)
- [Usage Guide](#usage-guide)
- [Troubleshooting](#troubleshooting)

## Overview

OpenMetabolics is a Flutter application that:

- **Records Sensor Data**: Captures accelerometer and gyroscope data from mobile device sensors
- **Calculates Energy Expenditure**: Processes sensor data to estimate energy expenditure using machine learning models
- **Manages User Profiles**: Stores and manages user demographic data (age, weight, height, gender)
- **Tracks Sessions**: Records and displays historical workout/activity sessions
- **Collects Feedback**: Allows users to provide survey responses for research purposes

The app communicates with AWS backend services (deployed via Terraform) for data storage, processing, and authentication.

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter App                          │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │   UI Layer   │  │  Services    │  │   Models     │ │
│  │  (Pages/     │  │  (Business   │  │  (Data       │ │
│  │   Widgets)   │  │   Logic)     │  │   Structures)│ │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘ │
│         │                  │                  │         │
│  ┌──────┴──────────────────┴──────────────────┴───────┐ │
│  │           State Management (Provider)                │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌──────────────────────────────────────────────────────┐ │
│  │         Native Platform Integration                   │ │
│  │  (Sensors, Notifications, File System)                │ │
│  └──────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌────────────────┐  ┌────────────────┐  ┌────────────────┐
│  AWS Cognito   │  │  API Gateway    │  │  ECS Fargate    │
│  (Auth)        │  │  (Lambda)       │  │  (Processing)   │
└────────────────┘  └────────────────┘  └────────────────┘
         │                    │                    │
         └────────────────────┴────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │    DynamoDB      │
                    │  (Data Storage)   │
                    └─────────────────┘
```

### Key Design Patterns

- **Provider Pattern**: State management using the `provider` package
- **Service Layer**: Business logic separated into service classes
- **Repository Pattern**: Data access abstracted through service classes
- **Platform Channels**: Native code integration for sensors and platform-specific features

## Directory Structure

```
lib/
├── main.dart                    # Application entry point
├── auth/                        # Authentication module
│   ├── amplify_config.dart      # AWS Amplify configuration
│   ├── auth_service.dart        # Authentication business logic
│   ├── auth_wrapper.dart        # Auth state wrapper widget
│   ├── login_page.dart          # Login screen UI
│   ├── signup_page.dart         # Signup screen UI
│   ├── verification_page.dart   # Email verification screen
│   └── user_model.dart          # User data model
├── config/                      # Configuration
│   └── api_config.dart          # API endpoint URLs
├── models/                      # Data models
│   ├── session.dart             # Session data models
│   └── user_profile.dart        # User profile data model
├── pages/                       # Screen UI pages
│   ├── home_page.dart           # Main recording screen
│   ├── past_sessions_page.dart  # History of sessions
│   ├── session_details_page.dart # Detailed session view
│   ├── user_profile_page.dart   # User profile management
│   ├── day_sessions_page.dart   # Sessions by date
│   └── ml_test_screen.dart      # ML testing screen
├── services/                    # Business logic services
│   ├── sensor_channel.dart      # Platform channel for sensors
│   ├── sensor_data_recorder.dart # CSV recording service
│   ├── workout_service.dart     # Workout mode service
│   └── notification_service.dart # Local notifications
├── widgets/                     # Reusable UI components
│   ├── energy_expenditure_card.dart # EE display card
│   ├── energy_expenditure_chart.dart # EE chart widget
│   ├── feedback_bottom_drawer.dart   # Survey feedback UI
│   ├── login_tf.dart            # Login text field
│   ├── name_tf.dart             # Name text field
│   ├── signup_tf.dart           # Signup text field
│   └── network_error_widget.dart # Network error display
├── providers/                   # State providers
│   └── user_profile_provider.dart # User profile state
├── db/                          # Database utilities
│   └── lambda-->index.mjs       # (Legacy/symlink)
└── main_util_webservice/        # Python ML utilities (legacy)
    ├── main.py
    ├── utils.py
    └── *.pkl                    # ML model files
```

## Core Components

### 1. Authentication (`auth/`)

#### `auth_service.dart`

**Purpose**: Handles all authentication operations using AWS Cognito via Amplify.

**Key Methods**:

- `signIn(String email, String password)`: Authenticate user
- `signUp(...)`: Register new user
- `signOut()`: Log out current user
- `verifyEmail(String email, String code)`: Verify email with code
- `getCurrentUserEmail()`: Get authenticated user's email
- `isSignedIn()`: Check authentication status

**Error Handling**: Converts Amplify exceptions to user-friendly error messages.

#### `auth_wrapper.dart`

**Purpose**: Wrapper widget that checks authentication state and routes to login or home screen.

**Behavior**:

- Shows loading spinner while checking auth state
- Redirects to `LoginPage` if not authenticated
- Redirects to `SensorScreen` (home page) if authenticated

#### `amplify_config.dart`

**Purpose**: Generates AWS Amplify configuration JSON from environment variables.

**Configuration**:

- Uses `.env` file for sensitive data
- Requires: `AWS_COGNITO_POOL_ID`, `AWS_COGNITO_CLIENT_ID`, `AWS_COGNITO_REGION`

#### `login_page.dart` / `signup_page.dart` / `verification_page.dart`

**Purpose**: UI screens for authentication flow.

**Features**:

- Form validation
- Error message display
- Navigation between auth screens
- Integration with `AuthService`

### 2. Configuration (`config/`)

#### `api_config.dart`

**Purpose**: Centralized API endpoint configuration.

**Endpoints**:

- **User Profile**: `getUserProfile`, `manageUserProfile`
- **Sensor Data**: `saveRawSensorData`, `processEnergyExpenditure`
- **Sessions**: `getPastSessionsSummary`, `getSessionDetails`, `getPastSessions`
- **Surveys**: `saveSurveyResponse`, `checkSurveyResponses`, `getSurveyResponse`
- **Aggregated**: `getAllSessionSummaries`

**Configuration**: Uses `.env` file for base URLs.

### 3. Data Models (`models/`)

#### `session.dart`

**Purpose**: Data structures for session and energy expenditure data.

**Classes**:

- **`Session`**: Complete session data with results

  - `sessionId`: Unique session identifier
  - `timestamp`: Session start time
  - `results`: List of `SessionResult` objects
  - `basalMetabolicRate`: BMR value
  - `measurementCount`: Number of measurements

- **`SessionResult`**: Individual energy expenditure measurement

  - `timestamp`: Measurement time
  - `energyExpenditure`: EE value in Watts
  - `windowIndex`: Processing window index
  - `gaitCycleIndex`: Gait cycle index

- **`SessionSummary`**: Summary of session for list views
  - `sessionId`, `timestamp`, `measurementCount`
  - `hasSurveyResponse`: Whether survey was completed

**Usage**: JSON serialization/deserialization for API communication.

#### `user_profile.dart`

**Purpose**: User demographic and physical data model.

**Fields**:

- `userEmail`: User identifier
- `weight`: Weight in kg
- `height`: Height in cm
- `age`: Age in years
- `gender`: Gender (String)
- `lastUpdated`: Last update timestamp

**Usage**: Used for energy expenditure calculations and profile management.

### 4. Pages (`pages/`)

#### `home_page.dart` (Main Screen)

**Purpose**: Primary screen for recording sensor data and viewing real-time results.

**Key Features**:

- **Recording Controls**: Start/stop recording buttons
- **Sensor Data Collection**: Records accelerometer and gyroscope data
- **Real-time Display**: Shows current energy expenditure
- **Session Management**: Tracks active sessions, uploads data
- **Processing Status**: Shows upload and processing progress
- **Notifications**: Sends local notifications when processing completes

**State Management**:

- Manages active recording sessions
- Tracks upload progress
- Handles network errors gracefully
- Stores session status locally

**Data Flow**:

1. User starts recording → Sensors start → Data buffered
2. User stops recording → CSV saved → Data uploaded in batches
3. Upload complete → Processing triggered → Results polled
4. Results received → Displayed in UI → Notification sent

#### `past_sessions_page.dart`

**Purpose**: Displays historical sessions in a calendar view.

**Features**:

- **Calendar Interface**: Scrollable calendar showing dates with sessions
- **Session Cards**: List of sessions per day
- **Navigation**: Tap to view session details
- **Survey Indicators**: Visual indicators for sessions missing surveys
- **Caching**: Uses Hive for offline caching

**Data Loading**:

- Fetches session summaries from API
- Caches locally using Hive
- Groups sessions by date

#### `session_details_page.dart`

**Purpose**: Detailed view of a single session.

**Features**:

- **Energy Expenditure Chart**: Visual graph of EE over time
- **Statistics**: Total energy, average, min/max values
- **Session Info**: Timestamp, duration, measurement count
- **Survey Integration**: Link to survey if not completed

#### `user_profile_page.dart`

**Purpose**: User profile management screen.

**Features**:

- **Profile Form**: Input fields for weight, height, age, gender
- **Save/Cancel**: Update or discard changes
- **Validation**: Form validation before submission
- **State Management**: Uses `UserProfileProvider`

#### `day_sessions_page.dart`

**Purpose**: Shows all sessions for a specific date.

**Features**:

- Filtered session list by date
- Session cards with basic info
- Navigation to session details

#### `ml_test_screen.dart`

**Purpose**: Testing screen for ML model functionality (development).

### 5. Services (`services/`)

#### `sensor_data_recorder.dart`

**Purpose**: Records sensor data to CSV files.

**Features**:

- **File Management**: Creates CSV files per session
- **Data Buffering**: Buffers sensor readings before writing
- **CSV Format**: Standard format with headers
- **Platform Detection**: Records iOS/Android platform info
- **L2 Norm Calculation**: Calculates gyroscope L2 norm

**CSV Format**:

```
Timestamp,Accelerometer_X,Accelerometer_Y,Accelerometer_Z,Gyroscope_X,Gyroscope_Y,Gyroscope_Z,L2_Norm,Platform
```

**Key Methods**:

- `startRecording()`: Initialize file and start recording
- `stopRecording()`: Flush buffer and close file
- `bufferData(...)`: Add sensor reading to buffer
- `saveBufferedData()`: Write buffered data to file
- `getCurrentSessionFilePath()`: Get file path for current session

**Usage**: Instantiated per session with unique `sessionId`.

#### `sensor_channel.dart`

**Purpose**: Platform channel interface for native sensor access.

**Features**:

- **Cross-Platform**: Works on iOS and Android
- **Method Channels**: Communicates with native code
- **Sensor Access**: Accelerometer and gyroscope data
- **Session Management**: Sets active session state (Android)

**Key Methods**:

- `startSensors(String sessionId)`: Start sensor collection
- `stopSensors()`: Stop sensor collection
- `getAccelerometerData()`: Get current accelerometer values
- `getGyroscopeData()`: Get current gyroscope values

**Platform Differences**:

- **Android**: Returns combined 6-element array (3 accel + 3 gyro)
- **iOS**: Separate calls for accelerometer and gyroscope

#### `workout_service.dart`

**Purpose**: Manages workout mode on iOS (prevents screen lock during recording).

**Features**:

- **iOS Only**: Uses method channel to native iOS code
- **Workout Mode**: Keeps device active during recording
- **Auto Start/Stop**: Integrated with recording lifecycle

**Methods**:

- `startWorkoutMode()`: Enable workout mode
- `stopWorkoutMode()`: Disable workout mode

#### `notification_service.dart`

**Purpose**: Local notifications for session completion/failures.

**Features**:

- **Cross-Platform**: Works on iOS and Android
- **Permission Handling**: Requests notification permissions
- **Notification Types**: Success and error notifications
- **Tap Handling**: Handles notification taps

**Methods**:

- `initialize()`: Initialize notification service
- `requestPermissions()`: Request platform permissions
- `showSessionCompleteNotification(...)`: Show success notification
- `showSessionErrorNotification(...)`: Show error notification

### 6. Widgets (`widgets/`)

#### `energy_expenditure_card.dart`

**Purpose**: Displays individual energy expenditure measurement.

**Features**:

- **Visual Design**: Card with icon and formatted text
- **State Indicators**: Different styling for gait cycles vs resting
- **Timestamp Display**: Formatted date and time
- **Value Formatting**: Energy expenditure in Watts

#### `energy_expenditure_chart.dart`

**Purpose**: Line chart widget for energy expenditure over time.

**Features**:

- Uses `fl_chart` package
- Interactive chart with time axis
- Multiple data series support
- Customizable styling

#### `feedback_bottom_drawer.dart`

**Purpose**: Bottom sheet drawer for survey/feedback collection.

**Features**:

- **Slide-up Interface**: Bottom sheet UI pattern
- **Survey Questions**: Multiple question types
- **Submission**: Posts survey responses to API
- **Validation**: Form validation before submission

#### `login_tf.dart` / `signup_tf.dart` / `name_tf.dart`

**Purpose**: Custom text field widgets for authentication forms.

**Features**:

- **Custom Styling**: Consistent design across forms
- **Error Handling**: Error state display
- **Validation**: Input validation
- **Platform Optimized**: iOS and Android compatible

#### `network_error_widget.dart`

**Purpose**: Displays network error messages.

**Features**:

- **User-Friendly**: Clear error messages
- **Retry Functionality**: Retry button for failed operations
- **Offline Detection**: Detects network connectivity issues

### 7. Providers (`providers/`)

#### `user_profile_provider.dart`

**Purpose**: State management for user profile data.

**Features**:

- **ChangeNotifier**: Notifies listeners of state changes
- **Loading States**: Tracks loading, error, and success states
- **Network Error Handling**: Distinguishes network vs other errors
- **API Integration**: Fetches and updates profile via API

**Key Methods**:

- `fetchUserProfile()`: Load user profile from API
- `updateProfile(UserProfile)`: Update profile via API

**State Properties**:

- `userProfile`: Current profile data (nullable)
- `isLoading`: Loading state flag
- `errorMessage`: Error message if any
- `isNetworkError`: Network-specific error flag
- `hasProfile`: Whether profile exists

### 8. Main Entry Point (`main.dart`)

**Purpose**: Application initialization and setup.

**Initialization Steps**:

1. **Load Environment Variables**: Loads `.env` file
2. **Lock Orientation**: Portrait mode only
3. **Initialize Hive**: Local storage for caching
4. **Initialize Notifications**: Notification service setup
5. **Configure Amplify**: AWS Cognito authentication setup
6. **Setup Providers**: State management providers
7. **Run App**: Launch Material app with `AuthWrapper`

**Key Dependencies**:

- `flutter_dotenv`: Environment variable management
- `hive_flutter`: Local storage
- `amplify_flutter`: AWS Amplify integration
- `provider`: State management

## Data Flow

### Recording and Processing Flow

```
1. User Starts Recording
   ↓
2. SensorChannel.startSensors(sessionId)
   ↓
3. Native sensors start collecting data
   ↓
4. Periodic data collection (timer-based)
   ↓
5. SensorDataRecorder.bufferData(...)
   ↓
6. Data buffered in memory
   ↓
7. User Stops Recording
   ↓
8. SensorDataRecorder.stopRecording()
   ↓
9. CSV file saved to device
   ↓
10. Upload to API (batched for large files)
    ↓
11. API Gateway → Lambda → DynamoDB
    ↓
12. Trigger Processing (Fargate service)
    ↓
13. Poll for Results
    ↓
14. Display Results in UI
    ↓
15. Send Notification (if enabled)
```

### Authentication Flow

```
1. User Opens App
   ↓
2. AuthWrapper checks auth state
   ↓
3. If not signed in → LoginPage
   ↓
4. User enters credentials
   ↓
5. AuthService.signIn(...)
   ↓
6. AWS Cognito authentication
   ↓
7. Success → HomePage
   ↓
8. Failure → Error message
```

### Profile Management Flow

```
1. User navigates to Profile Page
   ↓
2. UserProfileProvider.fetchUserProfile()
   ↓
3. API call to get-user-profile endpoint
   ↓
4. Profile loaded or null returned
   ↓
5. User edits profile
   ↓
6. UserProfileProvider.updateProfile(...)
   ↓
7. API call to manage-user-profile endpoint
   ↓
8. Profile updated in DynamoDB
   ↓
9. UI updated via Provider notification
```

## Configuration

### Environment Variables (`.env` file)

Create a `.env` file in the project root with:

```env
# AWS Cognito Configuration
AWS_COGNITO_POOL_ID=us-east-1_xxxxxxxxx
AWS_COGNITO_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxx
AWS_COGNITO_REGION=us-east-1

# API Gateway Base URL
API_GATEWAY_BASE_URL=https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/dev

# ECS Fargate Service URL (for energy expenditure processing)
FARGATE_SERVICE_URL=http://xxxxxxxxxx.us-east-1.elb.amazonaws.com
```

**Getting Values**:

- Cognito IDs: AWS Console → Cognito → User Pools → Your Pool
- API Gateway URL: From Terraform output (`terraform output api_endpoint`)
- Fargate URL: From Terraform output (`terraform output energy_expenditure_service_url`)

### App Configuration

**Orientation**: Locked to portrait mode (configured in `main.dart`)

**Hive Boxes**:

- `session_summaries`: Cached session data
- `user_preferences`: User preferences (if used)

**Notification Channels** (Android):

- `session_complete`: Session processing complete notifications
- `session_error`: Session processing error notifications

## Key Features

### 1. Sensor Data Recording

- Real-time accelerometer and gyroscope data collection
- CSV file storage on device
- Buffered writes for performance
- Platform-specific handling (iOS/Android)

### 2. Energy Expenditure Calculation

- Uploads sensor data to AWS
- Triggers ML model processing
- Polls for results
- Displays results in real-time

### 3. Session Management

- Unique session IDs per recording
- Session status tracking
- Upload progress monitoring
- Error handling and retry logic

### 4. Offline Support

- Local CSV file storage
- Hive caching for session summaries
- Network error detection
- Retry mechanisms

### 5. User Profile

- Demographic data collection
- Required for energy expenditure calculations
- Profile management UI
- API integration

### 6. Survey Collection

- Feedback collection after sessions
- Survey response tracking
- Visual indicators for missing surveys

### 7. Notifications

- Local notifications for processing completion
- Error notifications
- Permission handling

## Dependencies

### Core Dependencies

- **`flutter`**: Flutter SDK
- **`provider`**: State management
- **`amplify_flutter`**: AWS Amplify integration
- **`amplify_auth_cognito`**: Cognito authentication
- **`flutter_dotenv`**: Environment variables
- **`http`**: HTTP requests
- **`sensors_plus`**: Sensor data access
- **`csv`**: CSV file handling
- **`path_provider`**: File system paths
- **`hive` / `hive_flutter`**: Local storage
- **`fl_chart`**: Charting library
- **`intl`**: Internationalization/date formatting
- **`flutter_local_notifications`**: Local notifications
- **`permission_handler`**: Permission management

### Platform-Specific

**iOS**:

- Native sensor access via platform channels
- Workout mode support
- Notification permissions

**Android**:

- Native sensor access via platform channels
- Foreground service for sensor recording
- Background upload capability

## Usage Guide

### Setting Up the Project

1. **Install Flutter**: Ensure Flutter SDK is installed

   ```bash
   flutter --version
   ```

2. **Install Dependencies**:

   ```bash
   flutter pub get
   ```

3. **Configure Environment**:

   - Create `.env` file in project root
   - Add required environment variables (see Configuration section)

4. **Configure Native Code**:

   - **iOS**: Configure platform channels in `ios/Runner/AppDelegate.swift`
   - **Android**: Configure platform channels in `android/app/src/main/kotlin/...`

5. **Run the App**:
   ```bash
   flutter run
   ```

### Using the App

1. **First Launch**:

   - App checks authentication state
   - If not signed in, shows login screen
   - User can sign up or sign in

2. **Sign Up Flow**:

   - Enter email, password, first name, last name
   - Submit signup form
   - Receive verification code via email
   - Enter code on verification screen
   - Automatically signed in after verification

3. **Recording a Session**:

   - Tap "Start Recording" button
   - Sensors start collecting data
   - Recording indicator shows active state
   - Tap "Stop Recording" when done
   - Data is saved and uploaded automatically

4. **Viewing Results**:

   - After processing completes, results appear on home screen
   - Tap "View Past Sessions" to see history
   - Tap a session to view details
   - Charts and statistics displayed

5. **Managing Profile**:
   - Navigate to profile page
   - Enter or update demographic data
   - Save changes
   - Profile is required for accurate calculations

### Development Workflow

1. **Making Changes**:

   - Edit Dart files in `lib/`
   - Hot reload for UI changes: Press `r` in terminal
   - Hot restart for logic changes: Press `R` in terminal

2. **Testing**:

   - Run unit tests: `flutter test`
   - Test on physical device for sensor access
   - Test on emulator for UI testing

3. **Building**:
   - **Android**: `flutter build apk` or `flutter build appbundle`
   - **iOS**: `flutter build ios`

## Troubleshooting

### Common Issues

1. **Sensors Not Working**

   - **Issue**: No data collected
   - **Solution**:
     - Check native platform channel configuration
     - Verify permissions are granted
     - Test on physical device (emulators may not support sensors)

2. **Authentication Errors**

   - **Issue**: Login fails or verification fails
   - **Solution**:
     - Verify `.env` file has correct Cognito credentials
     - Check AWS Cognito user pool is configured correctly
     - Ensure SES is in production mode (not sandbox)

3. **Network Errors**

   - **Issue**: API calls fail
   - **Solution**:
     - Verify API Gateway URL in `.env`
     - Check internet connectivity
     - Verify AWS resources are deployed (run `terraform output`)

4. **Upload Failures**

   - **Issue**: Data doesn't upload
   - **Solution**:
     - Check network connection
     - Verify API endpoint is correct
     - Check Lambda function logs in AWS CloudWatch
     - Large files may need batch upload (already implemented)

5. **Processing Not Completing**

   - **Issue**: Session stuck in "processing" state
   - **Solution**:
     - Check ECS service logs in CloudWatch
     - Verify SQS queue is processing messages
     - Check DynamoDB for processing status updates

6. **Notifications Not Showing**

   - **Issue**: No notifications appear
   - **Solution**:
     - Check notification permissions are granted
     - Verify platform-specific notification setup
     - Check notification service initialization

7. **Build Errors**
   - **Issue**: App won't build
   - **Solution**:
     - Run `flutter clean`
     - Run `flutter pub get`
     - Check for dependency conflicts
     - Verify all native dependencies are properly configured

### Debugging Tips

1. **Enable Debug Logging**:

   - Check console output for detailed logs
   - All services include print statements for debugging

2. **Check AWS Resources**:

   - Verify Terraform deployment is successful
   - Check CloudWatch logs for Lambda/ECS errors
   - Verify DynamoDB tables exist and have data

3. **Network Debugging**:

   - Use network inspection tools
   - Check API Gateway logs
   - Verify request/response formats

4. **State Debugging**:
   - Use Provider's `debugPrint` to track state changes
   - Check Hive boxes for cached data
   - Verify state updates are triggering UI rebuilds

## Additional Notes

### Platform Channels

The app uses platform channels for native functionality:

- **Sensor Access**: Native code for accelerometer/gyroscope
- **Workout Mode**: iOS-specific workout session management
- **File System**: Native file path handling

See native code in:

- **iOS**: `ios/Runner/AppDelegate.swift` and related files
- **Android**: `android/app/src/main/kotlin/...`

### Security Considerations

- **Environment Variables**: Never commit `.env` file to version control
- **API Keys**: Store sensitive data in environment variables
- **Authentication**: All API calls should include authentication tokens (if implemented)
- **Data Privacy**: Sensor data is user-specific and stored securely in DynamoDB

### Performance Optimization

- **Data Buffering**: Sensor data is buffered before writing to reduce I/O
- **Batch Uploads**: Large files are uploaded in batches
- **Caching**: Session summaries are cached locally using Hive
- **Lazy Loading**: Data is loaded on-demand, not all at once

### Future Enhancements

Potential improvements:

- Background processing for uploads
- Offline mode with sync when online
- Real-time energy expenditure display
- Advanced charting and analytics
- Export functionality for data
- Multi-user support (if needed)

---

**Last Updated**: See git history for latest changes.

**Questions or Issues?**: Check the troubleshooting section or review the code comments for detailed explanations.
