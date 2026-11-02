#!/bin/sh
set -eu

go get golang.org/x/net@v0.62.0 golang.org/x/crypto@v0.58.0
go mod tidy

test "$(go list -m -f '{{.Version}}' golang.org/x/net)" = v0.62.0
test "$(go list -m -f '{{.Version}}' golang.org/x/crypto)" = v0.58.0

# GO-2026-5932 applies only to x/crypto/openpgp. Trivy identifies the whole module;
# fail the build if either shipped binary ever starts importing that package.
! go list -deps ./cmd/prometheus ./cmd/promtool | grep -q '^golang.org/x/crypto/openpgp\($\|/\)'
