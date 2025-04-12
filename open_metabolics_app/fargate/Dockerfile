FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt
RUN pip install gunicorn

COPY process_energy_expenditure.py .

CMD ["gunicorn", "--bind", "0.0.0.0:80", "process_energy_expenditure:app"] 