# import pickle
# from sklearn.linear_model import LinearRegression
# import tensorflow as tf
# import numpy as np

# # File paths
# pre_file_path = 'pseudo_lr_model/linear_model.pkl'
# post_file_path = 'pseudo_lr_model/linear_model_converted.tflite'

# # Load the scikit-learn LinearRegression model
# with open(pre_file_path, 'rb') as file:
#     model = pickle.load(file)

# # Check dimensions of the loaded model's weights
# input_dim = model.coef_.shape[0]  # Should match the number of input features (90 in this case)
# output_dim = model.coef_.shape[1] if model.coef_.ndim > 1 else 1  # Detect output dimension; set to 1 if single output

# # Build a TensorFlow model with the correct input and output dimensions
# tf_model = tf.keras.Sequential([
#     tf.keras.layers.InputLayer(input_shape=(input_dim,)),  # Input layer with `input_dim` inputs
#     tf.keras.layers.Dense(output_dim, use_bias=True)       # Output layer with `output_dim` outputs
# ])

# # Prepare the weights and biases from the scikit-learn model
# weights = np.array(model.coef_).reshape((input_dim, output_dim))  # Reshape in case of single output
# bias = np.array(model.intercept_)

# # Handle mismatch in the number of bias values (pad if needed)
# if bias.shape[0] != output_dim:
#     bias = np.pad(bias, (0, output_dim - bias.shape[0]), 'constant')

# # Set the weights and bias in the TensorFlow model
# tf_model.layers[0].set_weights([weights, bias])

# # Convert the TensorFlow model to TensorFlow Lite format
# converter = tf.lite.TFLiteConverter.from_keras_model(tf_model)
# tflite_model = converter.convert()

# # Save the TensorFlow Lite model
# with open(post_file_path, 'wb') as f:
#     f.write(tflite_model)

# print("Model successfully converted to TensorFlow Lite!")

import pickle
import tensorflow as tf

# Load the model from the .pkl file
with open('pseudo_lr_model/linear_model.pkl', 'rb') as file:
    model = pickle.load(file)

    # Assuming your model is a simple linear regression
input_dim = model.coef_.shape[0]  # Get the number of features

# Create a TensorFlow model
tf_model = tf.keras.Sequential([
    tf.keras.layers.Dense(1, input_shape=(input_dim,))
])

# Set the weights and bias from the loaded model
tf_model.layers[0].set_weights([model.coef_.reshape(-1, 1), model.intercept_])

# Convert the model to TensorFlow Lite
converter = tf.lite.TFLiteConverter.from_keras_model(tf_model)
tflite_model = converter.convert()

# Save the TensorFlow Lite model
with open('pseudo_lr_model/linear_model_converted.tflite', 'wb') as f:
    f.write(tflite_model)