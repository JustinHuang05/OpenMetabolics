import torch

# Load the file and inspect what it contains
# file_path = 'data_driven_ee_model.pkl'
file_path = 'pocket_motion_correction_model.pkl'

try:
    # Try loading the file using torch.load()
    model = torch.load(file_path)

    # Check the type of the loaded object
    print(f"Loaded object type: {type(model)}")

    # If it's a state_dict (a dictionary), print its keys
    if isinstance(model, dict):
        print("This is a state_dict with the following keys:")
        print(model.keys())
    
    # If it's a model object, check its type and structure
    elif isinstance(model, torch.nn.Module):
        print("This is a full PyTorch model.")
        print(model)

    else:
        print(f"The file contains an unexpected object of type {type(model)}.")

except Exception as e:
    print(f"Error loading the model: {e}")
