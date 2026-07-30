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

# `jac start main.jac --client pwa` rebuilds the client bundle from scratch
# *twice* on every container start - PWATarget.start() builds, then
# delegates to WebTarget.start() which builds again (WebTarget.build()
# always rmtrees and rebuilds dist/, force=True, no staleness check). On a
# memory-constrained container that doubles peak Vite/Bun memory for no
# reason, since nothing changed between the two builds. jac_client has no
# flag to avoid this, so we patch the installed package: WebTarget.build()
# will reuse an already-built dist/ when JAC_REUSE_PREBUILT_CLIENT=1 (opt-in,
# so this doesn't change behavior for local dev or any other environment).
#
# NOTE: target "web" (instead of "pwa") is NOT a lighter-weight alternative -
# jac_client's own CLI treats "web" as a no-op and falls through to core
# jaclang's bare server, which doesn't know about this project's
# Tailwind/shadcn Vite plugin config and fails to build entirely. Must stay
# on "pwa".
COPY scripts/patch_jac_client_prebuild.py ./scripts/patch_jac_client_prebuild.py
RUN python scripts/patch_jac_client_prebuild.py

COPY . .

# Install npm deps and build the client bundle once, here, where the builder
# typically has more CPU/RAM headroom than the running container does. The
# patch above makes the runtime `jac start --client pwa` reuse this instead
# of rebuilding it.
ENV JAC_REUSE_PREBUILT_CLIENT=1
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
