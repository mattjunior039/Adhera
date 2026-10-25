FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# System dependencies required by OpenCV and OCR.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    build-essential \
    cmake \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./requirements.txt
RUN pip install --upgrade pip && pip install -r requirements.txt

COPY . ./backend_api

# Runtime directories for uploads and model weight caches.
RUN mkdir -p /app/backend_api/uploads /app/runs /app/.cache/torch

EXPOSE 8000

CMD ["uvicorn", "backend_api.main:app", "--host", "0.0.0.0", "--port", "8000"]
