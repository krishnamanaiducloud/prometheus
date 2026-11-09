#!/bin/sh
set -eu

downloaded=
for attempt in 1 2 3 4 5; do
  if go get golang.org/x/net@v0.62.0 golang.org/x/crypto@v0.58.1-0.20261009181718-2f1f834330b2 \
      github.com/klauspost/compress@v1.20.3; then
    downloaded=1
    break
  fi
  echo "Go module download failed (attempt ${attempt}), retrying" >&2
  sleep 5
done
test -n "${downloaded}"
go mod tidy

test "$(go list -m -f '{{.Version}}' golang.org/x/net)" = v0.62.0
test "$(go list -m -f '{{.Version}}' golang.org/x/crypto)" = v0.58.1-0.20261009181718-2f1f834330b2
test "$(go list -m -f '{{.Version}}' github.com/klauspost/compress)" = v1.20.3

# GO-2026-5932 concerns x/crypto/openpgp, which the pinned x/crypto commit fixes. Fail the build
# if either shipped binary ever starts importing that package.
! go list -deps ./cmd/prometheus ./cmd/promtool | grep -q '^golang.org/x/crypto/openpgp\($\|/\)'
