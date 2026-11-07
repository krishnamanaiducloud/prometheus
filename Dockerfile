# syntax=docker/dockerfile:1.7
ARG GO_IMAGE=cgr.dev/chainguard/go:latest-dev@sha256:ed70318f7b4f2e4a82e1dbc363f7a13be3a5805081f86ed9d1ec02d2694c222f
ARG RUNTIME_IMAGE=cgr.dev/chainguard/static:latest@sha256:fc42af33e643f20d08baf03cddcc1c02ba57052dfb02edb0d79f3fc47bcea8d9

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS source
ARG PROMETHEUS_VERSION=3.16.0
ARG PROMETHEUS_COMMIT=e2e28adeee2c5883d000fc82aca6008cfbf7e96d

USER root
WORKDIR /src
RUN git -c advice.detachedHead=false clone --quiet --depth 1 --branch "v${PROMETHEUS_VERSION}" \
      https://github.com/prometheus/prometheus.git . \
    && test "$(git rev-parse HEAD)" = "${PROMETHEUS_COMMIT}"

FROM source AS build
ARG TARGETOS
ARG TARGETARCH
ARG PROMETHEUS_VERSION=3.16.0
ARG PROMETHEUS_COMMIT=e2e28adeee2c5883d000fc82aca6008cfbf7e96d
ENV CGO_ENABLED=0 GOTOOLCHAIN=local
COPY build/patch-modules.sh /usr/local/bin/patch-modules.sh
RUN --mount=type=cache,id=prometheus-go-mod,target=/root/go/pkg/mod,sharing=locked \
    sh /usr/local/bin/patch-modules.sh
# The web UI is upstream's prebuilt release bundle, checked against the release's sha256sums.txt
# and embedded with upstream's own script and build tags (netgo,builtinassets), as in the
# official binaries. Without it the UI pages return HTTP 500.
ARG PROMETHEUS_UI_SHA256=000a45231f6dd22a5703218aad3ee11da125c8a44d1824a27670416c07531001
RUN apk add --no-cache bash curl gzip findutils coreutils \
    && mkdir -p /tmp/ui && cd /tmp/ui \
    && curl -fsSL --retry 5 -o ui.tar.gz \
      "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-web-ui-${PROMETHEUS_VERSION}.tar.gz" \
    && echo "${PROMETHEUS_UI_SHA256}  ui.tar.gz" | sha256sum -c - \
    && tar xzf ui.tar.gz \
    && cd /src && PREBUILT_ASSETS_STATIC_DIR=/tmp/ui/static bash scripts/compress_assets.sh \
    && test -n "$(find web/ui/static -name 'index.html.gz')"
RUN --mount=type=cache,id=prometheus-go-mod,target=/root/go/pkg/mod,sharing=locked \
    --mount=type=cache,id=prometheus-go-build,target=/root/.cache/go-build,sharing=locked \
    GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" go build -trimpath -buildvcs=false -tags netgo,builtinassets \
      -ldflags "-s -w -buildid= -X github.com/prometheus/common/version.Version=${PROMETHEUS_VERSION} -X github.com/prometheus/common/version.Revision=${PROMETHEUS_COMMIT}" \
      -o /out/prometheus ./cmd/prometheus \
    && GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" go build -trimpath -buildvcs=false -tags netgo,builtinassets \
      -ldflags "-s -w -buildid= -X github.com/prometheus/common/version.Version=${PROMETHEUS_VERSION} -X github.com/prometheus/common/version.Revision=${PROMETHEUS_COMMIT}" \
      -o /out/promtool ./cmd/promtool \
    && mkdir -p /out/etc/prometheus \
    && cp /src/documentation/examples/prometheus.yml /out/etc/prometheus/prometheus.yml \
    && chmod 0555 /out/etc/prometheus \
    && chmod 0444 /out/etc/prometheus/prometheus.yml \
    && mkdir -p /out/data \
    && chown 65532:0 /out/data \
    && chmod 0770 /out/data

FROM ${RUNTIME_IMAGE}
ARG PROMETHEUS_VERSION=3.16.0
LABEL org.opencontainers.image.title="Prometheus" \
      org.opencontainers.image.version="${PROMETHEUS_VERSION}-patched" \
      org.opencontainers.image.source="https://github.com/prometheus/prometheus" \
      org.opencontainers.image.licenses="Apache-2.0"
COPY --from=build --chown=65532:0 --chmod=0555 /out/prometheus /bin/prometheus
COPY --from=build --chown=65532:0 --chmod=0555 /out/promtool /bin/promtool
COPY --from=build --chown=65532:0 /out/etc/prometheus /etc/prometheus
COPY --from=build --chown=65532:0 --chmod=0770 /out/data /prometheus
WORKDIR /prometheus
USER 65532:0
EXPOSE 9090
ENTRYPOINT ["/bin/prometheus"]
CMD ["--config.file=/etc/prometheus/prometheus.yml", "--storage.tsdb.path=/prometheus"]
