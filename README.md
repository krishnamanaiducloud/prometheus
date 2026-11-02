# Prometheus hardened source build

Prometheus 3.15.1 rebuilt from the verified upstream tag and commit, then placed in a
shell-less Chainguard static runtime. The published image is
`mohankrishna999/prometheus:3.15.1-patched` for linux/amd64 and linux/arm64.

The build preserves the upstream entrypoint, default configuration, port 9090, and
`/prometheus` storage path. It runs as numeric UID 65532 with primary GID 0 so the same
image works under Kubernetes and OpenShift restricted SCCs.

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
