# OpenMetabolics Energy Expenditure Processing Service

This directory contains the Python-based energy expenditure processing service that runs on AWS ECS Fargate. The service processes accelerometer and gyroscope sensor data from mobile devices to estimate energy expenditure using machine learning models.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Service Components](#service-components)
- [Machine Learning Models](#machine-learning-models)
- [Processing Pipeline](#processing-pipeline)
- [Algorithm Details](#algorithm-details)
- [File Structure](#file-structure)
- [Dependencies](#dependencies)
- [Building and Deployment](#building-and-deployment)
- [Configuration](#configuration)
- [API Endpoints](#api-endpoints)
- [Worker Service](#worker-service)
- [Troubleshooting](#troubleshooting)
- [Performance Considerations](#performance-considerations)

## Overview

The energy expenditure processing service is a containerized Python application that:

- **Receives Processing Requests**: API endpoint accepts session IDs for processing
- **Queues Jobs**: Places processing jobs in SQS for asynchronous execution
- **Processes Sensor Data**: Worker service processes accelerometer/gyroscope data
- **Calculates Energy Expenditure**: Uses ML models to estimate energy expenditure in Watts
- **Stores Results**: Saves processed results to DynamoDB

The service runs on AWS ECS Fargate and operates in two modes:

1. **API Service**: Flask API that accepts requests and queues processing jobs
2. **Worker Service**: Processes jobs from SQS queue and calculates energy expenditure

## Architecture

### Service Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter App                           │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│         Application Load Balancer (ALB)                 │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│              ECS Fargate (API Service)                   │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Flask API (process_energy_expenditure.py)      │   │
│  │  - /process (POST)                               │   │
│  │  - /status/<session_id> (GET)                   │   │
│  │  - /results/<session_id> (GET)                  │   │
│  │  - /health (GET)                                 │   │
│  └─────────────────────────────────────────────────┘   │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│              SQS Processing Queue                        │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│           ECS Fargate (Worker Service)                   │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Worker (process_energy_expenditure_worker.py)  │   │
│  │  - Polls SQS queue                              │   │
│  │  - Fetches sensor data from DynamoDB          │   │
│  │  - Processes in windows                         │   │
│  │  - Calculates energy expenditure                 │   │
│  │  - Stores results in DynamoDB                   │   │
│  └─────────────────────────────────────────────────┘   │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│              DynamoDB Tables                              │
│  - RawSensorDataTable (input)                           │
│  - EnergyResultsTable (output)                           │
│  - UserProfilesTable (user data)                        │
│  - ProcessingStatusTable (status tracking)              │
└─────────────────────────────────────────────────────────┘
```

### Processing Flow

```
1. Flutter App → POST /process (session_id, user_email)
   ↓
2. API Service validates session exists in DynamoDB
   ↓
3. API Service initializes processing status (queued)
   ↓
4. API Service sends message to SQS queue
   ↓
5. Worker Service receives message from queue
   ↓
6. Worker Service updates status (processing)
   ↓
7. Worker Service queries DynamoDB for sensor data
   ↓
8. Worker Service processes data in sliding windows
   ↓
9. For each window:
   - Apply signal processing (filtering, orientation alignment)
   - Detect gait cycles
   - Calculate energy expenditure using ML models
   - Store results in DynamoDB
   ↓
10. Worker Service updates status (completed)
    ↓
11. Flutter App polls /status endpoint until complete
    ↓
12. Flutter App fetches results from /results endpoint
```

## Service Components

### 1. API Service (`process_energy_expenditure.py`)

**Purpose**: Flask REST API that handles processing requests and status queries.

**Key Features**:

- Validates session existence before queueing
- Initializes processing status in DynamoDB
- Queues jobs to SQS for asynchronous processing
- Provides status and results endpoints
- Health check endpoint for load balancer

**Endpoints**:

- `POST /process`: Queue a processing job
- `GET /status/<session_id>`: Get processing status
- `GET /results/<session_id>`: Get processing results
- `GET /health`: Health check (returns 200 OK)

### 2. Worker Service (`process_energy_expenditure_worker.py`)

**Purpose**: Long-running process that consumes messages from SQS and processes sensor data.

**Key Features**:

- Polls SQS queue for processing jobs (long polling)
- Fetches sensor data from DynamoDB in chunks
- Processes data in sliding windows (200 samples = 4 seconds at 50Hz)
- Calculates energy expenditure using ML models
- Stores results back to DynamoDB
- Updates processing status throughout workflow
- Handles errors gracefully with status updates

**Processing Strategy**:

- **Chunked Processing**: Fetches data in chunks to avoid memory issues
- **Window-based**: Processes data in 200-sample windows (4 seconds)
- **Overlap Buffer**: Maintains overlap between chunks for continuous processing
- **Progress Tracking**: Updates progress percentage in DynamoDB

### 3. Utility Functions (`utils.py`)

**Purpose**: Core algorithms and helper functions for energy expenditure calculation.

**Key Functions**:

- `basalEst()`: Calculate basal metabolic rate
- `get_rotate_z()` / `get_rotate_y()`: Orientation alignment
- `find_prin_axis()`: Find principal axis of rotation
- `peak_detect()`: Detect gait cycle peaks
- `segment_data()`: Segment data into gait cycles
- `estimateMetabolics()`: Estimate energy expenditure using ML models
- `processRawGait_model()`: Prepare data for ML model input

## Machine Learning Models

### 1. Data-Driven Energy Expenditure Model (`data_driven_ee_model.pkl`)

**Purpose**: Primary model for estimating energy expenditure from processed gait data.

**Input Features**:

- Processed gyroscope data (90 features: 30 bins × 3 axes)
- Statistical features (mean, std, median, skew, L2 norm) for each axis
- User physical characteristics (weight, height)
- Stride duration
- **Total**: ~105 features

**Output**: Energy expenditure in Watts

**Model Type**: XGBoost regressor (from scikit-learn)

**Training**: Trained on laboratory data with ground truth energy expenditure measurements

### 2. Pocket Motion Correction Model (`pocket_motion_correction_model.pkl`)

**Purpose**: Corrects for motion artifacts when phone is in pocket (not fixed to body).

**Input**:

- Processed gyroscope data (90 features)
- Stride duration

**Output**: Estimated motion artifact (subtracted from raw data)

**Model Type**: Regression model (likely XGBoost or similar)

**Usage**: Applied before feeding data to main energy expenditure model

### Model Files

- **`data_driven_ee_model.pkl`**: ~450KB, XGBoost model
- **`pocket_motion_correction_model.pkl`**: ~66KB, motion correction model
- **`daily_sp_pocket_data.csv`**: Sample data file (for testing)
- **`subject_info.csv`**: Sample subject information

**Note**: These models are trained on research data and should not be modified without retraining.

## Processing Pipeline

### Step-by-Step Processing

#### 1. Data Retrieval

```python
# Query DynamoDB for sensor data
query_params = {
    'TableName': 'RawSensorDataTable',
    'KeyConditionExpression': 'SessionId = :sessionId',
    'Limit': 1000  # Process in chunks
}
```

#### 2. Window-Based Processing

- **Window Size**: 200 samples (4 seconds at 50Hz sampling rate)
- **Sliding**: Process each window sequentially
- **Overlap**: Maintained between chunks for continuity

#### 3. Signal Processing (per window)

**a. Low-Pass Filtering**:

```python
# Butterworth filter, 4th order, 6Hz cutoff
b, a = signal.butter(4, 6, btype='low', fs=50)
gyro_filtered = signal.filtfilt(b, a, gyro_data, axis=0)
acc_filtered = signal.filtfilt(b, a, acc_data, axis=0)
```

**b. Orientation Alignment**:

- **Z-axis rotation**: Align with superior-inferior axis of thigh
- **Y-axis rotation**: Align with mediolateral axis
- Uses accelerometer data to determine optimal rotation

**c. Principal Axis Detection**:

- Find principal axis of angular velocity (X or Z axis)
- Used for gait cycle detection

**d. Gait Cycle Detection**:

- Detect peaks in principal angular velocity
- Minimum peak height: 70 degrees/second
- Minimum distance between peaks: 0.6 seconds (30 samples)

#### 4. Energy Expenditure Calculation

**For each detected gait cycle**:

```python
# Process raw gait data
model_input = processRawGait_model(
    data_array=gait_data,
    weight=user_weight,
    height=user_height,
    correction_model=pocket_motion_correction_model
)

# Estimate energy expenditure
ee_est = data_driven_model.predict(model_input)
```

**For non-gait periods**:

- Assign basal metabolic rate (BMR)

#### 5. Result Storage

Each result stored in DynamoDB with:

- `SessionId`: Session identifier
- `Timestamp`: ISO8601 timestamp
- `EnergyExpenditure`: Value in Watts
- `WindowIndex`: Window number
- `GaitCycleIndex`: Gait cycle number within window
- `BasalMetabolicRate`: BMR used for non-gait periods
- `UserEmail`: User identifier

## Algorithm Details

### Basal Metabolic Rate (BMR) Calculation

**Formula** (Harris-Benedict equation modified):

```python
offset = 5 if gender == 'M' else -161
BMR = (10.0 * weight + 625.0 * height - 5.0 * age + offset)
      * 0.048426  # kcal/day to Watts conversion
      * 1.41      # Standing augmentation factor
```

**Usage**:

- Assigned to windows with no detected movement
- Assigned to windows with insufficient gait cycles
- Used as baseline for energy expenditure

### Orientation Alignment

**Purpose**: Align sensor data with body coordinate system (thigh reference frame).

**Z-axis Rotation**:

- Rotate around Z-axis to align with superior-inferior axis
- Maximizes Y-component of accelerometer data
- Accounts for phone orientation in pocket

**Y-axis Rotation**:

- Rotate around Y-axis to align with mediolateral axis
- Maximizes Z-component of angular velocity during positive peaks
- Accounts for phone rotation around thigh

**Adjustment**:

- If positive peaks are smaller than negative peaks, rotate 180° around Y-axis
- Ensures consistent orientation

### Gait Cycle Detection

**Algorithm**:

1. Find principal axis of angular velocity (X or Z)
2. Detect peaks in principal angular velocity
3. Filter peaks: minimum height 70°/s, minimum distance 0.6s
4. Segment data between consecutive peaks

**Gait Cycle Features**:

- Duration: Typically 1-2 seconds
- Peak-to-peak: Represents one stride
- Segmented into 30 bins for model input

### Energy Expenditure Estimation

**Model Input Preparation**:

1. Segment gait data into cycles
2. Resample each cycle to 30 bins
3. Apply motion correction model
4. Extract statistical features (mean, std, median, skew, L2 norm)
5. Combine with user characteristics (weight, height, stride duration)

**Model Prediction**:

- XGBoost regressor predicts energy expenditure
- Output in Watts
- One prediction per gait cycle

**Output Format**:

- Timestamp: Start time of gait cycle
- Energy Expenditure: Predicted value in Watts
- Window Index: Which window this cycle belongs to
- Gait Cycle Index: Which cycle within the window

## File Structure

```
fargate/
├── Dockerfile                          # Container build definition
├── requirements.txt                    # Python dependencies
├── start.sh                            # Service startup script
├── process_energy_expenditure.py       # Flask API service
├── process_energy_expenditure_worker.py # Worker service
├── utils.py                            # Core algorithms
├── main.py                             # Legacy/test script
├── data_driven_ee_model.pkl           # ML model (450KB)
├── pocket_motion_correction_model.pkl  # Motion correction model (66KB)
├── subject_info.csv                   # Sample subject data
└── daily_sp_pocket_data.csv           # Sample sensor data
```

## Dependencies

### Python Packages

**Core Dependencies** (`requirements.txt`):

- **`boto3`** (1.26.137): AWS SDK for Python
- **`botocore`** (1.29.137): AWS SDK core
- **`flask`** (2.3.3): Web framework for API service
- **`werkzeug`** (2.3.7): WSGI utilities
- **`numpy`** (1.24.3): Numerical computing
- **`scipy`** (1.11.3): Scientific computing (signal processing)
- **`matplotlib`** (3.8.0): Plotting (for debugging/testing)
- **`scikit-learn`** (1.3.2): Machine learning utilities
- **`pandas`** (2.1.3): Data manipulation
- **`xgboost`** (2.0.2): XGBoost model library
- **`gunicorn`** (21.2.0): WSGI HTTP server
- **`python-dateutil`** (2.8.2): Date utilities

### System Requirements

- **Python**: 3.9 (slim base image)
- **Container**: Docker with Linux/AMD64 platform
- **Memory**: 2GB recommended for API service, 512MB for worker
- **CPU**: 1 vCPU recommended for API service, 0.25 vCPU for worker

## Building and Deployment

### Building Docker Image

**Prerequisites**:

- Docker installed
- AWS credentials configured
- ECR repository created (via Terraform)

**Build Command**:

```bash
cd fargate
docker build --platform linux/amd64 -t open-metabolics-energy-expenditure-service .
```

**Tag for ECR**:

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
docker tag open-metabolics-energy-expenditure-service:latest \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/open-metabolics-energy-expenditure-service:latest
```

**Push to ECR**:

```bash
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/open-metabolics-energy-expenditure-service:latest
```

### Automated Build Script

Use the provided build script:

```bash
cd terraform/scripts
./build_and_push.sh
```

This script:

1. Logs into ECR
2. Builds Docker image
3. Tags with multiple tags (latest, api, worker)
4. Pushes to ECR

### Dockerfile Details

**Base Image**: `python:3.9-slim`

**Build Steps**:

1. Copy requirements and install dependencies
2. Install gunicorn (WSGI server)
3. Copy Python source files
4. Copy ML model files (.pkl)
5. Copy startup script
6. Set Python path
7. Make startup script executable
8. Set entrypoint to startup script

**Multi-Service Support**:

- Uses `SERVICE_TYPE` environment variable
- `SERVICE_TYPE=api` → Runs Flask API with Gunicorn
- `SERVICE_TYPE=worker` → Runs worker script

### Deployment via Terraform

The Terraform configuration automatically:

1. Builds and pushes Docker image when files change
2. Creates ECS task definitions for both services
3. Deploys ECS services with appropriate configurations
4. Configures load balancer for API service

**Manual Deployment**:

```bash
cd terraform
terraform apply
```

## Configuration

### Environment Variables

Both services require the following environment variables (set by ECS task definition):

**Required Variables**:

- `SERVICE_TYPE`: `"api"` or `"worker"` (determines which service runs)
- `RAW_SENSOR_TABLE`: DynamoDB table name for raw sensor data
- `RESULTS_TABLE`: DynamoDB table name for energy expenditure results
- `USER_PROFILES_TABLE`: DynamoDB table name for user profiles
- `PROCESSING_STATUS_TABLE`: DynamoDB table name for processing status
- `PROCESSING_QUEUE_URL`: SQS queue URL for processing jobs

**AWS Configuration**:

- Uses IAM task role for AWS credentials (no explicit keys needed)
- Task role must have permissions for:
  - DynamoDB: Query, PutItem, GetItem, UpdateItem
  - SQS: ReceiveMessage, DeleteMessage, SendMessage

### Processing Parameters

**Constants** (defined in worker code):

- `sampling_freq`: 50 Hz (sensor sampling rate)
- `cutoff_freq`: 6 Hz (low-pass filter cutoff)
- `filt_order`: 4 (Butterworth filter order)
- `sliding_win`: 200 samples (4 seconds window)
- `gyro_norm_thres`: 0 rad/s (minimum gyro norm for processing)
- `stand_aug_fact`: 1.41 (standing augmentation factor for BMR)

**Gait Detection Parameters**:

- `peak_height_thresh`: 70°/s (minimum peak height)
- `peak_min_dist`: 0.6 seconds (minimum distance between peaks)
- `num_bins`: 30 (resampling bins per gait cycle)

## API Endpoints

### POST /process

**Purpose**: Queue a processing job for a session.

**Request Body**:

```json
{
  "session_id": "session-123",
  "user_email": "user@example.com"
}
```

**Response** (202 Accepted):

```json
{
  "message": "Processing queued successfully",
  "session_id": "session-123",
  "job_id": "sqs-message-id"
}
```

**Error Responses**:

- `400`: Missing required fields
- `404`: Session not found in DynamoDB
- `500`: Error queueing job

### GET /status/<session_id>

**Purpose**: Get processing status for a session.

**Response** (200 OK):

```json
{
  "session_id": "session-123",
  "status": "processing",
  "progress": 45.5,
  "error": null
}
```

**Status Values**:

- `queued`: Job queued, not yet processing
- `processing`: Currently processing
- `completed`: Processing complete
- `failed`: Processing failed

**Progress**: 0-100 percentage

### GET /results/<session_id>

**Purpose**: Get processing results for a session.

**Response** (200 OK):

```json
{
  "session_id": "session-123",
  "results": [
    {
      "SessionId": {"S": "session-123"},
      "Timestamp": {"S": "2024-01-01T12:00:00Z"},
      "EnergyExpenditure": {"N": "125.5"},
      "WindowIndex": {"N": "0"},
      "GaitCycleIndex": {"N": "0"},
      ...
    }
  ]
}
```

**Note**: Results are in DynamoDB format (attribute maps).

**Error Responses**:

- `404`: No results found

### GET /health

**Purpose**: Health check endpoint for load balancer.

**Response** (200 OK):

```json
{
  "status": "healthy"
}
```

## Worker Service

### Operation Mode

**Long Polling**: Worker uses SQS long polling (20 seconds) to efficiently receive messages.

**Processing Loop**:

```python
while True:
    # Receive message from queue
    response = sqs.receive_message(
        QueueUrl=PROCESSING_QUEUE_URL,
        MaxNumberOfMessages=1,
        WaitTimeSeconds=20  # Long polling
    )

    if 'Messages' in response:
        # Process message
        process_message(message)

        # Delete message after successful processing
        sqs.delete_message(...)
```

### Error Handling

**Message Processing Errors**:

- Exception caught and logged
- Message remains in queue (visibility timeout)
- Message returns to queue after timeout for retry
- Dead letter queue (DLQ) receives messages after 3 failed attempts

**Status Updates**:

- Updates DynamoDB status on errors
- Sets status to `failed` with error message
- Allows Flutter app to detect failures

### Chunked Processing

**Strategy**:

- DynamoDB queries limited to 1000 items
- Process in chunks to avoid memory issues
- Maintain overlap buffer between chunks
- Update progress as chunks complete

**Memory Management**:

- Processes windows sequentially
- Stores results in DynamoDB immediately
- Doesn't keep all data in memory

## Troubleshooting

### Common Issues

1. **Model Files Not Found**

   - **Error**: `FileNotFoundError: data_driven_ee_model.pkl`
   - **Solution**: Ensure model files are copied in Dockerfile
   - **Check**: Verify files exist in container: `docker exec <container> ls -la /app/*.pkl`

2. **DynamoDB Access Denied**

   - **Error**: `AccessDeniedException` or `ResourceNotFoundException`
   - **Solution**:
     - Verify IAM task role has DynamoDB permissions
     - Check table names match environment variables
     - Verify tables exist in AWS Console

3. **SQS Queue Not Receiving Messages**

   - **Error**: Worker not processing messages
   - **Solution**:
     - Check queue URL in environment variables
     - Verify worker service is running (`SERVICE_TYPE=worker`)
     - Check CloudWatch logs for errors

4. **Processing Timeout**

   - **Error**: Messages returning to queue
   - **Solution**:
     - Increase SQS visibility timeout (currently 7 hours 20 minutes)
     - Check for infinite loops or memory issues
     - Monitor CloudWatch logs for processing time

5. **Memory Errors**

   - **Error**: `MemoryError` or container killed
   - **Solution**:
     - Increase ECS task memory allocation
     - Reduce chunk size in worker
     - Check for memory leaks in processing

6. **Invalid Sensor Data**
   - **Error**: `ValueError` or `IndexError` during processing
   - **Solution**:
     - Verify sensor data format in DynamoDB
     - Check for missing timestamps or sensor values
     - Validate data before processing

### Debugging

**View API Service Logs**:

```bash
aws logs tail /ecs/open-metabolics-energy-expenditure --follow
```

**View Worker Service Logs**:

```bash
aws logs tail /ecs/energy-expenditure-worker --follow
```

**Check ECS Service Status**:

```bash
aws ecs describe-services \
  --cluster open-metabolics-cluster \
  --services open-metabolics-energy-expenditure-service
```

**Check SQS Queue**:

```bash
aws sqs get-queue-attributes \
  --queue-url <QUEUE_URL> \
  --attribute-names All
```

**Test API Endpoint**:

```bash
curl -X POST http://<ALB_DNS>/process \
  -H "Content-Type: application/json" \
  -d '{"session_id": "test-session", "user_email": "test@example.com"}'
```

**Test Health Check**:

```bash
curl http://<ALB_DNS>/health
```

### Performance Monitoring

**Key Metrics to Monitor**:

- **Processing Time**: Time from queue to completion
- **Queue Depth**: Number of messages waiting
- **Error Rate**: Failed processing attempts
- **Memory Usage**: Container memory utilization
- **CPU Usage**: Container CPU utilization

**CloudWatch Metrics**:

- ECS service metrics (CPU, memory)
- SQS queue metrics (message count, age)
- DynamoDB metrics (read/write capacity, throttles)

## Performance Considerations

### Optimization Strategies

1. **Parallel Processing**:

   - Multiple worker tasks can process different sessions
   - Scale worker service based on queue depth
   - Current: 1 worker task (can scale horizontally)

2. **Chunked Processing**:

   - Processes large sessions in chunks
   - Avoids memory issues for long recordings
   - Updates progress incrementally

3. **Caching**:

   - ML models loaded once at startup
   - User profiles cached during session processing
   - No need to reload models per request

4. **Database Optimization**:
   - Uses DynamoDB Query (not Scan) for efficient retrieval
   - Processes in chronological order
   - Limits query size to 1000 items

### Scaling Recommendations

**API Service**:

- **Current**: 1 task, 1 vCPU, 2GB memory
- **Scale**: Increase desired count for higher traffic
- **Load Balancer**: Already configured for multiple tasks

**Worker Service**:

- **Current**: 1 task, 0.25 vCPU, 512MB memory
- **Scale**: Increase desired count for parallel processing
- **Consideration**: Each task processes one message at a time

**Cost Optimization**:

- Use Fargate Spot for worker service (cost savings)
- Monitor queue depth to scale appropriately
- Consider reserved capacity for consistent workloads

### Processing Time Estimates

**Typical Processing Times**:

- **Short Session** (5 minutes): ~30-60 seconds
- **Medium Session** (30 minutes): ~2-5 minutes
- **Long Session** (1 hour): ~5-10 minutes

**Factors Affecting Time**:

- Number of gait cycles detected
- Chunk size and overlap
- DynamoDB query/put latency
- Model prediction time

**Note**: Processing time scales roughly linearly with session duration.

---

**Last Updated**: See git history for latest changes.

**Research Credit**: "A smartphone activity monitor that accurately estimates energy expenditure" - Harvard Ability Lab, 2025

**Questions or Issues?**: Check CloudWatch logs or review the troubleshooting section.
