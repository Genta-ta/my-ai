#!/bin/sh
set -e

REPO="Genta-ta/my-ai"
DEST="$HOME/ai"
MODEL_URL="https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf"

echo "=== Deploy AI Universal ==="

# ── Deteksi OS ────────────────────────────────────────
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo $ID
  elif command -v uname > /dev/null; then
    uname -s | tr '[:upper:]' '[:lower:]'
  else
    echo "unknown"
  fi
}

# ── Deteksi Arsitektur ────────────────────────────────
detect_arch() {
  case $(uname -m) in
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv6l) echo "arm32" ;;
    x86_64|amd64)  echo "x64"   ;;
    riscv64)       echo "riscv" ;;
    *)             echo "unknown" ;;
  esac
}

# ── Deteksi Package Manager ───────────────────────────
detect_pkg() {
  for pm in apt dnf yum pacman apk brew; do
    command -v $pm > /dev/null 2>&1 && echo $pm && return
  done
  echo "unknown"
}

# ── Install Package ───────────────────────────────────
pkg_install() {
  PKG=$1
  case $PKG_MGR in
    apt)    sudo apt update -qq && sudo apt install -y $PKG ;;
    dnf)    sudo dnf install -y $PKG ;;
    yum)    sudo yum install -y $PKG ;;
    pacman) sudo pacman -Sy --noconfirm $PKG ;;
    apk)    sudo apk add $PKG ;;
    brew)   brew install $PKG ;;
    *)      echo "ERROR: package manager tidak dikenali"; exit 1 ;;
  esac
}

# ── Deteksi Init System ───────────────────────────────
detect_init() {
  if command -v systemctl > /dev/null 2>&1; then
    echo "systemd"
  elif [ -f /etc/init.d ]; then
    echo "openrc"
  elif command -v launchctl > /dev/null 2>&1; then
    echo "launchd"
  else
    echo "none"
  fi
}

# ── Info System ───────────────────────────────────────
OS=$(detect_os)
ARCH=$(detect_arch)
PKG_MGR=$(detect_pkg)
INIT=$(detect_init)
RAM_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)

echo "OS      : $OS"
echo "Arch    : $ARCH"
echo "RAM     : ${RAM_MB}MB"
echo "Cores   : $CORES"
echo "Init    : $INIT"
echo "Pkg Mgr : $PKG_MGR"
echo "───────────────────────"

# ── Cek Arsitektur Support ────────────────────────────
if [ "$ARCH" = "unknown" ]; then
  echo "ERROR: Arsitektur tidak didukung ($(uname -m))"
  exit 1
fi

# ── Pilih Model Berdasarkan RAM ───────────────────────
pick_model() {
  if [ "$RAM_MB" -ge 16000 ]; then
    MODEL_FILE="Phi-3-mini-4k-instruct-q8.gguf"
    echo "Model   : Phi-3 Q8 (RAM >= 16GB)"
  elif [ "$RAM_MB" -ge 8000 ]; then
    MODEL_FILE="Phi-3-mini-4k-instruct-q5.gguf"
    echo "Model   : Phi-3 Q5 (RAM >= 8GB)"
  elif [ "$RAM_MB" -ge 4000 ]; then
    MODEL_FILE="Phi-3-mini-4k-instruct-q4.gguf"
    echo "Model   : Phi-3 Q4 (RAM >= 4GB)"
  else
    MODEL_FILE="Phi-3-mini-4k-instruct-q4.gguf"
    echo "WARN    : RAM < 4GB, performa mungkin lambat"
  fi
  MODEL_URL="https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/$MODEL_FILE"
}

pick_model

# ── Install GitHub CLI ────────────────────────────────
install_gh() {
  if command -v gh > /dev/null 2>&1; then
    echo "[gh] sudah terinstall"
    return
  fi
  echo "[1] Install GitHub CLI..."
  case $OS in
    ubuntu|debian|raspbian|armbian)
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
        https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list
      sudo apt update -qq && sudo apt install -y gh
      ;;
    fedora|centos|rhel)
      sudo dnf install -y 'dnf-command(config-manager)'
      sudo dnf config-manager --add-repo \
        https://cli.github.com/packages/rpm/gh-cli.repo
      sudo dnf install -y gh
      ;;
    arch|manjaro)
      sudo pacman -Sy --noconfirm github-cli
      ;;
    alpine)
      sudo apk add github-cli
      ;;
    darwin)
      brew install gh
      ;;
    *)
      # Fallback: download binary langsung
      GH_VER=$(curl -s https://api.github.com/repos/cli/cli/releases/latest \
        | grep tag_name | cut -d'"' -f4 | tr -d 'v')
      case $ARCH in
        arm64) GH_ARCH="arm64" ;;
        arm32) GH_ARCH="armv6" ;;
        x64)   GH_ARCH="amd64" ;;
        *)     echo "ERROR: gh CLI tidak bisa diinstall"; exit 1 ;;
      esac
      curl -fsSL \
        "https://github.com/cli/cli/releases/download/v${GH_VER}/gh_${GH_VER}_linux_${GH_ARCH}.tar.gz" \
        | sudo tar -xz -C /usr/local/bin --strip-components=2 \
          "gh_${GH_VER}_linux_${GH_ARCH}/bin/gh"
      ;;
  esac
}

install_gh

# ── Download Binary ───────────────────────────────────
echo "[2] Download binary dari GitHub..."
mkdir -p $DEST

RUN_ID=$(gh run list --repo $REPO --limit 1 \
  --json databaseId -q '.[0].databaseId')

gh run download $RUN_ID \
  --repo $REPO \
  --name ai-arm64-binaries \
  --dir $DEST

chmod +x $DEST/ai-server $DEST/search

# ── Download Model ────────────────────────────────────
if [ ! -f "$DEST/model.gguf" ]; then
  echo "[3] Download model (~2GB)..."
  if command -v wget > /dev/null 2>&1; then
    wget -q --show-progress -O $DEST/model.gguf "$MODEL_URL"
  elif command -v curl > /dev/null 2>&1; then
    curl -L --progress-bar -o $DEST/model.gguf "$MODEL_URL"
  else
    pkg_install wget
    wget -q --show-progress -O $DEST/model.gguf "$MODEL_URL"
  fi
else
  echo "[3] Model sudah ada, skip"
fi

# ── Sesuaikan Threads di Config ───────────────────────
echo "[4] Tuning threads = $CORES cores..."
sed -i "s/--threads 4/--threads $CORES/g" $DEST/ai-server 2>/dev/null || true

# ── Setup Auto-start ──────────────────────────────────
echo "[5] Setup auto-start ($INIT)..."

case $INIT in
  systemd)
    sudo tee /etc/systemd/system/ai-server.service > /dev/null << SERVICE
[Unit]
Description=AI Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$DEST
ExecStart=$DEST/ai-server
Restart=always
RestartSec=3
Nice=10

[Install]
WantedBy=multi-user.target
SERVICE
    sudo systemctl daemon-reload
    sudo systemctl enable ai-server
    sudo systemctl restart ai-server
    ;;

  openrc)
    sudo tee /etc/init.d/ai-server > /dev/null << SERVICE
#!/sbin/openrc-run
description="AI Server"
command="$DEST/ai-server"
command_background=true
pidfile="/run/ai-server.pid"
directory="$DEST"
SERVICE
    sudo chmod +x /etc/init.d/ai-server
    sudo rc-update add ai-server default
    sudo rc-service ai-server restart
    ;;

  launchd)
    # macOS
    tee ~/Library/LaunchAgents/ai.server.plist > /dev/null << SERVICE
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>ai.server</string>
  <key>ProgramArguments</key>
  <array><string>$DEST/ai-server</string></array>
  <key>WorkingDirectory</key><string>$DEST</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
SERVICE
    launchctl load ~/Library/LaunchAgents/ai.server.plist
    ;;

  none)
    # Fallback: pakai screen atau nohup
    if command -v screen > /dev/null 2>&1; then
      screen -dmS ai-server $DEST/ai-server
    else
      nohup $DEST/ai-server > $DEST/server.log 2>&1 &
      echo $! > $DEST/server.pid
    fi
    ;;
esac

# ── Selesai ───────────────────────────────────────────
echo ""
echo "=== Selesai! ==="
echo "Server  : http://localhost:8080"
echo "Test    : curl -s -X POST http://localhost:8080 \\"
echo "          -d '{\"prompt\":\"Halo, siapa kamu?\"}'"
echo ""
case $INIT in
  systemd) echo "Log     : journalctl -u ai-server -f"
           echo "Status  : systemctl status ai-server" ;;
  openrc)  echo "Log     : tail -f /var/log/ai-server.log"
           echo "Status  : rc-service ai-server status" ;;
  launchd) echo "Log     : tail -f $DEST/server.log" ;;
  none)    echo "Log     : tail -f $DEST/server.log" ;;
esac
