# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1: build AirSane (SANE -> eSCL/AirScan bridge) from source
# ---------------------------------------------------------------------------
FROM debian:trixie-slim AS build

# Pinned AirSane commit, for reproducible builds. Override with --build-arg.
ARG AIRSANE_REPO=https://github.com/SimulPiscator/AirSane.git
ARG AIRSANE_REF=e96627ae7a85e700fbb353b23deacfba868869ad

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates git cmake make g++ \
      libsane-dev libjpeg-dev libpng-dev libavahi-client-dev libusb-1.0-0-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git init -q AirSane \
 && cd AirSane \
 && git remote add origin "${AIRSANE_REPO}" \
 && git fetch -q --depth 1 origin "${AIRSANE_REF}" \
 && git checkout -q FETCH_HEAD \
 && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
 && cmake --build build -j"$(nproc)" \
 && strip build/airsaned

# ---------------------------------------------------------------------------
# Stage 2: runtime
# ---------------------------------------------------------------------------
FROM debian:trixie-slim

LABEL org.opencontainers.image.title="samsung-m2070fw-bridge-docker" \
      org.opencontainers.image.description="Expose the Samsung Xpress M2070FW scanner to macOS/Windows/Linux as an AirScan (eSCL) scanner via SANE + AirSane" \
      org.opencontainers.image.source="https://github.com/ivansollazzo/samsung-m2070fw-bridge-docker"

# sane-utils: scanimage + libsane1 with the xerox_mfp backend
# avahi-daemon + dbus: mDNS/Bonjour announcement (used when the host has no avahi)
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      sane-utils libsane1 \
      libjpeg62-turbo libpng16-16t64 libavahi-client3 libusb-1.0-0 \
      avahi-daemon dbus tini \
 && rm -rf /var/lib/apt/lists/*

# avahi's rlimit-nproc breaks inside containers (shared UID namespace);
# also don't advertise the host as a "workstation" from the container.
RUN sed -i 's/^rlimit-nproc=/#rlimit-nproc=/' /etc/avahi/avahi-daemon.conf \
 && sed -i 's/^#\?publish-workstation=.*/publish-workstation=no/' /etc/avahi/avahi-daemon.conf

COPY --from=build /src/AirSane/build/airsaned /usr/local/bin/airsaned
COPY --from=build /src/AirSane/etc/Gnome-scanner.png /etc/airsane/Gnome-scanner.png
COPY config/access.conf config/ignore.conf /etc/airsane/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV SCANNER_IP="" \
    SCANNER_PORT=9400 \
    SCANNER_LOCATION="" \
    LISTEN_PORT=8090 \
    AVAHI_MODE=auto \
    WEB_INTERFACE=true \
    DEBUG=false \
    RESCAN_INTERVAL=60 \
    SANE_JPEG=no

EXPOSE 8090

HEALTHCHECK --interval=60s --timeout=5s --start-period=30s --retries=3 \
  CMD bash -c "exec 3<>/dev/tcp/127.0.0.1/${LISTEN_PORT}" || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
