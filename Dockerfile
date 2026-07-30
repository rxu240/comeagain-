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

# Install npm deps. Not pre-building the client bundle here: `jac start
# --client pwa` always rebuilds from scratch at runtime regardless (and
# rebuilds it *twice* - PWATarget.start() builds, then delegates to
# WebTarget.start() which builds again - a jac_client 0.3.25 quirk), so a
# build-time bundle would just be thrown away. Pre-building here would only
# double memory pressure during the image build for no benefit.
#
# NOTE: target "web" (instead of "pwa") is NOT a lighter-weight alternative
# here - jac_client's own CLI treats "web" as a no-op and falls through to
# core jaclang's bare server, which doesn't know about this project's
# Tailwind/shadcn Vite plugin config and fails to build entirely. Stay on
# "pwa"; the real fix for the double build's memory pressure is giving the
# service enough RAM (see Railway service Settings -> Scale/Resources).
RUN jac install

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
