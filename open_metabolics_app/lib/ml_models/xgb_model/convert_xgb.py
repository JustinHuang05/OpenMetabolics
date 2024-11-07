import pickle
import xgboost as xgb
import tensorflow as tf

# Step 1: Load the XGBoost model
def load_xgboost_model(pkl_path):
    with open(pkl_path, 'rb') as file:
        xgb_model = pickle.load(file)
    return xgb_model

# Step 2: Extract number of input features from the model
def get_num_features(xgb_model):
    num_features = xgb_model.n_features_in_
    return num_features

# Register the custom layer so it can be saved and loaded properly
@tf.keras.utils.register_keras_serializable()
class TreeLayer(tf.keras.layers.Layer):
    def __init__(self, tree, **kwargs):
        super(TreeLayer, self).__init__(**kwargs)
        self.tree = tree

    def call(self, inputs):
        conditions = []
        results = []

        # Parse the tree dump and create TensorFlow logic
        for line in self.tree.splitlines():
            if "yes" in line:  # It's a split condition
                feature = int(line.split('[')[1].split('<')[0].strip('f'))
                threshold = float(line.split('<')[1].split(']')[0])
                condition = tf.less(inputs[:, feature], threshold)
                conditions.append(condition)
            elif "leaf" in line:  # It's a leaf node
                value = float(line.split('leaf=')[1])
                results.append(value)

        # Initialize the output tensor
        output_tensor = tf.zeros_like(inputs[:, 0])

        # Apply conditions and select leaf values
        for i, condition in enumerate(conditions):
            output_tensor = tf.where(condition, results[i], output_tensor)

        return output_tensor

# Step 3: Convert the entire XGBoost model to TensorFlow
def convert_xgboost_to_tensorflow(xgb_model, input_shape):
    input_tensor = tf.keras.Input(shape=(input_shape,))
    
    # Get the raw string representation of the trees
    trees = xgb_model.get_booster().get_dump()

    # Convert each tree into a custom Keras layer and sum their outputs
    tree_outputs = []
    for tree in trees:
        tree_layer = TreeLayer(tree)
        tree_outputs.append(tree_layer(input_tensor))
    
    # Stack tree outputs and sum them to get the final output
    final_output = tf.keras.layers.Add()(tree_outputs)

    # Create and return a TensorFlow model
    return tf.keras.Model(inputs=input_tensor, outputs=final_output)

# Step 4: Save the TensorFlow model in SavedModel format
def save_tf_model(tf_model, save_path):
    # Save the model in TensorFlow SavedModel format
    tf_model.save(save_path)

def convert_keras_to_tflite(keras_model_path, tflite_model_path):
    # Step 1: Load the Keras model
    model = tf.keras.models.load_model(keras_model_path)

    # Step 2: Convert the model to TensorFlow Lite format
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()

    # Step 3: Save the converted model to a .tflite file
    with open(tflite_model_path, 'wb') as f:
        f.write(tflite_model)

# Main function to execute the conversion process
if __name__ == "__main__":
    # Path to the XGBoost model saved as a .pkl file
    pkl_model_path = "data_driven_ee_model.pkl"  # Replace with your actual file path
    keras_model_path = "xgb_model.keras"
    tflite_model_path = "xgb_model.tflite"

    # Load the XGBoost model
    xgb_model = load_xgboost_model(pkl_model_path)

    # Automatically get the number of features
    num_features = get_num_features(xgb_model)
    print(f"Number of features detected: {num_features}")

    # Convert the XGBoost model to TensorFlow
    tf_model = convert_xgboost_to_tensorflow(xgb_model, num_features)

    # Save the TensorFlow model to disk as a SavedModel
    save_tf_model(tf_model, keras_model_path)  # Use a directory name
    print("Model successfully converted and saved as a TensorFlow SavedModel.")

    convert_keras_to_tflite(keras_model_path, tflite_model_path)
    print(f"TFLite model successfully saved to {tflite_model_path}")



