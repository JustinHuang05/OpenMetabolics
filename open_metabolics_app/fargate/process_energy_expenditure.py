import os
import json
import boto3
from datetime import datetime, timedelta
from typing import List, Dict, Any
from flask import Flask, request, jsonify

app = Flask(__name__)

# Initialize DynamoDB client
dynamodb = boto3.client('dynamodb')

def calculate_energy_expenditure(gyro_data: List[Dict[str, float]], acc_data: List[Dict[str, float]]) -> List[float]:
    """
    Calculate energy expenditure from gyroscope and accelerometer data.
    This is a placeholder implementation that should be replaced with the actual algorithm.
    """
    print(f"calculate_energy_expenditure called with {len(gyro_data)} data points")
    values = [100.0, 95.0, 105.0, 373.42]  # Example: returns multiple values per window
    print(f"Returning {len(values)} values: {', '.join(map(str, values))}")
    return values

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

    print(f"\nProcessing window {window_index + 1}:")
    print(f"Window size: {len(window)}")
    print(f"Window start time: {window[0]['Timestamp']['S']}")
    print(f"Window end time: {window[-1]['Timestamp']['S']}")

    # Calculate energy expenditure for this window
    ee_values = calculate_energy_expenditure(gyro_data, acc_data)
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
            'total_windows_processed': len(all_results),
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