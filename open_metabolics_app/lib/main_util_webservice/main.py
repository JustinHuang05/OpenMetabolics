"""
Copyright (c) 2024 Harvard Ability Lab
Title: "A smartphone activity monitor that accurately estimates energy expenditure"
"""

import os
import numpy as np
import pandas as pd
import pickle
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

"""Load energy expenditure estimation and pocket motion correction models"""
data_driven_model = pickle.load(open('./model_weight/data_driven_ee_model.pkl', 'rb'))
pocket_motion_correction_model = pickle.load(open('./model_weight/pocket_motion_correction_model.pkl', 'rb'))

"""Load smartphone data (assumed to be one active bout)"""
csv_path = './example_data/data_segment.csv'
df_sp = pd.read_csv(csv_path).values

"""Constants for low-pass filter"""
sampling_freq = 50  # Sampling frequency in Hz
crossover_freq = 6  # Crossover frequency for low-pass filter in Hz
filt_order = 4  # Filter order

"""Low-pass filter parameters"""
b, a = signal.butter(filt_order, crossover_freq, btype='low', fs=sampling_freq)

"""Filter the collected smartphone data"""
time_sp = df_sp[:, 0]
gyro_sp = signal.filtfilt(b, a, df_sp[:, 1:4], axis=0)  # Filter gyro data
acc_sp = signal.filtfilt(b, a, df_sp[:, 4:], axis=0)  # Filter accelerometer data

"""Step 1: Orientation alignment: Align with the superior-inferior axis of the thigh"""
opt_rotm_z_pocket, theta_z = utils.get_rotate_z(acc_sp)
cur_pocket_gyro_rot_zx = np.matmul(gyro_sp, opt_rotm_z_pocket)

"""Find principal axis of angular velocity"""
prin_idx_pocket = utils.find_prin_axis(cur_pocket_gyro_rot_zx)
prin_gyro_pocket = cur_pocket_gyro_rot_zx[:, prin_idx_pocket]

if np.abs(np.max(prin_gyro_pocket)) < np.abs(np.min(prin_gyro_pocket)):
    prin_gyro_pocket = -prin_gyro_pocket

"""Detect peaks in the principal angular velocity (step detection)"""
gait_peaks = utils.peak_detect(prin_gyro_pocket)

"""Step 2: Orientation alignment: Align with the mediolateral axis of the thigh"""
if len(gait_peaks) > 3:  # Ensure there are enough peaks to detect steps
    gait_data_pocket = utils.segment_data(gait_peaks, cur_pocket_gyro_rot_zx, stride_detect_window=2*sampling_freq)
    
    if len(gait_data_pocket) >= 1:
        avg_gait_data_pocket = np.mean(gait_data_pocket, axis=0)
        opt_rotm_y_pocket, theta_y = utils.get_rotate_y(avg_gait_data_pocket, prin_idx_pocket)
        opt_rotm_pocket = np.matmul(opt_rotm_z_pocket, opt_rotm_y_pocket)
        cur_pocket_gyro_cal = np.matmul(gyro_sp, opt_rotm_pocket)

        """Step 3: Compute EE for each step within the bout"""
        ee_all = []
        for step_idx in range(len(gait_peaks) - 1):
            gait_start_index = gait_peaks[step_idx]
            gait_stop_index = gait_peaks[step_idx + 1]

            if 35 < (gait_stop_index - gait_start_index) <= 2 * sampling_freq:  # Ensure valid step duration
                ee_est = utils.estimateMetabolics(
                    data_driven_model, cur_pocket_gyro_cal, [gait_start_index, gait_stop_index],
                    weight, height, cur_basal,
                    stride_detect_window=2*sampling_freq,
                    correction_model=pocket_motion_correction_model
                )
                ee_all.append(ee_est)

        """Flatten EE data"""
        ee_all = sum(ee_all, [])
        print(f"Energy expenditure per step: {ee_all}")
else:
    print("Not enough peaks detected for step-wise EE estimation.")
