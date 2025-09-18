#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
PROJECT_DIR="$HOME/status"
VENV_DIR="$PROJECT_DIR/.venv"
SERVICE_NAME="oled-status.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
PY="$VENV_DIR/bin/python"
PIP="$VENV_DIR/bin/pip"
REQUIREMENTS="$PROJECT_DIR/requirements.txt"
SCRIPT="$PROJECT_DIR/oled_status.py"

# --- Sanity checks ---
if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "ERROR: $PROJECT_DIR does not exist. Create it first."; exit 1
fi
if [[ ! -f "$SCRIPT" ]]; then
  echo "ERROR: $SCRIPT not found. Save oled_status.py there first."; exit 1
fi

# --- Optional: normalize CRLF endings on the Python script (no dos2unix needed) ---
# (Silently does nothing if already LF)
sed -i 's/\r$//' "$SCRIPT"

# --- System packages (build deps + fonts) ---
# - python3-venv: to create venv
# - python3-dev & build-essential: build RPi.GPIO wheel on 64-bit
# - fonts-dejavu: ensures a baseline font is present for PIL if you ever switch
sudo apt update
sudo apt install -y python3-venv python3-dev build-essential fonts-dejavu

# --- Create venv if missing ---
if [[ ! -x "$PY" ]]; then
  echo "Creating venv: $VENV_DIR"
  python3 -m venv "$VENV_DIR"
fi

# --- Requirements file (create if missing) ---
if [[ ! -f "$REQUIREMENTS" ]]; then
  cat > "$REQUIREMENTS" <<'REQS'
luma.oled
Pillow
RPi.GPIO
REQS
fi

# --- Install/upgrade deps into the venv ---
"$PIP" install --upgrade pip wheel setuptools
# If RPi.GPIO previously failed due to missing headers, the new build deps will fix it:
"$PIP" install --no-cache-dir -r "$REQUIREMENTS"

# --- Create/Update systemd service (runs as root, starts early, shows 'IP: Connecting...') ---
sudo tee "$SERVICE_PATH" >/dev/null <<UNIT
[Unit]
Description=OLED Status Display (early boot)
# Start once udev has settled so /dev/i2c-1 is present; run before network is declared online.
After=systemd-udev-settle.service local-fs.target
Before=network-online.target multi-user.target
Wants=systemd-udev-settle.service

[Service]
Type=simple
User=root
Group=root
ExecStart=$PY $SCRIPT
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

# --- Enable & (re)start service ---
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

echo "✅ Installed and started: $SERVICE_NAME"
echo "   View logs: sudo journalctl -u $SERVICE_NAME -e -n 100"
echo "   Status   : sudo systemctl status $SERVICE_NAME"
