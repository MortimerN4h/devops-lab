FROM python:3.12-slim

# No .pyc files in the image; print logs immediately (no buffering) so `docker logs` is live.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Dependencies first: this layer is cached until requirements.txt changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# Run as a normal user, not root (if the app is hacked, the attacker is not root in the container).
RUN useradd --create-home --uid 10001 app
USER app

EXPOSE 8000
# uvicorn = the web server that runs the FastAPI app object "app" from main.py
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
