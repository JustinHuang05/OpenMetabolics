FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt
RUN pip install gunicorn

# Copy Python files
COPY process_energy_expenditure.py .
COPY process_energy_expenditure_worker.py .
COPY utils.py .

# Copy data files
COPY data_driven_ee_model.pkl .
COPY pocket_motion_correction_model.pkl .

# Add the current directory to Python path
ENV PYTHONPATH=/app

# Create a script to choose which service to run
COPY start.sh .
RUN chmod +x start.sh

# Use the start script as the entry point
CMD ["./start.sh"] 