#!/bin/bash

if [ "$SERVICE_TYPE" = "worker" ]; then
    echo "Starting worker service..."
    python process_energy_expenditure_worker.py
else
    echo "Starting API service..."
    gunicorn --bind 0.0.0.0:80 process_energy_expenditure:app
fi 