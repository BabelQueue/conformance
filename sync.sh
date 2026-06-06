#!/usr/bin/env bash
# Vendor the canonical conformance suite into each sibling SDK's tests/conformance/.
# conformance/ is the single source of truth; run this after changing any fixture.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$here")"

# repo path : relative tests/conformance dir
targets=(
  "$root/php-sdk/tests/conformance"
  "$root/babelqueue-python/tests/conformance"
)

for dest in "${targets[@]}"; do
  sdk="$(dirname "$(dirname "$dest")")"
  if [ ! -d "$sdk" ]; then
    echo "skip (missing): $sdk"
    continue
  fi
  rm -rf "$dest"
  mkdir -p "$dest/fixtures" "$dest/schema"
  cp "$here/manifest.json" "$dest/manifest.json"
  cp "$here"/fixtures/*.json "$dest/fixtures/"
  cp "$here"/schema/*.json "$dest/schema/"
  echo "synced -> $dest"
done
