import os
import json
import boto3
from datetime import datetime
from flask import Flask, request, jsonify
from botocore.config import Config

app = Flask(__name__)

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

@app.route('/process', methods=['POST'])
def queue_energy_expenditure():
    try:
        data = request.get_json()
        print("Received request:", data)

        if not data or not data.get('session_id') or not data.get('user_email'):
            return jsonify({
                'error': 'Missing required fields (session_id or user_email)'
            }), 400

        session_id = data['session_id']
        user_email = data['user_email']

        # Verify session exists in DynamoDB
        try:
            # Query for the first item for this session using both SessionId and Timestamp
            response = dynamodb.query(
                TableName=os.environ['RAW_SENSOR_TABLE'],
                KeyConditionExpression='SessionId = :sessionId AND #ts >= :minTimestamp',
                ExpressionAttributeNames={'#ts': 'Timestamp'},
                ExpressionAttributeValues={
                    ':sessionId': {'S': session_id},
                    ':minTimestamp': {'S': '0000-01-01T00:00:00Z'}  # earliest possible ISO8601
                },
                Limit=1
            )
            
            if not response.get('Items'):
                return jsonify({
                    'error': f'No data found for session {session_id}'
                }), 404
        except Exception as e:
            print(f"Error verifying session: {str(e)}")
            return jsonify({
                'error': 'Error verifying session data'
            }), 500

        # Initialize processing status in DynamoDB
        try:
            dynamodb.put_item(
                TableName=os.environ['PROCESSING_STATUS_TABLE'],
                Item={
                    'SessionId': {'S': session_id},
                    'Status': {'S': 'queued'},
                    'UserEmail': {'S': user_email},
                    'QueuedAt': {'S': datetime.utcnow().isoformat()},
                    'Progress': {'N': '0'}
                }
            )
        except Exception as e:
            print(f"Error initializing processing status: {str(e)}")
            return jsonify({
                'error': 'Error initializing processing status'
            }), 500

        # Queue the processing job
        try:
            message = {
                'session_id': session_id,
                'user_email': user_email
            }
            
            response = sqs.send_message(
                QueueUrl=os.environ['PROCESSING_QUEUE_URL'],
                MessageBody=json.dumps(message)
            )
            
            return jsonify({
                'message': 'Processing queued successfully',
                'session_id': session_id,
                'job_id': response['MessageId']
            }), 202

        except Exception as e:
            print(f"Error queueing job: {str(e)}")
            # Update status to failed
            try:
                dynamodb.update_item(
                    TableName=os.environ['PROCESSING_STATUS_TABLE'],
                    Key={'SessionId': {'S': session_id}},
                    UpdateExpression='SET #status = :status, #error = :error',
                    ExpressionAttributeNames={'#status': 'Status', '#error': 'Error'},
                    ExpressionAttributeValues={
                        ':status': {'S': 'failed'},
                        ':error': {'S': f'Failed to queue job: {str(e)}'}
                    }
                )
            except Exception as update_error:
                print(f"Error updating status to failed: {str(update_error)}")
            
            return jsonify({
                'error': 'Error queueing processing job'
            }), 500

    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        return jsonify({
            'error': 'Unexpected error occurred'
        }), 500

@app.route('/status/<session_id>', methods=['GET'])
def get_processing_status(session_id):
    try:
        response = dynamodb.get_item(
            TableName=os.environ['PROCESSING_STATUS_TABLE'],
            Key={'SessionId': {'S': session_id}}
        )
        
        if 'Item' not in response:
            return jsonify({'error': 'Session not found'}), 404
            
        status = response['Item']['Status']['S']
        progress = response['Item'].get('Progress', {'N': '0'})['N']
        error = response['Item'].get('Error', {'S': None})['S']

        return jsonify({
            'session_id': session_id,
            'status': status,
            'progress': float(progress),
            'error': error
        })
    except Exception as e:
        print(f"Error getting status: {str(e)}")
        return jsonify({'error': 'Error getting processing status'}), 500

@app.route('/results/<session_id>', methods=['GET'])
def get_processing_results(session_id):
    try:
        response = dynamodb.query(
            TableName=os.environ['RESULTS_TABLE'],
            KeyConditionExpression='SessionId = :sid',
            ExpressionAttributeValues={':sid': {'S': session_id}}
        )
        
        if not response.get('Items'):
            return jsonify({'error': 'No results found'}), 404
        
        return jsonify({
            'session_id': session_id,
            'results': response['Items']
        })
    except Exception as e:
        print(f"Error getting results: {str(e)}")
        return jsonify({'error': 'Error getting processing results'}), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy'}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80) 