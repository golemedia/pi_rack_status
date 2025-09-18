#!/bin/bash
case "${1:-}" in
  start)  sudo systemctl start oled-status.service ;;
  stop)   sudo systemctl stop oled-status.service ;;
  restart)sudo systemctl restart oled-status.service ;;
  status) sudo systemctl status oled-status.service ;;
  logs)   sudo journalctl -u oled-status.service -e -n 100 ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|logs}"
    exit 1
    ;;
esac
