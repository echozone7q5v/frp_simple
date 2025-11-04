#!/usr/bin/env bash

set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "[ERROR] Please run this script as root or with sudo." >&2
  exit 1
fi

FRP_VERSION="${FRP_VERSION:-0.65.0}"
FRP_TOKEN="${FRP_TOKEN:-frp-demo-token}"
FRP_SERVER_ADDR="${FRP_SERVER_ADDR:-23.146.156.14}"
FRP_SERVER_PORT="${FRP_SERVER_PORT:-7000}"
FRP_LOCAL_IP="${FRP_LOCAL_IP:-127.0.0.1}"
FRP_LOCAL_PORT="${FRP_LOCAL_PORT:-5555}"
FRP_REMOTE_PORT="${FRP_REMOTE_PORT:-55555}"
FRP_INSTALL_ROOT="${FRP_INSTALL_ROOT:-/opt/frp}"
FRP_SYSTEMD_NAME="${FRP_SYSTEMD_NAME:-frpc}"
FRP_PROXY_NAME="${FRP_PROXY_NAME:-local-5555}"

detect_arch() {
  local machine suffix
  machine="$(uname -m)"
  case "$machine" in
    x86_64|amd64)
      suffix="linux_amd64"
      ;;
    aarch64|arm64)
      suffix="linux_arm64"
      ;;
    armv7l)
      suffix="linux_arm_hf"
      ;;
    armv6l)
      suffix="linux_arm"
      ;;
    *)
      echo "[ERROR] Unsupported architecture: $machine" >&2
      echo "Set FRP_ARCH_SUFFIX manually (e.g. linux_amd64) and re-run." >&2
      exit 1
      ;;
  esac
  echo "$suffix"
}

ARCH_SUFFIX="${FRP_ARCH_SUFFIX:-$(detect_arch)}"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

TARBALL="frp_${FRP_VERSION}_${ARCH_SUFFIX}.tar.gz"
TARBALL_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${TARBALL}"

echo "[INFO] Downloading ${TARBALL_URL}"
curl -fsSL "$TARBALL_URL" -o "$TMP_DIR/$TARBALL"

echo "[INFO] Extracting $TARBALL"
tar -xzf "$TMP_DIR/$TARBALL" -C "$TMP_DIR"

EXTRACTED_DIR="$TMP_DIR/frp_${FRP_VERSION}_${ARCH_SUFFIX}"
if [[ ! -d "$EXTRACTED_DIR" ]]; then
  echo "[ERROR] Failed to extract frp archive." >&2
  exit 1
fi

INSTALL_DIR="${FRP_INSTALL_ROOT}/frpc"
mkdir -p "$INSTALL_DIR"

echo "[INFO] Installing frpc to $INSTALL_DIR"
install -m 0755 "$EXTRACTED_DIR/frpc" "$INSTALL_DIR/frpc"

cat > "$INSTALL_DIR/frpc.toml" <<EOF
serverAddr = "${FRP_SERVER_ADDR}"
serverPort = ${FRP_SERVER_PORT}

[auth]
token = "${FRP_TOKEN}"

[log]
to = "${INSTALL_DIR}/frpc.log"
level = "info"
maxDays = 3

[[proxies]]
name = "${FRP_PROXY_NAME}"
type = "tcp"
localIP = "${FRP_LOCAL_IP}"
localPort = ${FRP_LOCAL_PORT}
remotePort = ${FRP_REMOTE_PORT}
EOF

cat > "$INSTALL_DIR/run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/frpc" -c "$SCRIPT_DIR/frpc.toml"
EOF
chmod +x "$INSTALL_DIR/run.sh"

SERVICE_FILE="/etc/systemd/system/${FRP_SYSTEMD_NAME}.service"
echo "[INFO] Creating systemd service ${FRP_SYSTEMD_NAME}"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=frpc client service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/run.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$FRP_SYSTEMD_NAME"

echo "[INFO] frpc service is running. Use 'systemctl status ${FRP_SYSTEMD_NAME}' to check logs." 
echo "[INFO] Local service ${FRP_LOCAL_IP}:${FRP_LOCAL_PORT} is now exposed via ${FRP_SERVER_ADDR}:${FRP_REMOTE_PORT}."
