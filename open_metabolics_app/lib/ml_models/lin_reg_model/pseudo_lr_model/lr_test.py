import numpy as np
import pickle
import tensorflow as tf

# File paths
model_file_path = 'linear_model.pkl'
tflite_model_path = 'linear_model_converted.tflite'

# Fix np.random.seed
np.random.seed(1000)

# Load input features and output for testing
test_input = np.random.rand(1, 108)

# Load the original model (from .pkl)
with open(model_file_path, 'rb') as file:
    original_model = pickle.load(file)

# Predict using the original model
original_predicted_output = original_model.predict(test_input)
print(f"Original Model Prediction: {original_predicted_output}")    

# Load the TFLite model
interpreter = tf.lite.Interpreter(model_path=tflite_model_path)
interpreter.allocate_tensors()

# Get input and output details
input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

# Print the expected input shape for debugging
print(f"Expected input shape for TFLite model: {input_details[0]['shape']}")

# Adjust test_input to match the TFLite model's expected input shape
expected_shape = input_details[0]['shape']
if expected_shape[1] != test_input.shape[1]:
    test_input = np.random.rand(*expected_shape).astype(np.float32)  # Generate new test input with the correct shape
else:
    test_input = test_input.astype(np.float32)  # Cast test_input to float32 if shape matches

# Set the tensor for the model input
interpreter.set_tensor(input_details[0]['index'], test_input)

# Run the TFLite model
interpreter.invoke()

# Get the output from the TFLite model
tflite_predicted_output = interpreter.get_tensor(output_details[0]['index'])
print(f"TFLite Model Prediction: {tflite_predicted_output}")

# Check if the predictions match
if np.allclose(original_predicted_output, tflite_predicted_output, rtol=1e-05):
    print("The predictions match!")
else:
    print("The predictions do not match.")
