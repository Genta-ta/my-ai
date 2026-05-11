#!/bin/sh
set -e

REPO="Genta-ta/my-ai"
DEST="$HOME/ai"
MODEL_URL="https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf"

echo "=== Deploy AI ke ARM64 ==="

# 1. Cek arsitektur
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
  echo "ERROR: Device bukan ARM64 (detected: $ARCH)"
  exit 1
fi

# 2. Install gh cli jika belum ada
if ! command -v gh > /dev/null 2>&1; then
  echo "[1] Install GitHub CLI..."
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
    https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list
  sudo apt update && sudo apt install -y gh
fi

# 3. Download binary dari GitHub
echo "[2] Download binary ARM64..."
mkdir -p $DEST
gh run download \
  $(gh run list --repo $REPO --limit 1 --json databaseId -q '.[0].databaseId') \
  --repo $REPO \
  --name ai-arm64-binaries \
  --dir $DEST

chmod +x $DEST/ai-server $DEST/search

# 4. Download model jika belum ada
if [ ! -f "$DEST/model.gguf" ]; then
  echo "[3] Download model Phi-3 mini (~2GB)..."
  wget -q --show-progress -O $DEST/model.gguf "$MODEL_URL"
else
  echo "[3] Model sudah ada, skip download"
fi

# 5. Buat systemd service agar auto-start
echo "[4] Setup systemd service..."
sudo tee /etc/systemd/system/ai-server.service > /dev/null << SERVICE
[Unit]
Description=AI Server ARM64
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$DEST
ExecStart=$DEST/ai-server
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable ai-server
sudo systemctl start ai-server

echo ""
echo "=== Selesai! ==="
echo "Server  : http://localhost:8080"
echo "Test    : curl -X POST http://localhost:8080 -d '{\"prompt\":\"Halo\"}'"
echo "Log     : journalctl -u ai-server -f"
echo "Status  : systemctl status ai-server"
