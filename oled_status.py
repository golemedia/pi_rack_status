# oled_status_cpu_compact.py
from luma.core.interface.serial import i2c
from luma.oled.device import ssd1306
from PIL import Image, ImageDraw, ImageFont
from collections import deque
import socket, time

I2C_ADDR = 0x3C
W, H = 128, 32
LINE_SPACING = 10          # y=0,10,20 for 3 text lines
FONT = ImageFont.load_default()
MAX_CHARS = 21

BOTTOM_Y = 31              # single-pixel CPU bar at the very bottom
PEAK_TOP_Y = 29             # 3px tall tick (29..31)

def clamp(s): return s[:MAX_CHARS]

def hostname():
    return socket.gethostname()

def ip_addr():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = "0.0.0.0"
    finally:
        s.close()
    return ip

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
    return 0.0 if used < 0 else 100.0 if used > 100 else used

def main(interval=1.0):
    serial = i2c(port=1, address=I2C_ADDR)
    dev = ssd1306(serial_interface=serial, width=W, height=H)
    dev.clear()

    hi = hostname()
    ip = ip_addr()
    status = "Running"  # placeholder

    # seed CPU calc
    pi, pt = read_cpu_times()
    time.sleep(0.1)
    ci, ct = read_cpu_times()
    cur = cpu_percent(pi, pt, ci, ct)
    pi, pt = ci, ct
    hist = deque([cur], maxlen=10)

    while True:
        time.sleep(interval)

        # CPU update
        ci, ct = read_cpu_times()
        cur = cpu_percent(pi, pt, ci, ct)
        pi, pt = ci, ct
        hist.append(cur)
        peak = max(hist)

        temp = cpu_temp_c()

        # draw frame
        img = Image.new("1", (W, H), 0)
        d = ImageDraw.Draw(img)

        # 3 lines of text (y=0,10,20)
        # First line: hostname (left) and temp (right)
        left_txt = clamp(hi)
        temp_txt = f"{temp:.1f}C"
        # Calculate right-justified x position
        temp_w = d.textlength(temp_txt, font=FONT)
        d.text((0, 0), left_txt, font=FONT, fill=255)
        d.text((W - temp_w, 0), temp_txt, font=FONT, fill=255)

        d.text((0, 10), clamp(f"IP: {ip}"),   font=FONT, fill=255)
        d.text((0, 20), clamp(f"Status: {status}"), font=FONT, fill=255)

        # single-pixel CPU bar along bottom
        x_cur  = int((cur  / 100.0) * (W - 1))
        if x_cur > 0:
            d.line((0, BOTTOM_Y, x_cur, BOTTOM_Y), fill=1, width=1)

        # 3px vertical tick for recent peak
        x_peak = int((peak / 100.0) * (W - 1))
        d.line((x_peak, PEAK_TOP_Y, x_peak, BOTTOM_Y), fill=1)

        dev.display(img)

if __name__ == "__main__":
    try:
        main(interval=1.0)
    except KeyboardInterrupt:
        pass
