"""
Copyright (c) 2024 Harvard Ability lab
Title: "A smartphone activity monitor that accurately estimates energy expenditure"
"""

import os
import numpy as np
import pandas as pd
import pickle
import matplotlib.pyplot as plt
from scipy import signal
from scipy.linalg import norm
import utils

"""Load subject information from CSV"""
subj_csv = pd.read_csv('./subject_info.csv')
target_subj = 'S1'
subj_info = {
    'code': subj_csv.loc[subj_csv['subject'] == target_subj, 'subject'].values[0],
    'weight': subj_csv.loc[subj_csv['subject'] == target_subj, 'weight'].values[0],
    'height': subj_csv.loc[subj_csv['subject'] == target_subj, 'height'].values[0],
    'gender': subj_csv.loc[subj_csv['subject'] == target_subj, 'gender'].values[0],
    'age': subj_csv.loc[subj_csv['subject'] == target_subj, 'age'].values[0]
}

"""Compute the basal metabolic rate"""
stand_aug_fact = 1.41
height = subj_info['height']
weight = subj_info['weight']
age = subj_info['age']
gender = subj_info['gender']
cur_basal = utils.basalEst(height, weight, age, gender, stand_aug_fact, kcalPerDay2Watt=0.048426)

model_url = "https://data-driven-webservice-735933323813.us-east1.run.app/predict"
correction_url = "https://pocket-motion-webservice-735933323813.us-east1.run.app/predict"

"""Load daily smartphone data"""
csv_path = './example_data/just_testing.csv'
df_sp = pd.read_csv(csv_path).values

"""Constants for low-pass filter"""
sampling_freq = 50  # Sampling frequency in Hz
crossover_freq = 6  # Crossover frequency for low-pass filter in Hz
filt_order = 4  # Filter order

"""Constants for bout detection algorithm"""
sliding_win = 200  # Window size for sliding window in samples (4 seconds at 50Hz)
gyro_norm_thres = 0.5  # Threshold for gyro norm in rad/s

"""Low-pass filter parameters"""
b, a = signal.butter(filt_order, crossover_freq, btype='low', fs=sampling_freq)

"""Filter the collected smartphone data"""
time_sp = df_sp[:, 0]
gyro_sp = signal.filtfilt(b, a, df_sp[:, 1:4], axis=0)  # Filter gyro data
acc_sp = signal.filtfilt(b, a, df_sp[:, 4:], axis=0)  # Filter accelerometer data

"""Bout detection: Identify active phases based on the norm of gyro data"""
gyro_l2_norm_sp = norm(gyro_sp, ord=2, axis=1)
active_idx = utils.get_active_phase(gyro_l2_norm_sp, sliding_win, gyro_norm_thres)
active_idx = utils.find_consecutive(active_idx)

"""Initialize lists to collect energy expenditure data"""
ee_all = []

"""Step 1: Process each detected active bout"""
for idx, cur_active_idx in enumerate(active_idx):
    stride_detect_window = 2 * sampling_freq  # Stride detection window in samples (2 seconds)
    start_idx = cur_active_idx[0]
    end_idx = cur_active_idx[-1]
    cur_pocket_gyro = gyro_sp[start_idx:end_idx, :]
    cur_pocket_acc = acc_sp[start_idx:end_idx, :]

    # Print bout details
    num_rows = end_idx - start_idx
    print(f"Bout {idx + 1}: Start index = {start_idx}, End index = {end_idx}, Rows = {num_rows}")

    """Step 2: Orientation alignment: Align with the superior-inferior axis of the thigh"""
    opt_rotm_z_pocket, theta_z = utils.get_rotate_z(cur_pocket_acc)
    cur_pocket_gyro_rot_zx = np.matmul(cur_pocket_gyro, opt_rotm_z_pocket)

    """Find principal axis of angular velocity"""
    prin_idx_pocket = utils.find_prin_axis(cur_pocket_gyro_rot_zx)
    prin_gyro_pocket = cur_pocket_gyro_rot_zx[:, prin_idx_pocket]
    
    if np.abs(np.max(prin_gyro_pocket)) < np.abs(np.min(prin_gyro_pocket)):
        prin_gyro_pocket = -prin_gyro_pocket

    """Detect peaks in the principal angular velocity"""
    gait_peaks = utils.peak_detect(prin_gyro_pocket)
    
    if len(gait_peaks) > 3:  # Consider it a bout if more than 3 peaks are detected
        gait_data_pocket = utils.segment_data(gait_peaks, cur_pocket_gyro_rot_zx, stride_detect_window)
        if len(gait_data_pocket) < 1:
            continue

        """Step 2: Orientation alignment: Align with the mediolateral axis of the thigh"""
        avg_gait_data_pocket = np.mean(gait_data_pocket, axis=0)
        opt_rotm_y_pocket, theta_y = utils.get_rotate_y(avg_gait_data_pocket, prin_idx_pocket)
        opt_rotm_pocket = np.matmul(opt_rotm_z_pocket, opt_rotm_y_pocket)
        cur_pocket_gyro_cal = np.matmul(cur_pocket_gyro, opt_rotm_pocket)

        """Adjust rotation if necessary"""
        pos_idx = cur_pocket_gyro_cal[:, -1] > 0
        neg_idx = cur_pocket_gyro_cal[:, -1] < 0
        gyro_z_norm_pos = norm(cur_pocket_gyro_cal[pos_idx, -1], ord=2)
        gyro_z_norm_neg = norm(cur_pocket_gyro_cal[neg_idx, -1], ord=2)
        
        if gyro_z_norm_pos <= gyro_z_norm_neg:
            opt_rotm_pocket = np.matmul(opt_rotm_pocket, utils.rotm_y(np.pi))
            theta_y += 180
            if theta_y > 180:
                theta_y -= 360
            cur_pocket_gyro_cal = np.matmul(cur_pocket_gyro, opt_rotm_pocket)

        """Step 3: Gait segmentation and energy expenditure estimation"""
        gait_peaks = utils.peak_detect(cur_pocket_gyro_cal[:, -1])
        gait_data_pocket = utils.segment_data(gait_peaks, cur_pocket_gyro_cal, stride_detect_window)
        
        if len(gait_peaks) > 3 and len(gait_data_pocket) >= 1:  # Consider it a bout if more than 3 peaks are detected
            print(f"Sending {cur_pocket_gyro_cal.shape[0]} rows to estimateMetabolics for bout {idx + 1}.")
            ee_est = utils.estimateMetabolics(
                model_url, cur_pocket_gyro_cal, gait_peaks,
                weight, height, cur_basal, correction_url,
                stride_detect_window, 
            )
            ee_all.append(ee_est)

"""Flatten the collected list of energy expenditure data"""
ee_all = sum(ee_all, [])
print(ee_all)
