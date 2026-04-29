#!/bin/sh
# Falcon HTTP Framework — one-line installer
#
# Usage (macOS / Linux):
#   curl -fsSL https://DAN6256.github.io/falcon_sdk/install.sh | sudo sh
#
# Custom install prefix (no sudo needed if you own the directory):
#   FALCON_PREFIX=$HOME/.local sh install.sh
#
# Pin a specific version:
#   VERSION=v1.2.0 sh install.sh

set -e

REPO="DAN6256/falcon_sdk"
PREFIX="${FALCON_PREFIX:-/usr/local}"

# ── detect platform ───────────────────────────────────────────────────────────
OS=$(uname -s)
ARCH=$(uname -m)

case "$OS" in
  Linux)
    case "$ARCH" in
      x86_64)        TARGET="linux-x86_64" ;;
      aarch64|arm64) TARGET="linux-arm64" ;;
      *)
        printf 'Unsupported Linux architecture: %s\n' "$ARCH" >&2
        printf 'Download manually: https://github.com/%s/releases\n' "$REPO" >&2
        exit 1 ;;
    esac
    ;;
  Darwin)
    case "$ARCH" in
      arm64) TARGET="macos-arm64" ;;
      x86_64)
        printf 'macOS x86_64 is not yet supported.\n' >&2
        printf 'Download manually: https://github.com/%s/releases\n' "$REPO" >&2
        exit 1 ;;
      *)
        printf 'Unsupported macOS architecture: %s\n' "$ARCH" >&2
        exit 1 ;;
    esac
    ;;
  *)
    printf 'Unsupported OS: %s\n' "$OS" >&2
    printf 'Download manually: https://github.com/%s/releases\n' "$REPO" >&2
    exit 1 ;;
esac

# ── resolve version ───────────────────────────────────────────────────────────
if [ -z "$VERSION" ]; then
  printf 'Fetching latest Falcon release...\n'
  VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep '"tag_name"' | head -1 \
    | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
fi

if [ -z "$VERSION" ]; then
  printf 'Failed to fetch latest version from the GitHub API.\n' >&2
  printf 'Check your internet connection, or pin a version manually:\n' >&2
  printf '  VERSION=v1.2.0 sh install.sh\n' >&2
  exit 1
fi

ARCHIVE="falcon-${VERSION}-${TARGET}.tar.gz"
BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"

# ── download ──────────────────────────────────────────────────────────────────
TMP=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT

printf 'Downloading Falcon %s for %s...\n' "$VERSION" "$TARGET"
curl -fsSL --progress-bar -o "$TMP/$ARCHIVE"        "${BASE_URL}/${ARCHIVE}"
curl -fsSL                -o "$TMP/$ARCHIVE.sha256" "${BASE_URL}/${ARCHIVE}.sha256"

# ── verify checksum ───────────────────────────────────────────────────────────
printf 'Verifying checksum...\n'
cd "$TMP"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum -c "$ARCHIVE.sha256"
elif command -v shasum >/dev/null 2>&1; then
  shasum -a 256 -c "$ARCHIVE.sha256"
else
  printf 'Warning: no sha256 tool found — skipping checksum verification.\n' >&2
fi
cd - >/dev/null

# ── install ───────────────────────────────────────────────────────────────────
if [ -w "$PREFIX" ]; then
  SUDO=""
else
  SUDO="sudo"
  printf 'Installing to %s (will prompt for sudo)...\n' "$PREFIX"
fi

$SUDO mkdir -p \
  "$PREFIX/include" \
  "$PREFIX/lib/pkgconfig" \
  "$PREFIX/lib/cmake/falcon"

$SUDO tar -xzf "$TMP/$ARCHIVE" -C "$PREFIX"

if [ "$OS" = "Linux" ]; then
  $SUDO ldconfig 2>/dev/null || true
fi

# ── done ──────────────────────────────────────────────────────────────────────
printf '\nFalcon %s installed to %s\n' "$VERSION" "$PREFIX"
printf '\nVerify:\n'
printf '  pkg-config --modversion falcon\n'
printf '\nQuick compile:\n'
printf '  gcc hello.c $(pkg-config --cflags --libs falcon) -o hello\n'
