FROM python:3.11-slim

WORKDIR /app

# Install system dependencies if required
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the backend source files and pre-seeded cache files
COPY backend/ ./backend/

# Expose internal port
EXPOSE 3001

# Run the Flask app
CMD ["python", "backend/app.py"]
