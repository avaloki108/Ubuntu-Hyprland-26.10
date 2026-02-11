#!/bin/bash
# 💫 https://github.com/JaKooLit 💫 #
# Install Hyprland and related packages from PPA (24.04-friendly)

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || exit 1

# shellcheck source=install-scripts/Global_functions.sh
source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"

LOG="Install-Logs/install-$(date +%d-%H%M%S)_hyprland-ppa.log"

echo -e "${INFO} Ensuring Hyprland PPA is available..." | tee -a "$LOG"
ensure_ppa_cppiber_hyprland "$LOG"

if dpkg -l | grep -q '^ii  hyprcursor-util '; then
  echo -e "${NOTE} Purging conflicting package hyprcursor-util before PPA stack install" | tee -a "$LOG"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[DRY-RUN] sudo apt -y purge hyprcursor-util" | tee -a "$LOG"
  else
    sudo apt -y purge hyprcursor-util 2>&1 | tee -a "$LOG" || true
  fi
fi
apt_repair "$LOG"

PKGS=(
  hyprland
  hypridle
  hyprlock
  hyprpaper
  hyprpicker
  hyprwayland-scanner
  hyprland-qtutils
  waybar
)

for p in "${PKGS[@]}"; do
  install_if_available "$p" "$LOG" || true
done

case "${PORTAL_BACKEND:-hyprland}" in
  hyprland)
    install_if_available xdg-desktop-portal-hyprland "$LOG" || true
    ;;
  wlr)
    install_if_available xdg-desktop-portal-wlr "$LOG" || true
    ;;
  build-hyprland)
    echo -e "${NOTE} PORTAL_BACKEND=build-hyprland selected. Run install-scripts/xdph.sh after this step." | tee -a "$LOG"
    ;;
  *)
    echo -e "${WARN} Unknown PORTAL_BACKEND='${PORTAL_BACKEND}'. Skipping explicit portal package install." | tee -a "$LOG"
    ;;
esac

apt_repair "$LOG"
echo -e "${OK} PPA-based Hyprland package installation finished." | tee -a "$LOG"
