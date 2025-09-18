#!/usr/bin/env python3
# oled_status.py
#
# Display:
#   Line 1: Hostname (left)  | CPU temp °C (right, 1 decimal)
#   Line 2: IP: <addr>  (or "IP: Connecting..." until acquired)
#   Line 3: Status: Running
#   Bottom: 1px CPU usage bar + 3px peak tick (last 10 samples)
#
# Reboot button on GPIO17 (pin 11) to GND:
#   Hold 5s  -> show "Ready to Reboot"  (READY)
#   Release  -> remain ARMED showing "Ready to Reboot"
#   Press    -> start 5s countdown; keep holding to 0 to reboot
#   Release before 0 -> "Reboot Cancelled" 5s, then NORMAL

from luma.core.interface.serial import i2c
from luma.oled.device import ssd1306
from PIL import Image, ImageDraw, ImageFont
from collections import deque
import RPi.GPIO as GPIO
import socket, time, os

# ---- Display constants ----
I2C_ADDR = 0x3C
W, H = 128, 32
LINE_SPACING = 10          # y = 0,10,20 for 3 text lines
FONT = ImageFont.load_default()
MAX_CHARS = 21
BOTTOM_Y = 31
PEAK_TOP_Y = 29

# ---- Button (BCM numbering) ----
BTN = 17  # physical pin 11, other side of switch to GND

def clamp(s): return s[:MAX_CHARS]

def hostname():
    return socket.gethostname()

def try_ip_addr():
    """
    Return (ip_str, connected_bool).
    If network isn’t ready yet, return ("Connecting...", False).
    """
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(0.2)
    try:
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        if ip and ip != "0.0.0.0":
            return ip, True
        return "Connecting...", False
    except Exception:
        return "Connecting...", False
    finally:
        s.close()

def cpu_temp_c():
    try:
        with open("/sys/class/thermal/thermal_zone0/temp","r") as f:
            return int(f.read().strip()) / 1000.0
    except:
        return 0.0

def read_cpu_times():
    with open("/proc/stat", "r") as f:
        p = f.readline().split()
    vals = list(map(int, p[1:]))
    idle = vals[3] + vals[4]   # idle + iowait
    total = sum(vals)
    return idle, total

def cpu_percent(prev_i, prev_t, cur_i, cur_t):
    di, dt = cur_i - prev_i, cur_t - prev_t
    if dt <= 0: return 0.0
    used = 100.0 * (1.0 - di / dt)
    if used < 0: return 0.0
    if used > 100: return 100.0
    return used

def draw_status(dev, host, ip_text, status, cur_pct, peak_pct, temp):
    img = Image.new("1", (W, H), 0)
    d = ImageDraw.Draw(img)

    # Line 1: hostname left, temp right
    left_txt = clamp(host)
    temp_txt = f"{temp:.1f}C"
    temp_w = d.textlength(temp_txt, font=FONT)
    d.text((0, 0), left_txt, font=FONT, fill=255)
    d.text((W - temp_w, 0), temp_txt, font=FONT, fill=255)

    # Line 2: IP or Connecting...
    d.text((0, 10), clamp(f"IP: {ip_text}"), font=FONT, fill=255)

    # Line 3: Status text
    d.text((0, 20), clamp(f"Status: {status}"), font=FONT, fill=255)

    # Bottom CPU bar
    x_cur  = int((cur_pct  / 100.0) * (W - 1))
    if x_cur > 0:
        d.line((0, BOTTOM_Y, x_cur, BOTTOM_Y), fill=1, width=1)
    x_peak = int((peak_pct / 100.0) * (W - 1))
    d.line((x_peak, PEAK_TOP_Y, x_peak, BOTTOM_Y), fill=1)

    dev.display(img)

def draw_message(dev, a, b="", c=""):
    img = Image.new("1", (W, H), 0)
    d = ImageDraw.Draw(img)
    d.text((0, 0), clamp(a), font=FONT, fill=255)
    if b: d.text((0, 10), clamp(b), font=FONT, fill=255)
    if c: d.text((0, 20), clamp(c), font=FONT, fill=255)
    dev.display(img)

def main(interval_status=1.0):
    # Display init
    serial = i2c(port=1, address=I2C_ADDR)
    dev = ssd1306(serial_interface=serial, width=W, height=H)
    dev.clear()

    # GPIO init
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(BTN, GPIO.IN, pull_up_down=GPIO.PUD_UP)  # pressed = 0

    host = hostname()
    ip_text, ip_ok = try_ip_addr()
    status = "Running"

    # CPU init
    pi, pt = read_cpu_times()
    time.sleep(0.1)
    ci, ct = read_cpu_times()
    cur = cpu_percent(pi, pt, ci, ct)
    pi, pt = ci, ct
    hist = deque([cur], maxlen=10)

    # Button state machine
    STATE = "NORMAL"         # NORMAL -> READY -> ARMED -> COUNTDOWN -> (REBOOT/CANCELLED)
    press_start = None
    countdown = 5
    cancel_show_until = 0.0

    # Timers
    now = time.monotonic()
    next_status_update = now
    next_ip_probe = now

    try:
        while True:
            now = time.monotonic()
            pressed = (GPIO.input(BTN) == 0)

            # ---------- STATE MACHINE ----------
            if STATE == "NORMAL":
                if pressed:
                    if press_start is None:
                        press_start = now
                    elif now - press_start >= 5.0:
                        STATE = "READY"
                        draw_message(dev, "Ready to Reboot")
                else:
                    press_start = None

            elif STATE == "READY":
                # Stay here until user releases after the 5s hold
                if not pressed:
                    STATE = "ARMED"
                    draw_message(dev, "Ready to Reboot")

            elif STATE == "ARMED":
                # Wait for a *new press* to start the countdown
                if pressed:
                    STATE = "COUNTDOWN"
                    countdown = 5
                    draw_message(dev, f"Reboot in {countdown}")
                    next_tick = now + 1.0

            elif STATE == "COUNTDOWN":
                if not pressed:
                    STATE = "CANCELLED"
                    cancel_show_until = now + 5.0
                    draw_message(dev, "Reboot Cancelled")
                else:
                    if now >= next_tick:
                        countdown -= 1
                        if countdown <= 0:
                            draw_message(dev, "Rebooting...")
                            # execv replaces the process; -f for immediate reboot
                            os.execv("/sbin/reboot", ["reboot", "-f"])
                            time.sleep(60)  # fallback if reboot somehow fails
                        else:
                            draw_message(dev, f"Reboot in {countdown}")
                            next_tick = now + 1.0

            elif STATE == "CANCELLED":
                if now >= cancel_show_until:
                    STATE = "NORMAL"
                    press_start = None

            # ---------- IP PROBE ----------
            if now >= next_ip_probe:
                # Probe quickly until we have an IP, then every 5s
                ip_text, ip_ok = try_ip_addr()
                next_ip_probe = now + (0.5 if not ip_ok else 5.0)

            # ---------- STATUS/CPU REFRESH (only in NORMAL) ----------
            if STATE == "NORMAL" and now >= next_status_update:
                temp = cpu_temp_c()
                ci, ct = read_cpu_times()
                cur = cpu_percent(pi, pt, ci, ct)
                pi, pt = ci, ct
                hist.append(cur)
                peak = max(hist)
                draw_status(dev, host, ip_text, status, cur, peak, temp)
                next_status_update = now + interval_status

            time.sleep(0.05)  # ~20Hz loop for responsive button

    finally:
        GPIO.cleanup()

if __name__ == "__main__":
    try:
        main(interval_status=1.0)
    except KeyboardInterrupt:
        GPIO.cleanup()
