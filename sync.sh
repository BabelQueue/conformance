#!/usr/bin/env bash
# Vendor the canonical conformance suite into each sibling SDK, or verify that the
# vendored copies are in sync. conformance/ is the single source of truth.
#
#   ./sync.sh            # copy the canonical suite into each SDK (run after edits)
#   ./sync.sh --check    # diff vendored copies vs canonical; exit 1 on any drift
#
# --check is the local counterpart to each SDK's CI drift guard (which fetches the
# canonical repo and diffs its own vendored copy).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$here")"

mode="sync"
if [ "${1:-}" = "--check" ]; then
  mode="check"
fi

# Per-SDK vendored copy. Go uses testdata/ (the toolchain ignores it in builds),
# Java uses src/test/resources/, the rest use tests/conformance/ — the existence
# check derives the SDK root from each dest, so any nesting depth works.
targets=(
  "$root/php-sdk/tests/conformance"
  "$root/babelqueue-python/tests/conformance"
  "$root/babelqueue-go/testdata/conformance"
  "$root/babelqueue-node/test/conformance"
  "$root/babelqueue-java/src/test/resources/conformance"
  "$root/babelqueue-dotnet/tests/BabelQueue.Core.Tests/conformance"
  "$root/babelqueue-node-adapters/packages/sqs/test/conformance"
  "$root/babelqueue-java-sqs/src/test/resources/conformance"
  "$root/babelqueue-dotnet-sqs/tests/BabelQueue.Sqs.Tests/conformance"
  "$root/babelqueue-node-adapters/packages/azure-service-bus/test/conformance"
  "$root/babelqueue-java-azureservicebus/src/test/resources/conformance"
  "$root/babelqueue-dotnet-azureservicebus/tests/BabelQueue.AzureServiceBus.Tests/conformance"
  "$root/babelqueue-node-adapters/packages/pulsar/test/conformance"
  "$root/babelqueue-java-pulsar/src/test/resources/conformance"
  "$root/babelqueue-dotnet-pulsar/tests/BabelQueue.Pulsar.Tests/conformance"
)

drifted=0

for dest in "${targets[@]}"; do
  sdk="$(dirname "$(dirname "$dest")")"
  if [ ! -d "$sdk" ]; then
    echo "skip (missing): $sdk"
    continue
  fi

  if [ "$mode" = "check" ]; then
    if diff -q "$here/manifest.json" "$dest/manifest.json" >/dev/null 2>&1 \
      && diff -qr "$here/fixtures" "$dest/fixtures" >/dev/null 2>&1 \
      && diff -qr "$here/schema" "$dest/schema" >/dev/null 2>&1; then
      echo "in sync: $dest"
    else
      echo "DRIFT:   $dest"
      drifted=1
    fi
  else
    rm -rf "$dest"
    mkdir -p "$dest/fixtures" "$dest/schema"
    cp "$here/manifest.json" "$dest/manifest.json"
    cp "$here"/fixtures/*.json "$dest/fixtures/"
    cp "$here"/schema/*.json "$dest/schema/"
    echo "synced -> $dest"
  fi
done

if [ "$mode" = "check" ] && [ "$drifted" = 1 ]; then
  echo "Vendored conformance copies drifted from the canonical suite. Run ./sync.sh." >&2
  exit 1
fi
