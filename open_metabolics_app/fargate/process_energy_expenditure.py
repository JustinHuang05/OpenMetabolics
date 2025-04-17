import os
import json
import boto3
from datetime import datetime, timedelta
from typing import List, Dict, Any
from flask import Flask, request, jsonify
import numpy as np
import pandas as pd
import pickle
from scipy import signal
from scipy.linalg import norm
import utils

app = Flask(__name__)

# Initialize DynamoDB client
dynamodb = boto3.client('dynamodb')

# Load subject information from CSV
subj_csv = pd.read_csv('./subject_info.csv')
target_subj = 'S1'
subj_info = {
    'code': subj_csv.loc[subj_csv['subject'] == target_subj, 'subject'].values[0],
    'weight': subj_csv.loc[subj_csv['subject'] == target_subj, 'weight'].values[0],
    'height': subj_csv.loc[subj_csv['subject'] == target_subj, 'height'].values[0],
    'gender': subj_csv.loc[subj_csv['subject'] == target_subj, 'gender'].values[0],
    'age': subj_csv.loc[subj_csv['subject'] == target_subj, 'age'].values[0]
}

# Compute basal metabolic rate
stand_aug_fact = 1.41  # Standing augmentation factor
height = subj_info['height']
weight = subj_info['weight']
age = subj_info['age']
gender = subj_info['gender']
cur_basal = utils.basalEst(height, weight, age, gender, stand_aug_fact, kcalPerDay2Watt=0.048426)

# Load models
data_driven_model = pickle.load(open('./data_driven_ee_model.pkl', 'rb'))
pocket_motion_correction_model = pickle.load(open('./pocket_motion_correction_model.pkl', 'rb'))

# Constants for signal processing
sampling_freq = 50  # Sampling frequency in Hz
cutoff_freq = 6  # Crossover frequency for low-pass filter in Hz
filt_order = 4  # Filter order
sliding_win = 200  # Window size for sliding window in samples (4 seconds at 50Hz)
gyro_norm_thres = 0.5  # Threshold for gyro norm in rad/s

# Define low-pass filter parameters
b, a = signal.butter(filt_order, cutoff_freq, btype='low', fs=sampling_freq)

def calculate_energy_expenditure(gyro_data: List[Dict[str, float]], acc_data: List[Dict[str, float]], window_time: List[float]) -> List[float]:
    """
    Calculate energy expenditure from gyroscope and accelerometer data using the full pipeline.
    """
    # Convert input data to numpy arrays
    gyro_array = np.array([[d['x'], d['y'], d['z']] for d in gyro_data])
    acc_array = np.array([[d['x'], d['y'], d['z']] for d in acc_data])
    time_array = np.array(window_time)

    # Calculate L2 norm of gyro data
    l2_norm_gyro = np.linalg.norm(gyro_array)

    if l2_norm_gyro > gyro_norm_thres:
        # Apply low-pass filter
        gyro_filtered = signal.filtfilt(b, a, gyro_array, axis=0)
        acc_filtered = signal.filtfilt(b, a, acc_array, axis=0)

        # Orientation alignment with superior-inferior axis
        opt_rotm_z_pocket, theta_z = utils.get_rotate_z(acc_filtered)
        gyro_rot_zx = np.matmul(gyro_filtered, opt_rotm_z_pocket)

        # Find principal axis
        prin_idx = utils.find_prin_axis(gyro_rot_zx)
        prin_gyro = gyro_rot_zx[:, prin_idx]
        
        if np.abs(np.max(prin_gyro)) < np.abs(np.min(prin_gyro)):
            prin_gyro = -prin_gyro

        # Detect peaks
        gait_peaks = utils.peak_detect(prin_gyro)
        
        if len(gait_peaks) > 1:
            # Segment gait data
            gait_data = utils.segment_data(gait_peaks, gyro_rot_zx, sliding_win)
            if len(gait_data) < 1:
                return [cur_basal]

            # Orientation alignment with mediolateral axis
            avg_gait_data = np.mean(gait_data, axis=0)
            opt_rotm_y, theta_y = utils.get_rotate_y(avg_gait_data, prin_idx)
            opt_rotm = np.matmul(opt_rotm_z_pocket, opt_rotm_y)
            gyro_cal = np.matmul(gyro_filtered, opt_rotm)

            # Adjust rotation if necessary
            pos_idx = gyro_cal[:, -1] > 0
            neg_idx = gyro_cal[:, -1] < 0
            gyro_z_norm_pos = norm(gyro_cal[pos_idx, -1], ord=2)
            gyro_z_norm_neg = norm(gyro_cal[neg_idx, -1], ord=2)
            
            if gyro_z_norm_pos <= gyro_z_norm_neg:
                opt_rotm = np.matmul(opt_rotm, utils.rotm_y(np.pi))
                gyro_cal = np.matmul(gyro_filtered, opt_rotm)

            # Final gait segmentation and EE estimation
            gait_peaks = utils.peak_detect(gyro_cal[:, -1])
            ee_time, ee_est = utils.estimateMetabolics(
                model=data_driven_model,
                time=time_array,
                gait_data=gyro_cal,
                peak_index=gait_peaks,
                weight=weight,
                height=height,
                stride_detect_window=sliding_win,
                correction_model=pocket_motion_correction_model
            )
            return ee_est
        else:
            return [cur_basal]
    else:
        return [cur_basal]

def process_window(window: List[Dict[str, Any]], window_index: int, session_id: str, user_email: str) -> List[Dict[str, Any]]:
    """
    Process a window of sensor data and calculate energy expenditure values.
    """
    # Extract gyroscope and accelerometer data
    gyro_data = [{
        'x': float(item['Gyroscope_X']['N']),
        'y': float(item['Gyroscope_Y']['N']),
        'z': float(item['Gyroscope_Z']['N'])
    } for item in window]

    acc_data = [{
        'x': float(item['Accelerometer_X']['N']),
        'y': float(item['Accelerometer_Y']['N']),
        'z': float(item['Accelerometer_Z']['N'])
    } for item in window]

    # Extract timestamps and convert to seconds since epoch
    window_time = [
        datetime.fromisoformat(item['Timestamp']['S'].replace('Z', '+00:00')).timestamp()
        for item in window
    ]

    print(f"\nProcessing window {window_index + 1}:")
    print(f"Window size: {len(window)}")
    print(f"Window start time: {window[0]['Timestamp']['S']}")
    print(f"Window end time: {window[-1]['Timestamp']['S']}")

    # Calculate energy expenditure for this window
    ee_values = calculate_energy_expenditure(gyro_data, acc_data, window_time)
    # Convert numpy float32 to regular Python float
    ee_values = [float(value) for value in ee_values]
    print(f"Window {window_index + 1} EE values: {ee_values}")

    results = []
    window_start_time = datetime.fromisoformat(window[0]['Timestamp']['S'].replace('Z', '+00:00'))
    window_end_time = datetime.fromisoformat(window[-1]['Timestamp']['S'].replace('Z', '+00:00'))
    time_per_gait_cycle = (window_end_time - window_start_time).total_seconds() / len(ee_values)

    # Store each result
    for j, ee_value in enumerate(ee_values):
        gait_cycle_timestamp = window_start_time + timedelta(seconds=j * time_per_gait_cycle)
        
        print(f"Window {window_index + 1}, Gait Cycle {j + 1}:")
        print(f"Window start: {window_start_time.isoformat()}")
        print(f"Window end: {window_end_time.isoformat()}")
        print(f"Time per cycle: {time_per_gait_cycle}")
        print(f"Timestamp: {gait_cycle_timestamp.isoformat()}")
        print(f"EE value: {ee_value}")

        # Store result in DynamoDB
        result_item = {
            'TableName': os.environ['RESULTS_TABLE'],
            'Item': {
                'SessionId': {'S': session_id},
                'Timestamp': {'S': gait_cycle_timestamp.isoformat()},
                'UserEmail': {'S': user_email},
                'EnergyExpenditure': {'N': str(ee_value)},
                'WindowIndex': {'N': str(window_index)},
                'GaitCycleIndex': {'N': str(j)}
            }
        }

        dynamodb.put_item(**result_item)
        results.append({
            'timestamp': gait_cycle_timestamp.isoformat(),
            'energyExpenditure': ee_value,
            'windowIndex': window_index,
            'gaitCycleIndex': j
        })

    return results

@app.route('/process', methods=['POST'])
def process_energy_expenditure():
    try:
        data = request.get_json()
        print("Received request:", data)

        if not data or not data.get('session_id') or not data.get('user_email'):
            return jsonify({
                'error': 'Missing required fields (session_id or user_email)'
            }), 400

        session_id = data['session_id']
        user_email = data['user_email']

        # Initialize variables for pagination
        last_evaluated_key = None
        all_sensor_data = []
        total_processed = 0

        # Query all sensor data for this session with pagination
        while True:
            query_params = {
                'TableName': os.environ['RAW_SENSOR_TABLE'],
                'KeyConditionExpression': 'SessionId = :sessionId',
                'ExpressionAttributeValues': {
                    ':sessionId': {'S': session_id}
                },
                'Limit': 1000,  # Maximum items per query
                'ScanIndexForward': True  # Sort by timestamp in ascending order
            }
            
            if last_evaluated_key:
                query_params['ExclusiveStartKey'] = last_evaluated_key

            print(f"Querying data with last_evaluated_key: {json.dumps(last_evaluated_key)}")
            query_result = dynamodb.query(**query_params)
            
            if query_result.get('Items'):
                all_sensor_data.extend(query_result['Items'])
                total_processed += len(query_result['Items'])
                print(f"Processed {total_processed} items so far")

            last_evaluated_key = query_result.get('LastEvaluatedKey')
            if not last_evaluated_key:
                break

        if not all_sensor_data:
            return jsonify({
                'error': 'No sensor data found for this session'
            }), 404

        # Sort the data by timestamp to ensure chronological order
        all_sensor_data.sort(key=lambda x: x['Timestamp']['S'])

        print(f"Total items to process: {len(all_sensor_data)}")

        # Process the data in windows (4 seconds at 50Hz = 200 samples)
        window_size = 200
        all_results = []

        # Process each window
        for i in range(0, len(all_sensor_data), window_size):
            window = all_sensor_data[i:i + window_size]
            window_results = process_window(window, i // window_size, session_id, user_email)
            all_results.extend(window_results)

        print('\nFinal Results Summary:')
        print(f"Total windows processed: {len(all_sensor_data) / window_size}")
        print(f"Total results: {len(all_results)}")
        print('Results:', json.dumps(all_results, indent=2))

        return jsonify({
            'message': 'Energy expenditure calculation completed',
            'session_id': session_id,
            'total_windows_processed': len(all_sensor_data) / window_size,
            'results': all_results
        })

    except Exception as error:
        print("Error processing energy expenditure:", error)
        return jsonify({
            'error': str(error)
        }), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy'}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80) 