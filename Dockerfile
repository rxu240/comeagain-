# TONECRAFT — one container, server and client both compiled from Jac.
#
# Runs anywhere that runs a process: Render, Railway, Fly.io, Cloud Run.
#   docker build -t tonecraft .
#   docker run -p 8000:8000 tonecraft
FROM python:3.12-slim

# curl + unzip: `jac install` fetches Bun to build the client bundle.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Install npm deps and compile the client (cl) Jac to a PWA bundle.
RUN jac install && jac build --client pwa

# The graph database (SQLite, WAL mode) lives here. This path must be a
# mounted volume in production - see docker-compose.yml - or takes vanish on
# every restart/redeploy.
ENV JAC_DATA_PATH=/data/jac-data
ENV PYTHONIOENCODING=utf-8
ENV PORT=8000
# Where to reach transcribe_service (see docker-compose.yml for the default
# service-discovery name); transcription itself no longer runs in this process.
ENV TRANSCRIBE_SERVICE_URL=http://transcribe:8001
EXPOSE 8000

CMD ["sh", "-c", "jac start main.jac --host 0.0.0.0 --port ${PORT} --client pwa"]
