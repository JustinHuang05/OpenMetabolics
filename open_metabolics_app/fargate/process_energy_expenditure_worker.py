import os
import json
import boto3
import time
from datetime import datetime, timedelta
from typing import List, Dict, Any
import numpy as np
import pickle
from scipy import signal
from scipy.linalg import norm
import utils
from botocore.config import Config

# Initialize AWS clients
dynamodb = boto3.client('dynamodb', config=Config(
    retries = dict(
        max_attempts = 3,
        mode = 'adaptive'
    ),
    connect_timeout = 5,
    read_timeout = 30
))
sqs = boto3.client('sqs')

# Load models
try:
    data_driven_model = pickle.load(open('./data_driven_ee_model.pkl', 'rb'))
    with open('./pocket_motion_correction_model.pkl', 'rb') as f_pmcm:
        pocket_motion_correction_model = pickle.load(f_pmcm)
    print("Successfully loaded data_driven_ee_model.pkl and pocket_motion_correction_model.pkl")
except FileNotFoundError as e:
    print(f"ERROR: Model file not found: {e}. Ensure models are present in the Docker image.")
    raise
except Exception as e:
    print(f"ERROR: Could not load models: {e}")
    raise

# Constants for signal processing
sampling_freq = 50  # Sampling frequency in Hz
cutoff_freq = 6  # Crossover frequency for low-pass filter in Hz
filt_order = 4  # Filter order
sliding_win = 200  # Window size for sliding window in samples (4 seconds at 50Hz)
gyro_norm_thres = 0  # Threshold for gyro norm in rad/s

# Define low-pass filter parameters
b, a = signal.butter(filt_order, cutoff_freq, btype='low', fs=sampling_freq)

def update_processing_status(session_id: str, status: str, progress: float = None, error: str = None):
    """Update the processing status in DynamoDB"""
    update_expr = 'SET #status = :status'
    expr_attrs = {
        '#status': 'Status'
    }
    expr_vals = {
        ':status': {'S': status}
    }
    
    if progress is not None:
        update_expr += ', #progress = :progress'
        expr_attrs['#progress'] = 'Progress'
        expr_vals[':progress'] = {'N': str(progress)}
    
    if error is not None:
        update_expr += ', #error = :error'
        expr_attrs['#error'] = 'Error'
        expr_vals[':error'] = {'S': error}
    
    try:
        dynamodb.update_item(
            TableName=os.environ['PROCESSING_STATUS_TABLE'],
            Key={'SessionId': {'S': session_id}},
            UpdateExpression=update_expr,
            ExpressionAttributeNames=expr_attrs,
            ExpressionAttributeValues=expr_vals
        )
    except Exception as e:
        print(f"Error updating processing status: {str(e)}")

def get_user_profile(user_email: str) -> Dict[str, Any]:
    """Fetch user profile from DynamoDB"""
    try:
        response = dynamodb.get_item(
            TableName=os.environ['USER_PROFILES_TABLE'],
            Key={
                'UserEmail': {'S': user_email.lower()}
            }
        )
        
        if 'Item' not in response:
            error_msg = f"User profile not found for email: {user_email}"
            print(f"ERROR: {error_msg}")
            raise Exception(error_msg)
            
        item = response['Item']
        try:
            user_profile_data = {
                'weight': float(item['Weight']['N']),
                'height': float(item['Height']['N']),
                'age': int(item['Age']['N']),
                'gender': item['Gender']['S']
            }
            if not all(k in user_profile_data for k in ['weight', 'height', 'age', 'gender']):
                raise ValueError("One or more profile fields are missing.")
            return user_profile_data
        except KeyError as ke:
            error_msg = f"Missing expected field in user profile for {user_email}: {ke}"
            print(f"ERROR: {error_msg}")
            raise Exception(error_msg)
        except ValueError as ve:
            error_msg = f"Invalid data type in user profile for {user_email}: {ve}"
            print(f"ERROR: {error_msg}")
            raise Exception(error_msg)

    except Exception as e:
        print(f"Error fetching/parsing user profile for {user_email}: {e}")
        raise Exception(f"Could not retrieve or parse user profile for {user_email}.")

def calculate_energy_expenditure(gyro_data: List[Dict[str, float]], acc_data: List[Dict[str, float]], window_time: List[float], user_email: str) -> List[float]:
    """
    Calculate energy expenditure from gyroscope and accelerometer data
    """
    try:
        # Get user profile
        user_profile = get_user_profile(user_email)
        
        # Compute basal metabolic rate
        stand_aug_fact = 1.41  # Standing augmentation factor
        height = user_profile['height']
        weight = user_profile['weight']
        age = user_profile['age']
        gender = user_profile['gender']
        cur_basal = utils.basalEst(height, weight, age, gender, stand_aug_fact, kcalPerDay2Watt=0.048426)

        # Convert input data to numpy arrays
        gyro_array = np.array([[d['x'], d['y'], d['z']] for d in gyro_data])
        acc_array = np.array([[d['x'], d['y'], d['z']] for d in acc_data])
        time_array = np.array(window_time)

        # Apply low-pass filter
        gyro_filtered = signal.filtfilt(b, a, gyro_array, axis=0)
        acc_filtered = signal.filtfilt(b, a, acc_array, axis=0)

        # Calculate L2 norm of gyro data
        l2_norm_gyro = np.linalg.norm(gyro_filtered, axis=1)

        if np.max(l2_norm_gyro) > gyro_norm_thres:
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
                # Segment data
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
    except Exception as e:
        error_message = f"Error in calculate_energy_expenditure for user {user_email}. Details: {str(e)}. "
        error_message += f"Gyro data shape: {np.array(gyro_data).shape if gyro_data else 'N/A'}, "
        error_message += f"Acc data shape: {np.array(acc_data).shape if acc_data else 'N/A'}, "
        error_message += f"Window time length: {len(window_time) if window_time else 'N/A'}"
        print(f"ERROR: {error_message}")
        raise Exception(error_message)

def process_window(window: List[Dict[str, Any]], window_index: int, session_id: str, user_email: str, cur_basal: float) -> List[Dict[str, Any]]:
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
    try:
        ee_values = calculate_energy_expenditure(gyro_data, acc_data, window_time, user_email)
        print(f"Raw ee_values from calculate_energy_expenditure: {ee_values}")
        print(f"Type of ee_values: {type(ee_values)}")
        
        if ee_values is None:
            print(f"WARNING: calculate_energy_expenditure returned None for window {window_index + 1}")
            ee_values = [cur_basal]
        else:
            # Convert numpy float32 to regular Python float
            try:
                ee_values = [float(value) for value in ee_values]
                print(f"Converted ee_values: {ee_values}")
            except (ValueError, TypeError) as e:
                print(f"ERROR: Failed to convert ee_values to float: {e}")
                print(f"Problematic ee_values: {ee_values}")
                ee_values = [cur_basal]
    except Exception as e:
        print(f"ERROR: Exception in calculate_energy_expenditure: {str(e)}")
        ee_values = [cur_basal]

    print(f"Final ee_values before processing: {ee_values}")

    results = []
    if len(ee_values) > 0:
        window_start_time = datetime.fromisoformat(window[0]['Timestamp']['S'].replace('Z', '+00:00'))
        window_end_time = datetime.fromisoformat(window[-1]['Timestamp']['S'].replace('Z', '+00:00'))
        time_per_gait_cycle = (window_end_time - window_start_time).total_seconds() / len(ee_values)
    else:
        print(f"WARNING: No EE values for window {window_index + 1} in session {session_id}. Skipping window.")
        return results

    # Store each result
    for j, ee_value in enumerate(ee_values):
        gait_cycle_timestamp = window_start_time + timedelta(seconds=j * time_per_gait_cycle)
        
        # Validate ee_value and cur_basal before storing
        if not np.isfinite(ee_value) or not np.isfinite(cur_basal):
            print(f"WARNING: Non-finite EE value ({ee_value}) or BMR ({cur_basal}) for session {session_id}, user {user_email}, window {window_index + 1}, gait cycle {j + 1}. Skipping DynamoDB put for this entry.")
            results.append({
                'timestamp': gait_cycle_timestamp.isoformat(),
                'energyExpenditure': None,
                'error': f'Non-finite EE ({ee_value}) or BMR ({cur_basal}) detected',
                'windowIndex': window_index,
                'gaitCycleIndex': j
            })
            continue

        print(f"Window {window_index + 1}, Gait Cycle {j + 1}:")
        print(f"Window start: {window_start_time.isoformat()}")
        print(f"Window end: {window_end_time.isoformat()}")
        print(f"Time per cycle: {time_per_gait_cycle}")
        print(f"Timestamp: {gait_cycle_timestamp.isoformat()}")
        print(f"EE value: {ee_value}")
        print(f"Basal metabolic rate: {cur_basal}")

        # Store result in DynamoDB
        result_item = {
            'TableName': os.environ['RESULTS_TABLE'],
            'Item': {
                'SessionId': {'S': session_id},
                'Timestamp': {'S': gait_cycle_timestamp.isoformat()},
                'UserEmail': {'S': user_email},
                'EnergyExpenditure': {'N': str(ee_value)},
                'WindowIndex': {'N': str(window_index)},
                'GaitCycleIndex': {'N': str(j)},
                'BasalMetabolicRate': {'N': str(cur_basal)}
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

def process_message(message):
    """Process a single message from the queue"""
    try:
        data = json.loads(message['Body'])
        session_id = data['session_id']
        user_email = data['user_email']
        
        print(f"\n==============================\nProcessing session_id: {session_id} for user: {user_email}\n==============================")
        update_processing_status(session_id, 'processing', 0)
        
        try:
            user_profile = get_user_profile(user_email)
            cur_basal = utils.basalEst(user_profile['height'], user_profile['weight'], 
                                     user_profile['age'], user_profile['gender'], 
                                     1.41, kcalPerDay2Watt=0.048426)
            
            # --- Chunked Processing Variables ---
            last_evaluated_key = None
            all_results: List[Dict[str, Any]] = []
            overlap_buffer: List[Dict[str, Any]] = []
            window_size = 200
            current_items_for_chunk: List[Dict[str, Any]] = []
            PROCESSING_CHUNK_TARGET_SIZE = window_size * 10
            total_items_processed_into_windows = 0
            global_window_count = 0
            
            while True:
                try:
                    query_params = {
                        'TableName': os.environ['RAW_SENSOR_TABLE'],
                        'KeyConditionExpression': 'SessionId = :sessionId AND #ts >= :minTimestamp',
                        'ExpressionAttributeNames': {'#ts': 'Timestamp'},
                        'ExpressionAttributeValues': {
                            ':sessionId': {'S': session_id},
                            ':minTimestamp': {'S': '0000-01-01T00:00:00Z'}
                        },
                        'Limit': 1000,
                        'ScanIndexForward': True
                    }
                    if last_evaluated_key:
                        query_params['ExclusiveStartKey'] = last_evaluated_key
                    
                    query_result = dynamodb.query(**query_params)
                    items_from_db_page = query_result.get('Items', [])
                    
                    last_evaluated_key = query_result.get('LastEvaluatedKey')
                    print(f"[DEBUG] last_evaluated_key after query: {last_evaluated_key}")

                    if not items_from_db_page:
                        break
                    
                    current_items_for_chunk.extend(items_from_db_page)
                    
                    # Process chunks as before
                    can_process_chunk = len(current_items_for_chunk) >= PROCESSING_CHUNK_TARGET_SIZE
                    is_last_batch_from_db = not last_evaluated_key
                    has_pending_data_to_process = current_items_for_chunk or overlap_buffer
                    
                    if (can_process_chunk or is_last_batch_from_db) and has_pending_data_to_process:
                        data_to_process_now = overlap_buffer + current_items_for_chunk
                        current_items_for_chunk = []
                        overlap_buffer = []

                        # Debug: print timestamps of first and last items in data_to_process_now
                        if data_to_process_now:
                            try:
                                first_ts = data_to_process_now[0]['Timestamp']['S']
                                last_ts = data_to_process_now[-1]['Timestamp']['S']
                                print(f"[DEBUG] Processing batch: {len(data_to_process_now)} items, first_ts: {first_ts}, last_ts: {last_ts}")
                            except Exception as e:
                                print(f"[DEBUG] Could not extract timestamps from data_to_process_now: {e}")
                        else:
                            print("[DEBUG] data_to_process_now is empty")
                        
                        if not data_to_process_now or (is_last_batch_from_db and len(data_to_process_now) < window_size):
                            # No more data, or not enough for a full window at the end
                            break
                        
                        num_items_in_current_processing_batch = len(data_to_process_now)
                        num_full_windows_in_batch = num_items_in_current_processing_batch // window_size
                        end_index_for_full_windows = num_full_windows_in_batch * window_size
                        
                        if end_index_for_full_windows > 0:
                            for i in range(0, end_index_for_full_windows, window_size):
                                window_data = data_to_process_now[i : i + window_size]
                                window_results = process_window(window_data, global_window_count, 
                                                             session_id, user_email, cur_basal)
                                all_results.extend(window_results)
                                global_window_count += 1
                            
                            total_items_processed_into_windows += end_index_for_full_windows
                            
                            # Update progress
                            denominator = total_items_processed_into_windows + len(overlap_buffer)
                            if denominator > 0:
                                progress = (total_items_processed_into_windows / denominator) * 100
                                update_processing_status(session_id, 'processing', progress)
                            else:
                                # Only update status if there is meaningful progress
                                update_processing_status(session_id, 'processing', 0.0)
                        
                        overlap_buffer = data_to_process_now[end_index_for_full_windows:]
                        print(f"[DEBUG] overlap_buffer length after processing: {len(overlap_buffer)}")

                        # Fix: break if last batch and overlap_buffer is less than window_size
                        if is_last_batch_from_db and len(overlap_buffer) < window_size:
                            print(f"[DEBUG] Breaking loop: last batch and overlap_buffer has {len(overlap_buffer)} items (less than window_size).")
                            break
                
                except Exception as e:
                    print(f"Error processing chunk: {str(e)}")
                    update_processing_status(session_id, 'failed', error=str(e))
                    raise
            
            if not all_results:
                update_processing_status(session_id, 'failed', 
                                      error='No results generated from processing')
                return
            
            update_processing_status(session_id, 'completed', 100)
            
        except Exception as e:
            print(f"Error processing session: {str(e)}")
            update_processing_status(session_id, 'failed', error=str(e))
            raise
            
    except Exception as e:
        print(f"Error processing message: {str(e)}")
        raise

def main():
    """Main worker loop"""
    print("Starting energy expenditure processing worker")
    
    while True:
        try:
            # Receive message from queue
            response = sqs.receive_message(
                QueueUrl=os.environ['PROCESSING_QUEUE_URL'],
                MaxNumberOfMessages=1,
                WaitTimeSeconds=20
            )
            
            if 'Messages' in response:
                for message in response['Messages']:
                    try:
                        process_message(message)
                        # Delete message from queue after successful processing
                        sqs.delete_message(
                            QueueUrl=os.environ['PROCESSING_QUEUE_URL'],
                            ReceiptHandle=message['ReceiptHandle']
                        )
                    except Exception as e:
                        print(f"Error processing message: {str(e)}")
                        # Message will return to queue after visibility timeout
                        continue
            
        except Exception as e:
            print(f"Error in main loop: {str(e)}")
            time.sleep(5)  # Wait before retrying

if __name__ == '__main__':
    main() 