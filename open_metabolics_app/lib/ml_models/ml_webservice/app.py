# app.py
import pickle
from flask import Flask, request, jsonify

# Load the pocket correction model
with open('pocket_motion_correction_model.pkl', 'rb') as f:
    pocket_model = pickle.load(f)

# Load the ee model
with open('data_driven_ee_model.pkl', 'rb') as f:
    ee_model = pickle.load(f)


app = Flask(__name__)

@app.route('/')
def health_check():
    return jsonify({'status': 'healthy'}), 200

# Define prediction endpoint
@app.route('/predict_pocket_motion_correction', methods=['POST'])
def predict_pocket_motion_correction():
    data = request.get_json()
    features = data.get('features')
    
    # Ensure that features are in the correct format for batch prediction
    if isinstance(features[0], list):  # Multiple samples provided
        prediction = pocket_model.predict(features)
    else:  # Single sample provided
        prediction = pocket_model.predict([features])

    return jsonify({'prediction': prediction.tolist()})

# Define prediction endpoint
@app.route('/predict_ee', methods=['POST'])
def predict_ee():
    data = request.get_json()
    features = data.get('features')
    
    # Ensure that features are in the correct format for batch prediction
    if isinstance(features[0], list):  # Multiple samples provided
        prediction = ee_model.predict(features)
    else:  # Single sample provided
        prediction = ee_model.predict([features])

    return jsonify({'prediction': prediction.tolist()})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
