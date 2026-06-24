#!/usr/bin/env bash
set -euo pipefail

version="${RAVEN_VERSION:-latest}"
release_repository="${RAVEN_RELEASE_REPOSITORY:-jbearak/raven}"

fail() {
  echo "::error::$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required to install Raven"
}

if [ "$version" != "latest" ] && ! [[ "$version" =~ ^v[0-9]+(\.[0-9]+){0,2}([-+][A-Za-z0-9._-]+)?$ ]]; then
  fail "version must be 'latest' or a Raven release tag (e.g. v0.11.1)"
fi

runner_os="${RUNNER_OS:-$(uname -s)}"
case "$runner_os" in
  Linux | linux* | GNU/Linux)
    os="linux"
    ;;
  macOS | Darwin | darwin*)
    os="macos"
    ;;
  Windows | Windows_NT | windows* | MINGW* | MSYS* | CYGWIN*)
    os="windows"
    ;;
  *)
    fail "unsupported runner OS: ${runner_os}. setup-raven supports Linux, macOS, and Windows runners."
    ;;
esac

runner_arch="${RUNNER_ARCH:-$(uname -m)}"
case "$runner_arch" in
  X64 | x86_64 | amd64)
    arch="x64"
    ;;
  ARM64 | arm64 | aarch64)
    arch="arm64"
    ;;
  *)
    fail "unsupported runner architecture: ${runner_arch}. setup-raven supports x64 and arm64 runners."
    ;;
esac

# Windows release archives ship raven.exe; Linux/macOS ship raven.
bin_name="raven"
if [ "$os" = "windows" ]; then
  bin_name="raven.exe"
fi

asset="raven-${os}-${arch}.zip"
if [ "$version" = "latest" ]; then
  release_base="https://github.com/${release_repository}/releases/latest/download"
else
  release_base="https://github.com/${release_repository}/releases/download/${version}"
fi

runner_temp="${RUNNER_TEMP:-/tmp}"
# On Windows RUNNER_TEMP uses backslashes (e.g. D:\a\_temp). Git Bash handles
# forward-slash drive paths fine, and a backslash in a filename makes GNU
# sha256sum escape its output line with a leading backslash — which would
# corrupt the parsed checksum. Normalize to forward slashes to avoid both.
runner_temp="${runner_temp//\\//}"
# mktemp -d gives a collision-free working dir (safer than $RANDOM on shared or
# self-hosted runners). No cleanup trap: bin_dir lives under workdir and is put
# on GITHUB_PATH for later job steps, so it must outlive this script. The runner
# is ephemeral and reclaims RUNNER_TEMP itself.
workdir="$(mktemp -d "${runner_temp}/setup-raven-${os}-${arch}.XXXXXX")"
extract_dir="${workdir}/extract"
bin_dir="${workdir}/bin"
archive="${workdir}/${asset}"
checksum_file="${workdir}/${asset}.sha256"

mkdir -p "$extract_dir" "$bin_dir"

require_command curl

echo "Downloading ${asset} from ${release_repository} (${version})"
curl -fsSL --retry 3 --retry-delay 2 -o "$archive" "${release_base}/${asset}"
curl -fsSL --retry 3 --retry-delay 2 -o "$checksum_file" "${release_base}/${asset}.sha256"

# Parse exactly one "<hex>  <name>" line. Validate both the 64-char hex digest
# and the filename so a stray HTML body served with HTTP 200 fails as a
# malformed checksum file rather than as a confusing hash mismatch.
# `read` returns non-zero at EOF when the line has no trailing newline, even
# though it populated the variables — so `|| true`, and let the digest/filename
# validation below reject a genuinely empty or malformed file.
read -r expected_checksum expected_name extra < "$checksum_file" || true
expected_name="${expected_name#\*}"  # strip sha256sum binary-mode marker if present
if [ -n "${extra:-}" ] || ! [[ "$expected_checksum" =~ ^[0-9a-fA-F]{64}$ ]]; then
  fail "malformed checksum file for ${asset}"
fi
if [ "$expected_name" != "$asset" ]; then
  fail "checksum file names '${expected_name:-<missing>}', expected '${asset}'"
fi

if command -v sha256sum >/dev/null 2>&1; then
  actual_checksum="$(sha256sum "$archive" | awk '{print $1; exit}')"
elif command -v shasum >/dev/null 2>&1; then
  actual_checksum="$(shasum -a 256 "$archive" | awk '{print $1; exit}')"
else
  fail "sha256sum or shasum is required to verify Raven"
fi

if [ "$actual_checksum" != "$expected_checksum" ]; then
  fail "checksum mismatch for ${asset}: expected ${expected_checksum}, got ${actual_checksum}"
fi

echo "Checksum verified for ${asset}"

# unzip is standard on Linux/macOS runners; Windows runners ship 7z instead.
if command -v unzip >/dev/null 2>&1; then
  unzip -q "$archive" -d "$extract_dir"
elif command -v 7z >/dev/null 2>&1; then
  # 7z writes errors to stdout, so capture it and surface it only on failure
  # (rather than discarding it) — otherwise a failed Windows extraction aborts
  # with no diagnostic.
  if ! extract_log="$(7z x -y -o"$extract_dir" "$archive" 2>&1)"; then
    printf '%s\n' "$extract_log" >&2
    fail "7z failed to extract ${asset}"
  fi
else
  fail "unzip or 7z is required to extract Raven"
fi

# Require the binary at the archive root, as a regular non-symlink file, so a
# changed archive layout fails loudly rather than silently picking up the wrong
# file.
binary="${extract_dir}/${bin_name}"
if [ ! -f "$binary" ] || [ -L "$binary" ]; then
  fail "archive must contain a regular ${bin_name} at its root"
fi

cp "$binary" "${bin_dir}/${bin_name}"
chmod +x "${bin_dir}/${bin_name}"

# Put the binary on PATH for later workflow steps. (No in-script PATH export:
# the smoke test below calls the absolute path, and a Windows-style bin_dir like
# D:/... would split Bash's colon-separated PATH at the drive-letter colon.)
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$bin_dir" >> "$GITHUB_PATH"
fi

"${bin_dir}/${bin_name}" --version
