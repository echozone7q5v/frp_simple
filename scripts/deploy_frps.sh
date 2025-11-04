#!/usr/bin/env bash

set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "[ERROR] Please run this script as root or with sudo." >&2
  exit 1
fi

FRP_VERSION="${FRP_VERSION:-0.65.0}"
FRP_TOKEN="${FRP_TOKEN:-frp-demo-token}"
FRP_BIND_PORT="${FRP_BIND_PORT:-7000}"
FRP_INSTALL_ROOT="${FRP_INSTALL_ROOT:-/opt/frp}"
FRP_SYSTEMD_NAME="${FRP_SYSTEMD_NAME:-frps}"

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

INSTALL_DIR="${FRP_INSTALL_ROOT}/frps"
mkdir -p "$INSTALL_DIR"

echo "[INFO] Installing frps to $INSTALL_DIR"
install -m 0755 "$EXTRACTED_DIR/frps" "$INSTALL_DIR/frps"

cat > "$INSTALL_DIR/frps.toml" <<EOF
bindAddr = "0.0.0.0"
bindPort = ${FRP_BIND_PORT}

[auth]
token = "${FRP_TOKEN}"

[log]
to = "${INSTALL_DIR}/frps.log"
level = "info"
maxDays = 3

[transport]
tls.force = false
EOF

cat > "$INSTALL_DIR/run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/frps" -c "$SCRIPT_DIR/frps.toml"
EOF
chmod +x "$INSTALL_DIR/run.sh"

SERVICE_FILE="/etc/systemd/system/${FRP_SYSTEMD_NAME}.service"
echo "[INFO] Creating systemd service ${FRP_SYSTEMD_NAME}"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=frps reverse proxy service
After=network.target
Wants=network.target

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

echo "[INFO] frps service is running. Use 'systemctl status ${FRP_SYSTEMD_NAME}' to check logs."
echo "[INFO] Ensure TCP port 7000 (control) and desired proxy ports (e.g. 55555) are open in the firewall." 
