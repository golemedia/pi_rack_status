# pi_rack_status

### Displays status information of Raspberry Pi for quick assessment. Also includes function for a reset button with bump protection.
![IMG_1720](https://github.com/user-attachments/assets/4deb1d87-4446-48b0-9ae3-41ea2a3dbf26)

## Information Displayed:
- Hostname
- System Temp
- IP Address
- Power / Undervoltage status
- Placeholder to include status of specific app / service
- CPU Utilization Bar with indicator of highest usage over past 10 readings
&nbsp;
## OLED Wiring
- GND → pin 6
- VCC → pin 1
- SCL → pin 5
- SDA → pin 3
&nbsp;
## Button Wiring
- **Physical pin 11** → one side of the button
- **GND** / **pin 6** (or any GND) → other side of the button
&nbsp;
## Reboot Procedure
- Hold Button for 5 Seconds - screen shows "Ready to Reboot"
- Release Button then Press and Hold again to start 5 second countdown
- Release before countdown ends to cancel reboot

&nbsp;
## To install:

mkdir -p ~/status && cd ~/status
curl -fsSL https://raw.githubusercontent.com/golemedia/pi_rack_status/main/install_status.sh -o install_status.sh
chmod +x install_status.sh
./install_status.sh
