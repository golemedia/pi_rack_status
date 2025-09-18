#!/bin/bash
set -euo pipefail

# Create project folder
mkdir -p ~/status
cd ~/status

# Create venv
python3 -m venv .venv

# Requirements
cat > requirements.txt <<'REQS'
luma.oled
Pillow
RPi.GPIO
REQS

# Install deps into the venv (without activating)
./.venv/bin/pip install --upgrade pip wheel setuptools
./.venv/bin/pip install -r requirements.txt

# Ensure oled_status.py exists (skip if you already saved it)
if [ ! -f oled_status.py ]; then
  echo "ERROR: ~/status/oled_status.py not found. Save the script first."
  exit 1
fi

# Create systemd service (root)
SERVICE_FILE=/etc/systemd/system/oled-status.service
sudo tee "$SERVICE_FILE" >/dev/null <<'UNIT'
[Unit]
Description=OLED Status Display (early boot)
# Start early, before network is fully online, so we can show "IP: Connecting..."
# Local filesystems & udev settled ensure /dev/i2c-1 appears.
After=systemd-udev-settle.service local-fs.target
Before=network-online.target multi-user.target
Wants=systemd-udev-settle.service

[Service]
Type=simple
User=root
Group=root
# Run the exact venv Python so imports are guaranteed
ExecStart=/home/revgolem/status/.venv/bin/python /home/revgolem/status/oled_status.py
Restart=always
RestartSec=2
# If I2C needs a moment on some kernels, a short start delay helps:
# ExecStartPre=/bin/sleep 1

[Install]
WantedBy=multi-user.target
UNIT

# Reload systemd, enable and start
sudo systemctl daemon-reload
sudo systemctl enable oled-status.service
sudo systemctl restart oled-status.service

echo "✅ Service installed and started: oled-status.service"
echo "   Check status: sudo systemctl status oled-status.service"
