#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# CONFIG
# -----------------------------
REPO_USER="golemedia"
REPO_NAME="pi_rack_status"
BRANCH="main"

PROJECT_DIR="$(pwd)"
VENV_DIR="$PROJECT_DIR/.venv"
PY="$VENV_DIR/bin/python"
PIP="$VENV_DIR/bin/pip"
SCRIPT="$PROJECT_DIR/oled_status.py"
REQS="$PROJECT_DIR/requirements.txt"

SERVICE_NAME="oled-status.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

RAW_BASE="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}"

# -----------------------------
# HELPERS
# -----------------------------
log() { printf "\e[1;36m[INFO]\e[0m %s\n" "$*"; }
warn() { printf "\e[1;33m[WARN]\e[0m %s\n" "$*"; }
err() { printf "\e[1;31m[ERR ]\e[0m %s\n" "$*" >&2; }

normalize_lf() {
  # strip CRLFs without needing dos2unix
  sed -i 's/\r$//' "$1" || true
}

is_pi5() {
  # Detect model from device tree; returns 0 if Pi 5
  local model_file="/proc/device-tree/model"
  if [[ -r "$model_file" ]] && grep -q "Raspberry Pi 5" "$model_file"; then
    return 0
  fi
  return 1
}

need_reboot_flag="no"

enable_i2c_if_needed() {
  # Bookworm: /boot/firmware/config.txt ; legacy: /boot/config.txt
  local cfg
  if [[ -f /boot/firmware/config.txt ]]; then
    cfg="/boot/firmware/config.txt"
  elif [[ -f /boot/config.txt ]]; then
    cfg="/boot/config.txt"
  else
    warn "Could not find config.txt (unusual system). Skipping I²C enable."
    return
  fi

  if ! grep -q '^[[:space:]]*dtparam=i2c_arm=on' "$cfg"; then
    log "Enabling I²C in $cfg"
    echo "dtparam=i2c_arm=on" | sudo tee -a "$cfg" >/dev/null
    need_reboot_flag="yes"
  fi
}

fetch_latest_files() {
  log "Fetching latest files from GitHub ($REPO_USER/$REPO_NAME@$BRANCH)"
  curl -fsSL "$RAW_BASE/oled_status.py" -o "$SCRIPT"
  curl -fsSL "$RAW_BASE/requirements.txt" -o "$REQS"
  normalize_lf "$SCRIPT"
  normalize_lf "$REQS"
}

create_pi5_gpio_shim_if_needed() {
  if is_pi5; then
    log "Pi 5 detected — creating local RPi.GPIO shim backed by gpiozero"
    mkdir -p "$PROJECT_DIR/RPi"
    cat > "$PROJECT_DIR/RPi/__init__.py" <<'PYI'
# Local shim package for Pi 5 support when code imports RPi.GPIO
PYI
    cat > "$PROJECT_DIR/RPi/GPIO.py" <<'PYG'
# Minimal RPi.GPIO shim for Pi 5 using gpiozero backend
# Provides setmode, setup, input, cleanup, and constants BCM, IN, PUD_UP
from gpiozero import Button

BCM    = 11
IN     = 1
PUD_UP = 2

_buttons = {}

def setmode(_):  # ignore
    pass

def setup(pin, mode, pull_up_down=None):
    # pull-up internally; button wired to pin <-> GND
    _buttons[pin] = Button(pin, pull_up=True, bounce_time=0.05)

def input(pin):
    # Original code tests (GPIO.input(BTN) == 0) as "pressed"
    # With pull-up to 3.3V and press to GND: pressed => is_pressed True => return 0
    b = _buttons.get(pin)
    if b is None:
        return 1
    return 0 if b.is_pressed else 1

def cleanup():
    for b in _buttons.values():
        try:
            b.close()
        except Exception:
            pass
    _buttons.clear()
PYG
  fi
}

write_service() {
  log "Writing systemd unit: $SERVICE_PATH"
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
# Mild guard: if /dev/i2c-1 isn't present yet, the pre-check will fail and systemd will retry (Restart=always).
ExecStartPre=/usr/bin/test -e /dev/i2c-1
ExecStart=$PY $SCRIPT
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT
}

# -----------------------------
# RUN
# -----------------------------
log "Project dir: $PROJECT_DIR"

# 1) System packages (covers Pi 0–5, and Pi 5-specific GPIO backend)
log "Installing system packages (sudo)"
sudo apt update
sudo apt install -y \
  python3-venv python3-dev build-essential \
  fonts-dejavu libraspberrypi-bin i2c-tools \
  python3-gpiozero python3-lgpio

# 2) Enable I²C if needed
enable_i2c_if_needed

# 3) Download the latest app + requirements from your repo
fetch_latest_files

# 4) Create venv (idempotent), upgrade pip tooling
if [[ ! -x "$PY" ]]; then
  log "Creating virtual environment: $VENV_DIR"
  python3 -m venv "$VENV_DIR"
fi

log "Upgrading pip/wheel/setuptools"
"$PIP" install --upgrade pip wheel setuptools

# 5) Any-model GPIO: Pi 5 shim (so your unchanged script continues to import RPi.GPIO)
create_pi5_gpio_shim_if_needed

# 6) Install Python deps from your requirements.txt (latest from repo)
log "Installing Python deps from requirements.txt"
"$PIP" install --no-cache-dir -r "$REQS"

# 7) Write/enable service
write_service
log "Reloading systemd and enabling service"
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"

# 8) Start/restart service
log "Starting service"
sudo systemctl restart "$SERVICE_NAME"

log "Done."
if [[ "$need_reboot_flag" == "yes" ]]; then
  warn "I²C was just enabled in firmware config. If the service fails to start this first time, reboot once:"
  warn "  sudo reboot"
fi
log "Service status:"
sudo systemctl --no-pager --full status "$SERVICE_NAME" || true
log "Tail logs:"
echo "  sudo journalctl -u $SERVICE_NAME -f"
