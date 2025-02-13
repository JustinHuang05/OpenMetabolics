import pickle

with open("data_driven_ee_model.pkl", "rb") as f:
    model = pickle.load(f)

# Now save it properly in the XGBoost format
import xgboost as xgb

model.save_model("data_driven_ee_model.json")
