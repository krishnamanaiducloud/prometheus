# syntax=docker/dockerfile:1.7
ARG GO_IMAGE=cgr.dev/chainguard/go:latest-dev@sha256:c33b2ae1b183ff001b7f2c29936c587ce1cd4ffaf9efb031bd81240f16a96504
ARG RUNTIME_IMAGE=cgr.dev/chainguard/static:latest@sha256:fc42af33e643f20d08baf03cddcc1c02ba57052dfb02edb0d79f3fc47bcea8d9

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS source
ARG PROMETHEUS_VERSION=3.15.1
ARG PROMETHEUS_COMMIT=bae3eced0a5369e050e83ea73bc381d7c4b1a719

USER root
WORKDIR /src
RUN git -c advice.detachedHead=false clone --quiet --depth 1 --branch "v${PROMETHEUS_VERSION}" \
      https://github.com/prometheus/prometheus.git . \
    && test "$(git rev-parse HEAD)" = "${PROMETHEUS_COMMIT}"

FROM source AS build
ARG TARGETOS
ARG TARGETARCH
ARG PROMETHEUS_VERSION=3.15.1
ARG PROMETHEUS_COMMIT=bae3eced0a5369e050e83ea73bc381d7c4b1a719
ENV CGO_ENABLED=0 GOTOOLCHAIN=local
COPY build/patch-modules.sh /usr/local/bin/patch-modules.sh
RUN --mount=type=cache,id=prometheus-go-mod,target=/root/go/pkg/mod,sharing=locked \
    sh /usr/local/bin/patch-modules.sh
RUN --mount=type=cache,id=prometheus-go-mod,target=/root/go/pkg/mod,sharing=locked \
    --mount=type=cache,id=prometheus-go-build,target=/root/.cache/go-build,sharing=locked \
    GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" go build -trimpath -buildvcs=false \
      -ldflags "-s -w -buildid= -X github.com/prometheus/common/version.Version=${PROMETHEUS_VERSION} -X github.com/prometheus/common/version.Revision=${PROMETHEUS_COMMIT}" \
      -o /out/prometheus ./cmd/prometheus \
    && GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" go build -trimpath -buildvcs=false \
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
ARG PROMETHEUS_VERSION=3.15.1
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
