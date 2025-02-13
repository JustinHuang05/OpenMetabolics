"""
Copyright (c) 2024 Harvard Ability lab
Title: "A smartphone activity monitor that accurately estimates energy expenditure"
"""

import numpy as np
from scipy import signal
from numpy import linalg as LA
import pickle
import os
import matplotlib.pyplot as plt
from itertools import groupby
from scipy.linalg import norm

def basalEst(height, weight, age, gender, stand_aug_fact, kcalPerDay2Watt=0.048426):
    """Estimate basal metabolic rate"""
    offset = 5 if gender == 'M' else -161
    return (10.0 * weight + 625.0 * height - 5.0 * age + offset) * kcalPerDay2Watt * stand_aug_fact

def get_active_phase(gyro_l2_norm, gyro_norm_win, gyro_norm_thres):
    """Detect active phases in gyroscopic data based on norm threshold over a sliding window"""
    idx_process = []
    for idx in range(len(gyro_l2_norm)):
        if idx + gyro_norm_win >= len(gyro_l2_norm):
            break
        cur_win_gyro_norm = gyro_l2_norm[idx:idx + gyro_norm_win]
        if np.mean(cur_win_gyro_norm) > gyro_norm_thres:
            idx_process.append(idx)
    return idx_process

def find_consecutive(indices):
    """Group consecutive indices together"""
    result = []
    for _, group in groupby(enumerate(indices), lambda x: x[0] - x[1]):
        group = list(map(lambda x: x[1], group))
        if len(group) > 1:
            result.append(group)
    return result

def rotm_x(theta):
    """Create a rotation matrix for rotation around the x-axis"""
    return [[1, 0, 0], [0, np.cos(theta), -np.sin(theta)], [0, np.sin(theta), np.cos(theta)]]

def rotm_y(theta):
    """Create a rotation matrix for rotation around the y-axis"""
    return [[np.cos(theta), 0, np.sin(theta)], [0, 1, 0], [-np.sin(theta), 0, np.cos(theta)]]

def rotm_z(theta):
    """Create a rotation matrix for rotation around the z-axis"""
    return [[np.cos(theta), -np.sin(theta), 0], [np.sin(theta), np.cos(theta), 0], [0, 0, 1]]

def get_rotate_y(input_data, prin_idx):
    """Compute a rotation matrix around the y-axis using local acceleration data"""
    pos_idx = np.where(input_data[:, prin_idx] > 0)[0]
    theta = np.linspace(-np.pi, np.pi, 1000)

    opt_theta = None
    opt_rotm_y = None
    cur_max_gyro_z = np.sum(input_data[pos_idx, 2])

    for cur_theta in theta:
        cur_rotm = rotm_y(cur_theta)
        rot_gyro = np.matmul(input_data, cur_rotm)
        if np.sum(rot_gyro[pos_idx, 2]) > cur_max_gyro_z:
            cur_max_gyro_z = np.sum(rot_gyro[pos_idx, 2])
            opt_theta = cur_theta
            opt_rotm_y = cur_rotm
    return opt_rotm_y if opt_rotm_y is not None else np.identity(3), int(np.rad2deg(opt_theta)) if opt_theta is not None else 0

def get_rotate_z(acc):
    """Compute a rotation matrix around the z-axis using local acceleration data"""
    cur_acc_y_mean = np.mean(acc[:, 1])
    theta = np.linspace(-np.pi, np.pi, 1000)
    opt_theta = None
    opt_rotm_z = None

    for cur_theta in theta:
        cur_rotm = rotm_z(cur_theta)
        cur_rot_acc = np.matmul(acc, cur_rotm)
        if np.mean(cur_rot_acc[:, 1]) > cur_acc_y_mean:
            cur_acc_y_mean = np.mean(cur_rot_acc[:, 1])
            opt_theta = cur_theta
            opt_rotm_z = cur_rotm
    return opt_rotm_z if opt_rotm_z is not None else np.identity(3), int(np.rad2deg(opt_theta)) if opt_theta is not None else 0

def find_prin_axis(input_data):
    """Find the principal axis of angular velocity"""
    gyro_x = input_data[:, 0]
    gyro_z = input_data[:, 2]
    return 0 if LA.norm(gyro_x) > LA.norm(gyro_z) else 2

def processRawGait(data_array, start_ind, end_ind, num_bins=30):
    """Process raw gait data by cropping and resampling"""
    gait_data = data_array[start_ind:end_ind, :]
    dur_stride = gait_data.shape[0] / 100
    return signal.resample(gait_data, num_bins, axis=0)

def peak_detect(input_data):
    """Detect significant peaks in the input data"""
    fs = 50
    peak_height_thresh = np.deg2rad(70)
    peak_min_dist = int(0.6 * fs)
    return signal.find_peaks(input_data, height=peak_height_thresh, distance=peak_min_dist)[0]

def segment_data(peak_index_list, data_to_segment, stride_detect_window):
    """Segment data based on identified peak indices"""
    gait_data = []
    for i in range(len(peak_index_list) - 1):
        gait_start_index = peak_index_list[i]
        gait_stop_index = peak_index_list[i + 1]
        if (gait_stop_index - gait_start_index) <= stride_detect_window and (gait_stop_index - gait_start_index) > 35:
            cur_gait_data = processRawGait(data_to_segment, gait_start_index, gait_stop_index)
            gait_data.append(cur_gait_data)
    return np.array(gait_data)

def get_features(signal):
    """Extract statistical features from the signal"""
    from scipy.stats import skew
    return np.array([np.mean(signal), np.std(signal), np.median(signal), skew(signal), LA.norm(signal, ord=2)])

def processRawGait_model(data_array, start_ind, end_ind, weight, height, correction_model, cur_device, num_bins=30):
    """Process raw gait data for model input preparation"""
    fs = 50
    gait_data = data_array[start_ind:end_ind, :]
    dur_stride = gait_data.shape[0] / fs
    bin_gait = signal.resample(gait_data, num_bins, axis=0)
    shift_flip_bin_gait = bin_gait.transpose()
    model_input = shift_flip_bin_gait.flatten()

    """Correct motion artifacts"""
    est_artifact = correction_model.predict(np.insert(model_input, 0, dur_stride).reshape(1, -1)).flatten()
    model_input = model_input - est_artifact

    gyro_x = model_input[:30]
    gyro_y = model_input[30:60]
    gyro_z = model_input[60:90]

    gyro_x_feat = get_features(gyro_x)
    gyro_y_feat = get_features(gyro_y)
    gyro_z_feat = get_features(gyro_z)

    model_input = np.concatenate((model_input.reshape(-1, 1), gyro_x_feat.reshape(-1, 1), gyro_y_feat.reshape(-1, 1), gyro_z_feat.reshape(-1, 1)), axis=0).flatten()
    model_input = np.insert(model_input, 0, [weight, height, dur_stride])

    return model_input

def estimateMetabolics(model, gait_data, peak_index, weight, height, cur_basal, correction_model, stride_detect_window):
    """Estimate energy expenditure per step for a single detected bout."""
    
    ee_all = []
    for step_idx in range(len(peak_index) - 1):
        gait_start_index = peak_index[step_idx]
        gait_stop_index = peak_index[step_idx + 1]

        if 35 < (gait_stop_index - gait_start_index) <= stride_detect_window:
            # Process raw gait data and prepare input
            model_input = processRawGait_model(
                gait_data, gait_start_index, gait_stop_index, weight, height, correction_model, None
            ).reshape(1, -1)

            # Log feature size
            print(f"Step {step_idx + 1}: Processed model input has {model_input.shape[1]} features.")
            
            # Perform model prediction
            ee_est = model.predict(model_input)[0]
            print(f"Step {step_idx + 1}: Predicted energy expenditure = {ee_est:.2f} kcal/min.")
            
            ee_all.append(ee_est)
        else:
            print(f"Step {step_idx + 1}: Invalid step duration, using basal metabolic rate.")
            ee_all.append(cur_basal)

    return ee_all

