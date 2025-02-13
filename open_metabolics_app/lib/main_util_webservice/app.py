# app.py
from flask import Flask, request, jsonify
import pandas as pd
import numpy as np
from scipy import signal
from scipy.linalg import norm
import utils

app = Flask(__name__)

@app.route('/process_csv', methods=['POST'])
def process_csv():
    # Check if 'file' is in the request
    if 'file' not in request.files:
        return jsonify({"error": "No file present in request"}), 400
    
    file = request.files['file']
    
    # Check if a file was selected
    if file.filename == '':
        return jsonify({"error": "No file selected"}), 400
    
    # Validate if the file is a CSV
    if not file.filename.endswith('.csv'):
        return jsonify({"error": "File is not a CSV"}), 400
    
    df = pd.read_csv(file)

    # Check if every row has exactly 7 columns
    if df.shape[1] != 7:
        return jsonify({"error": "CSV does not have exactly 7 columns. Found: {0}".format(df.shape[1])}), 400
    
    # Additional check: Ensure no rows are missing columns
    if df.isnull().any(axis=1).sum() > 0:
        return jsonify({"error": "CSV contains rows with missing values"}), 400
    
    try:
        
        
    except Exception as e:
        # Handle file processing errors
        return jsonify({"error": f"Failed to process the file: {str(e)}"}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)

