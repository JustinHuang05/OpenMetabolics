import numpy as np
import requests
import json
import pickle

# File path to the .pkl model
model_file_path = 'data_driven_ee_model.pkl'

# Fix np.random.seed
np.random.seed(1000)

# can change for testing
num_samples = 10

# Generate the test input data
test_input = np.random.rand(num_samples, 108)

# Part 1: Prediction via API

# Define the URL of your local API endpoint
# url = "http://localhost:8080"
url = "https://data-driven-webservice-735933323813.us-east1.run.app"

# Prepare the JSON payload
payload = json.dumps({
    "features": test_input.tolist()  # Flattening the array for compatibility with the API
})

# Set headers for JSON data
headers = {
    "Content-Type": "application/json"
}

# Send a POST request to the API
response = requests.post(url + "/predict", data=payload, headers=headers)

# Check if the request was successful and extract the prediction
if response.status_code == 200:
    api_predicted_output = response.json().get("prediction")
    
    # Flatten api_predicted_output if it’s a nested list
    if isinstance(api_predicted_output[0], list):
        api_predicted_output = [item for sublist in api_predicted_output for item in sublist]
    else:
        api_predicted_output = [float(pred) for pred in api_predicted_output]
        
    print(f"API Model Prediction: {api_predicted_output}")
else:
    print(f"Request failed with status code: {response.status_code}")
    print("Response:", response.text)
    api_predicted_output = None

# Part 2: Prediction using the .pkl model directly

# Load the .pkl model
with open(model_file_path, 'rb') as file:
    original_model = pickle.load(file)

# Predict using the original model
direct_predicted_output = original_model.predict(test_input).tolist()
print(f"Direct Model Prediction: {direct_predicted_output}")

# Part 3: Compare the two predictions

# Ensure `api_predicted_output` is reshaped correctly for comparison
if api_predicted_output is not None:
    
    # Now compare the reshaped predictions
    if np.allclose(direct_predicted_output, api_predicted_output, rtol=1e-05):
        print("The predictions match!")
    else:
        print("The predictions do not match.")
else:
    print("API prediction was not successful, so comparison cannot be made.")

