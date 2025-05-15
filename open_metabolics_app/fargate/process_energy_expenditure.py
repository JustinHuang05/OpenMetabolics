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

# Load models
try:
    data_driven_model = pickle.load(open('./data_driven_ee_model.pkl', 'rb'))
    # Load pocket_motion_correction_model using pickle as it's a LinearRegression model
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
            raise Exception(error_msg) # Or return a specific error response
            
        item = response['Item']
        # Add more robust parsing for profile items
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
        # Avoid printing the raw exception if it contains sensitive info, log a generic one for client
        print(f"Error fetching/parsing user profile for {user_email}: {e}") 
        # Re-raise a more generic exception if you don't want to expose details
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
        # Consider logging traceback for more detailed debugging on the server
        # import traceback
        # print(traceback.format_exc())
        raise Exception(error_message) # Re-raise with more context

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
    window_start_time = datetime.fromisoformat(window[0]['Timestamp']['S'].replace('Z', '+00:00'))
    window_end_time = datetime.fromisoformat(window[-1]['Timestamp']['S'].replace('Z', '+00:00'))
    time_per_gait_cycle = (window_end_time - window_start_time).total_seconds() / len(ee_values)

    # Store each result
    for j, ee_value in enumerate(ee_values):
        gait_cycle_timestamp = window_start_time + timedelta(seconds=j * time_per_gait_cycle)
        
        # Validate ee_value and cur_basal before storing
        if not np.isfinite(ee_value) or not np.isfinite(cur_basal):
            print(f"WARNING: Non-finite EE value ({ee_value}) or BMR ({cur_basal}) for session {session_id}, user {user_email}, window {window_index + 1}, gait cycle {j + 1}. Skipping DynamoDB put for this entry.")
            results.append({
                'timestamp': gait_cycle_timestamp.isoformat(),
                'energyExpenditure': None, # Indicate error or missing data
                'error': f'Non-finite EE ({ee_value}) or BMR ({cur_basal}) detected',
                'windowIndex': window_index,
                'gaitCycleIndex': j
            })
            continue # Skip this problematic entry for DynamoDB

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
                'BasalMetabolicRate': {'N': str(cur_basal)}  # Store the actual BMR
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

        user_profile = get_user_profile(user_email)
        cur_basal = utils.basalEst(user_profile['height'], user_profile['weight'], user_profile['age'], user_profile['gender'], 1.41, kcalPerDay2Watt=0.048426)
        print(f"Calculated basal metabolic rate: {cur_basal} for user {user_email}")

        # --- Chunked Processing Variables ---
        last_evaluated_key = None
        all_results: List[Dict[str, Any]] = [] # Stores final EE results from all chunks
        
        # Buffer for items from the end of one chunk to prepend to the next
        overlap_buffer: List[Dict[str, Any]] = [] 
        window_size = 200  # Defined earlier in the file, e.g., 200 samples
        
        # Data accumulated from DynamoDB pages before being processed as a larger chunk
        current_items_for_chunk: List[Dict[str, Any]] = [] 
        
        # Target size for accumulating items before processing them. Not a hard limit.
        # e.g., 5 * window_size = 1000 items. Process roughly this many items at a time.
        PROCESSING_CHUNK_TARGET_SIZE = window_size * 10 # e.g. 2000 items (40 seconds of data)

        # Tracks the total number of sensor data items that have been formed into windows
        total_items_processed_into_windows = 0
        # Tracks the global window index across all chunks for consistent reporting
        global_window_count = 0
        # --- End Chunked Processing Variables ---

        print(f"Starting chunked data retrieval and processing for session {session_id}.")

        while True:
            query_params: Dict[str, Any] = {
                'TableName': os.environ['RAW_SENSOR_TABLE'],
                'KeyConditionExpression': 'SessionId = :sessionId',
                'ExpressionAttributeValues': {':sessionId': {'S': session_id}},
                'Limit': 1000,  # DB_PAGE_SIZE
                'ScanIndexForward': True
            }
            if last_evaluated_key:
                query_params['ExclusiveStartKey'] = last_evaluated_key

            query_result = dynamodb.query(**query_params)
            items_from_db_page = query_result.get('Items', [])
            current_items_for_chunk.extend(items_from_db_page)
            last_evaluated_key = query_result.get('LastEvaluatedKey')

            # Determine if we should process the accumulated data now
            # Process if: accumulated enough items OR no more data from DB and there's something to process
            can_process_chunk = len(current_items_for_chunk) >= PROCESSING_CHUNK_TARGET_SIZE
            is_last_batch_from_db = not last_evaluated_key
            has_pending_data_to_process = current_items_for_chunk or overlap_buffer

            if (can_process_chunk or is_last_batch_from_db) and has_pending_data_to_process:
                data_to_process_now = overlap_buffer + current_items_for_chunk
                current_items_for_chunk = [] # Reset for next accumulation
                overlap_buffer = []      # Will be repopulated from the end of data_to_process_now

                if not data_to_process_now:
                    if is_last_batch_from_db: # No more data and nothing to process
                        break
                    else: # Nothing to process yet, but more data might come
                        continue
                
                print(f"Processing chunk with {len(data_to_process_now)} items (includes overlap). Session: {session_id}")

                num_items_in_current_processing_batch = len(data_to_process_now)
                
                # How many full windows can we make from this current batch?
                num_full_windows_in_batch = num_items_in_current_processing_batch // window_size
                
                # Index up to which we will extract full windows
                end_index_for_full_windows = num_full_windows_in_batch * window_size

                if end_index_for_full_windows > 0:
                    for i in range(0, end_index_for_full_windows, window_size):
                        window_data = data_to_process_now[i : i + window_size]
                        # process_window uses window_index for logging and storing in DynamoDB.
                        # It needs to be a unique, sequential index for the entire session.
                        window_results = process_window(window_data, global_window_count, session_id, user_email, cur_basal)
                        all_results.extend(window_results)
                        global_window_count += 1
                    
                    total_items_processed_into_windows += end_index_for_full_windows

                # Items left over from this batch become the new overlap_buffer for the next iteration
                # This will be empty if the batch perfectly divided into windows.
                # Its length will be < window_size.
                overlap_buffer = data_to_process_now[end_index_for_full_windows:]
            
            if is_last_batch_from_db: # No more items to fetch from DynamoDB
                if overlap_buffer: # If there's a final bit of overlap less than a window
                    print(f"End of session {session_id}. {len(overlap_buffer)} items in final overlap buffer, too small for a window. Discarding.")
                print(f"Finished processing all available data for session {session_id}.")
                break # Exit the main while loop
        
        # This check is after the loop, ensuring we don't return 404 if any processing occurred
        if not all_results and total_items_processed_into_windows == 0:
            return jsonify({
                'error': 'No sensor data found or processed for this session.'
            }), 404

        # No global sort of all_sensor_data is performed as data is processed in chunks.
        # We rely on DynamoDB's ScanIndexForward for ordered data within chunks.

        print(f"Total items formed into windows for session {session_id}: {total_items_processed_into_windows}")
        print(f"Total windows processed: {global_window_count}")
        # The print statements for 'Final Results Summary' and 'Total results' will use global_window_count and len(all_results)

        # The rest of the function (preparing and returning the jsonify response) remains largely the same,
        # but it will use the `all_results` accumulated from chunks and `global_window_count`.
        # Ensure the response structure matches what the client expects.

        # Process the data in windows (4 seconds at 50Hz = 200 samples)
        # window_size = 200 # already defined
        # all_results = [] # already defined and populated

        # Process each window (This block is now effectively handled within the chunk processing loop)
        # for i in range(0, len(all_sensor_data), window_size):
        #     window = all_sensor_data[i:i + window_size]
        #     window_results = process_window(window, i // window_size, session_id, user_email, cur_basal)
        #     all_results.extend(window_results)

        print('\nFinal Results Summary:')
        # print(f"Total windows processed: {round(len(all_sensor_data) / window_size)}") # Old calculation
        print(f"Total windows successfully processed: {global_window_count}")
        print(f"Total energy expenditure results generated: {len(all_results)}")
        # print('Results:', json.dumps(all_results, indent=2)) # Can be very verbose

        return jsonify({
            'message': 'Energy expenditure calculation completed',
            'session_id': session_id,
            'total_windows_processed': global_window_count, # Use the global count
            'results': all_results,
            'basal_metabolic_rate': cur_basal
        })

    except Exception as error:
        print(f"Error processing energy expenditure for session {session_id}: {error}")
        import traceback
        traceback.print_exc() # Print full traceback for server-side debugging
        return jsonify({
            'error': str(error)
        }), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy'}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80) 