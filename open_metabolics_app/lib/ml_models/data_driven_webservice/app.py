# app.py
import pickle
from flask import Flask, request, jsonify

# Load the model
with open('data_driven_ee_model.pkl', 'rb') as f:
    model = pickle.load(f)

app = Flask(__name__)

# Define prediction endpoint
@app.route('/predict', methods=['POST'])
def predict():
    data = request.get_json()
    features = data.get('features')
    
    # Ensure that features are in the correct format for batch prediction
    if isinstance(features[0], list):  # Multiple samples provided
        prediction = model.predict(features)
    else:  # Single sample provided
        prediction = model.predict([features])

    return jsonify({'prediction': prediction.tolist()})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
