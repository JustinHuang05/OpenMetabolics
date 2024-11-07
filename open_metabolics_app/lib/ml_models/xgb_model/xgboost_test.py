import numpy as np
import pickle
import tensorflow as tf

# Load input features from a CSV file
input_features = np.loadtxt('./input.csv')

# Load the pre-trained XGBoost model
with open('./data_driven_ee_model.pkl', 'rb') as model_file:
    xgb_model = pickle.load(model_file)

# Make a prediction using the XGBoost model
xgb_model_output = xgb_model.predict(input_features.reshape(1, -1))[0]
print(f"The output value of the XGBoost model given input: {xgb_model_output}")

# Load the TFLite model
tflite_model_path = './data_driven_ee_xgb_model.tflite'
interpreter = tf.lite.Interpreter(model_path=tflite_model_path)
interpreter.allocate_tensors()

# Get input and output details for the TFLite model
input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

# Prepare the input data for the TFLite model
# Ensure that the input is reshaped to match the expected shape of the TFLite model
tflite_input = input_features.reshape(1, -1).astype(np.float32)

# Set the tensor for the model input
interpreter.set_tensor(input_details[0]['index'], tflite_input)

# Run the model
interpreter.invoke()

# Get the output from the TFLite model
tflite_model_output = interpreter.get_tensor(output_details[0]['index'])[0]
print(f"The output value of the TFLite model given input: {tflite_model_output}")

# Check if the predictions match
if np.isclose(xgb_model_output, tflite_model_output, rtol=1e-05):
    print("The predictions of the XGBoost model and TFLite model match!")
else:
    print("The predictions of the XGBoost model and TFLite model do not match.")
