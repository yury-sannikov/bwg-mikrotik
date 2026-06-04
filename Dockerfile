# Build image with GO
FROM --platform=linux/amd64 golang:alpine AS build-linux-amd64
FROM --platform=linux/arm/v7 golang:alpine AS build-linux-armv7
FROM --platform=linux/arm64 golang:alpine AS build-linux-arm64
FROM --platform=linux/arm/v5 debian:trixie-slim AS build-linux-armv5

FROM build-${TARGETOS}-${TARGETARCH}${TARGETVARIANT} AS build

ARG TARGETPLATFORM
ARG TARGETARCH
ARG TARGETOS
ARG TARGETVARIANT
WORKDIR /go

RUN echo "Building for platform: $TARGETARCH" && \
    case "$TARGETPLATFORM" in \
        "linux/arm/v5") \
            apt update && apt install -y git make bash wget gcc golang ;; \
        linux/amd64 | linux/arm64 | linux/arm/v7) \
            apk add --no-cache git make bash build-base linux-headers ;; \
        *) echo "Unsupported platform: $TARGETPLATFORM" && exit 1 ;; \
    esac
    
COPY _build_sources/amneziawg-tools /go/amneziawg-tools
COPY _build_sources/amneziawg-go /go/amneziawg-go

RUN cd /go/amneziawg-tools/src && make
RUN cd /go/amneziawg-go && make
# make work structure
RUN mkdir -p /tmp/build/usr/bin/ \
    && mv /go/amneziawg-go/amneziabwg-go /tmp/build/usr/bin/amneziabwg-go \
    && mv /go/amneziawg-tools/src/wg /tmp/build/usr/bin/bwg \
    && mv /go/amneziawg-tools/src/wg-quick/linux.bash /tmp/build/usr/bin/bwg-quick
COPY wireguard-fs /tmp/build/

# Base image for different architecture
FROM --platform=linux/amd64 alpine:latest AS linux-amd64
FROM --platform=linux/arm/v7 alpine:latest AS linux-armv7
FROM --platform=linux/arm64 alpine:latest AS linux-arm64
FROM --platform=linux/arm/v5 debian:trixie-slim AS linux-armv5

# FINAL IMAGE
FROM ${TARGETOS}-${TARGETARCH}${TARGETVARIANT}
ARG TARGETPLATFORM
ARG TARGETARCH
ARG TARGETOS
ARG TARGETVARIANT
ENV GOMEMLIMIT=200MiB \
    GOGC=50 \
    MON_ENABLED=1 \
    MON_WG_INTERFACE= \
    MON_WG_PEER_PREFIX= \
    MON_HA_URL= \
    MON_HA_TOKEN= \
    MON_BASE_NAME= \
    MON_CURL_TIMEOUT=5 \
    MON_VERBOSE=0

RUN case "$TARGETPLATFORM" in \
        "linux/arm/v5") \
            apt update && \
            apt install -y bash openrc iptables openresolv iproute2 init procps iputils-ping traceroute cron curl jq && \
            apt autoremove -y && \
            apt clean -y && \
            rm -rf /var/cache/apt/archives /var/lib/apt/lists/* ;; \
        linux/amd64 | linux/arm64 | linux/arm/v7) \
            apk add --no-cache bash openrc iptables iptables-legacy openresolv iproute2 cronie curl jq ;; \
        *) echo "Unsupported platform: $TARGETPLATFORM" && exit 1 ;; \
    esac

COPY --from=build /tmp/build/ /

RUN sed -i 's/^\(tty\d\:\:\)/#\1/' /etc/inittab && \
  sed -i \
  -e 's/^#\?rc_env_allow=.*/rc_env_allow="\*"/' \
  -e 's/^#\?rc_sys=.*/rc_sys="docker"/' \
  /etc/rc.conf && \
  ### alpine
  if [ -f /usr/libexec/rc/sh/init.sh ]; then \
      sed -i -e 's/VSERVER/DOCKER/' -e 's/checkpath -d "$RC_SVCDIR"/mkdir "$RC_SVCDIR"/' /usr/libexec/rc/sh/init.sh; \
  fi && \
  ### debian
  if [ -f /lib/rc/sh/init.sh ]; then \
      sed -i -e 's/VSERVER/DOCKER/' -e 's/checkpath -d "$RC_SVCDIR"/mkdir "$RC_SVCDIR"/' /lib/rc/sh/init.sh; \
      sed -i '/^depend()/,/^}/d' /etc/init.d/bwg-quick; \
  fi && \
  ###
  rm -f \
  /etc/init.d/hwdrivers \
  /etc/init.d/machine-id && \
  # IPv4
  rm /usr/sbin/iptables /usr/sbin/iptables-save /usr/sbin/iptables-restore && \
  ln -s /usr/sbin/iptables-legacy /usr/sbin/iptables && \
  ln -s /usr/sbin/iptables-legacy-save /usr/sbin/iptables-save && \
  ln -s /usr/sbin/iptables-legacy-restore /usr/sbin/iptables-restore && \
  # IPv6
  rm /usr/sbin/ip6tables /usr/sbin/ip6tables-save /usr/sbin/ip6tables-restore && \
  ln -s /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables && \
  ln -s /usr/sbin/ip6tables-legacy-save /usr/sbin/ip6tables-save && \
  ln -s /usr/sbin/ip6tables-legacy-restore /usr/sbin/ip6tables-restore && \
  #
  mkdir -p /etc/amnezia/amneziabwg/ && \
  #
  chmod +x /etc/init.d/bwg-quick && \
  chmod 0644 /etc/crontabs/root /etc/cron.d/wg-peer-monitor && \
  chmod +x /data/pre_up.sh && \
  chmod +x /data/wg-peer-monitor.sh && \
  #
  rc-update add bwg-quick default && \
  if [ -f /etc/init.d/crond ]; then rc-update add crond default; fi && \
  if [ -f /etc/init.d/cron ]; then rc-update add cron default; fi

VOLUME ["/sys/fs/cgroup"]
# TODO: test and re-enable healthcheck
#HEALTHCHECK --interval=5m --timeout=30s CMD /bin/bash /data/healthcheck.sh
CMD ["/sbin/init"]

