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

# Serverless and container filesystems are read-only outside /tmp; the graph
# database lives there. Set this to a mounted volume to keep takes across
# restarts.
ENV JAC_DATA_PATH=/tmp/jac-data
ENV PYTHONIOENCODING=utf-8
ENV PORT=8000
EXPOSE 8000

CMD ["sh", "-c", "jac start main.jac --host 0.0.0.0 --port ${PORT} --client pwa"]
