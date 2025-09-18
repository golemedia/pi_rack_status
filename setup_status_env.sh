#!/bin/bash
set -e

# Create project folder
mkdir -p ~/status
cd ~/status

# Create venv
python3 -m venv .venv

# Install requirements into the venv (without activating)
./.venv/bin/pip install --upgrade pip
./.venv/bin/pip install -r requirements.txt

echo "✅ Status environment created in ~/status/.venv"
