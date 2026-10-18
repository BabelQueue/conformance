#!/usr/bin/env bash
# Fetch a released conformance suite, verify its checksum, and unpack it (or compare it to a
# vendored copy). Needs only curl, tar and sha256sum (or `shasum -a 256`).
#
#   ./fetch.sh <version> <dest>               # download, verify, unpack into <dest>
#   ./fetch.sh --check <version> <vendor-dir> # exit 1 if <vendor-dir> differs from the release
#
# <version> is a SemVer such as 1.5.0 (a leading `v` is accepted). The release asset is
# babelqueue-conformance-<version>.tar.gz, verified against the release's SHA256SUMS before
# anything is unpacked. LICENSE ships in the asset but is not part of the vendored copy, so
# --check ignores it.
#
# Integrity, not authenticity: SHA256SUMS comes from the same release as the asset, so the
# checksum catches corruption and a half-replaced asset, not a release whose asset and
# SHA256SUMS were both replaced. A consumer who needs authenticity pins the expected hash
# (or the exact tag) on its own side.
#
# Environment:
#   BQ_CONFORMANCE_BASE_URL  Directory URL holding the asset and SHA256SUMS. Defaults to
#                            https://github.com/BabelQueue/conformance/releases/download/v<version>
#                            (any curl-supported scheme works, e.g. file:///path/to/dist for tests).
set -euo pipefail

usage() {
  echo "usage: $0 <version> <dest>" >&2
  echo "       $0 --check <version> <vendor-dir>" >&2
  exit 2
}

mode="fetch"
if [ "${1:-}" = "--check" ]; then
  mode="check"
  shift
fi
[ "$#" -eq 2 ] || usage

version="${1#v}"
target="$2"

if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'; then
  echo "fetch.sh: '$1' is not a SemVer version" >&2
  exit 2
fi

asset="babelqueue-conformance-${version}.tar.gz"
root_dir="babelqueue-conformance-${version}"
base_url="${BQ_CONFORMANCE_BASE_URL:-https://github.com/BabelQueue/conformance/releases/download/v${version}}"
base_url="${base_url%/}"

if command -v sha256sum >/dev/null 2>&1; then
  sha_check() { sha256sum -c -; }
elif command -v shasum >/dev/null 2>&1; then
  sha_check() { shasum -a 256 -c -; }
else
  echo "fetch.sh: neither sha256sum nor shasum is available" >&2
  exit 2
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/bq-conformance.XXXXXX")"
trap 'rm -rf "$work"' EXIT

curl --fail --silent --show-error --location --output "$work/$asset" "$base_url/$asset"
curl --fail --silent --show-error --location --output "$work/SHA256SUMS" "$base_url/SHA256SUMS"

# Verify the asset against the line that names it (SHA256SUMS may list other files).
expected="$(awk -v name="$asset" '{ f = $2; sub(/^\*/, "", f); if (f == name) print $1 "  " name }' "$work/SHA256SUMS")"
if [ -z "$expected" ]; then
  echo "fetch.sh: SHA256SUMS has no entry for $asset" >&2
  exit 1
fi
(cd "$work" && printf '%s\n' "$expected" | sha_check >/dev/null) \
  || { echo "fetch.sh: checksum mismatch for $asset" >&2; exit 1; }

# Refuse anything that is not a single, well-behaved tree under one root directory before
# unpacking: every entry sits under <root_dir>/ (a fixed-string match, so the dots of the
# version are literal), no entry climbs out with `..`, and nothing is a link or a device.
tar -tzf "$work/$asset" > "$work/entries"
tar -tvzf "$work/$asset" > "$work/entries.long"
if [ -n "$(awk -v root="$root_dir" 'index($0, root "/") != 1 && $0 != root' "$work/entries")" ]; then
  echo "fetch.sh: $asset has entries outside $root_dir/" >&2
  exit 1
fi
if grep -Eq '(^|/)\.\.(/|$)' "$work/entries"; then
  echo "fetch.sh: $asset contains a parent-directory path" >&2
  exit 1
fi
if [ -n "$(cut -c1 "$work/entries.long" | grep -Ev '^[-d]$' || true)" ]; then
  echo "fetch.sh: $asset contains a link or special file" >&2
  exit 1
fi

mkdir "$work/extract"
tar -xzf "$work/$asset" -C "$work/extract"
src="$work/extract/$root_dir"

if [ "$(tr -d '[:space:]' < "$src/CONFORMANCE_VERSION")" != "$version" ]; then
  echo "fetch.sh: CONFORMANCE_VERSION inside $asset does not match $version" >&2
  exit 1
fi

if [ "$mode" = "check" ]; then
  if [ ! -d "$target" ]; then
    echo "fetch.sh: vendor dir not found: $target" >&2
    exit 1
  fi
  if diff -r -x LICENSE "$src" "$target"; then
    echo "in sync: $target (conformance $version)"
    exit 0
  fi
  echo "DRIFT:   $target differs from conformance $version" >&2
  exit 1
fi

if [ -e "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
  echo "fetch.sh: destination is not empty: $target" >&2
  exit 1
fi
mkdir -p "$target"
cp -R "$src"/. "$target"/
echo "fetched conformance $version into $target"
