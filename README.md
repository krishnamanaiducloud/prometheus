# Prometheus hardened source build

Prometheus 3.16.0 rebuilt from the verified upstream tag and commit, then placed in a
shell-less Chainguard static runtime. The published image is
`mohankrishna999/prometheus:3.16.0-patched` (also `latest`) for linux/amd64 and linux/arm64.

The build preserves the upstream entrypoint, default configuration, port 9090, and
`/prometheus` storage path. It runs as numeric UID 65532 with primary GID 0 so the same
image works under Kubernetes and OpenShift restricted SCCs.

## Release 3.16.0-patched

| Component | Upstream v3.16.0 | `3.16.0-patched` |
|---|---|---|
| Go toolchain | 1.27 | 1.27.3 (Chainguard `go`) |
| `golang.org/x/crypto` | 0.58.0 | fix commit `v0.58.1-0.20261009181718-2f1f834330b2` (GO-2026-5932) |
| `github.com/klauspost/compress` | 1.20.3 | 1.20.3 (pinned; fixes GO-2026-6865) |
| `golang.org/x/net` | 0.61.0 | 0.62.0 |
| Web UI | embedded | embedded (upstream's release bundle, checksum-verified) |
| Runtime base | busybox | Chainguard `static` (digest-pinned, no shell) |

The source is cloned at tag `v3.16.0` and the build fails unless it resolves to upstream
commit `e2e28adeee2c5883d000fc82aca6008cfbf7e96d`. The web UI is upstream's prebuilt
`prometheus-web-ui-3.16.0.tar.gz`, checked against the release's `sha256sums.txt` and embedded
with upstream's `scripts/compress_assets.sh` and build tags (`netgo,builtinassets`), as in the
official binaries. `3.15.1-patched` was built without the UI assets, so its UI pages (`/query`,
`/targets`, ...) returned HTTP 500; the API and scraping were not affected. It stays published
unchanged.

## Verification

| Check | Result |
|---|---|
| `--version`, `/api/v1/status/buildinfo` | 3.16.0, revision `e2e28adeee2c` |
| `promtool check config` on the default config | passes |
| `/-/ready`, self-scrape (`up` = 1) | ready, 1 |
| UI `/query` and `/targets` at 1440px and 390px | HTTP 200, no page overflow, no script errors |
| User, entrypoint, command | identical to `3.15.1-patched` |
| Arbitrary UID with GID 0 (OpenShift) | starts and serves |
| Trivy 0.76.2 (all severities) | no vulnerabilities |
| Grype 0.121.1 | no vulnerabilities |

```sh
make smoke
make scan
make push
kubectl apply -k k8s/
oc apply -k k8s-openshift/
```

Both Trivy and Grype must report no known fixable vulnerabilities before publishing.
The scheduled GitHub workflow repeats the build and scan weekly because vulnerability
databases and base images change over time.
