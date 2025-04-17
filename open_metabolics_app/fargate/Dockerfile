FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt
RUN pip install gunicorn

# Copy Python files
COPY process_energy_expenditure.py .
COPY utils.py .
COPY main.py .

# Copy data files
COPY subject_info.csv .
COPY data_driven_ee_model.pkl .
COPY pocket_motion_correction_model.pkl .
COPY daily_sp_pocket_data.csv .

# Add the current directory to Python path
ENV PYTHONPATH=/app

CMD ["gunicorn", "--bind", "0.0.0.0:80", "process_energy_expenditure:app"] 