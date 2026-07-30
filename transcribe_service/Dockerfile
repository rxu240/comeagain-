# Standalone transcription service — isolates the CPU-bound Whisper call
# from the main app's request thread pool. Plain Python/FastAPI, no jaclang.
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Bake the recogniser weights into the image, same as the main app used to —
# without this the first request after a cold start blocks on a ~75 MB
# download from Hugging Face, and fails outright on a host with no egress.
ENV HF_HOME=/opt/models
RUN python -c "from faster_whisper import WhisperModel; \
    WhisperModel('base.en', device='cpu', compute_type='int8')"

COPY main.py ./

ENV PORT=8001
# Each worker process holds its own warm model; leave this modest so worker
# count x threads-per-worker doesn't oversubscribe the host's cores.
ENV TRANSCRIBE_WORKERS=2
ENV OMP_NUM_THREADS=2
EXPOSE 8001

CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
