#!/bin/sh
set -e

DEST="$HOME/ai"
LLAMA_VER="b9101"
BASE="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_VER}"

detect_arch() {
  case $(uname -m) in
    aarch64|arm64) echo "arm64" ;;
    armv7l)        echo "armhf" ;;
    x86_64)        echo "x64"   ;;
    *)             echo "x64"   ;;
  esac
}

ARCH=$(detect_arch)
FILE="llama-${LLAMA_VER}-bin-ubuntu-${ARCH}.tar.gz"
URL="${BASE}/${FILE}"

echo "=== Download llama.cpp ${LLAMA_VER} untuk ${ARCH} ==="
echo "URL: $URL"
mkdir -p $DEST /tmp/llama-extract

# Download
if command -v wget > /dev/null 2>&1; then
  wget -q --show-progress -O /tmp/llama.tar.gz "$URL"
else
  curl -L --progress-bar -o /tmp/llama.tar.gz "$URL"
fi

# Extract
tar -xzf /tmp/llama.tar.gz -C /tmp/llama-extract

# Cari binary llama-cli
BINARY=$(find /tmp/llama-extract -type f -name "llama-cli" | head -1)
if [ -z "$BINARY" ]; then
  # Fallback cari nama lain
  BINARY=$(find /tmp/llama-extract -type f -executable | head -1)
fi

cp "$BINARY" $DEST/llama-cli
chmod +x $DEST/llama-cli

# Cleanup
rm -rf /tmp/llama.tar.gz /tmp/llama-extract

echo "OK: $(file $DEST/llama-cli)"
echo "Version: $($DEST/llama-cli --version 2>&1 | head -1)"
