#!/bin/bash
# 💫 https://github.com/JaKooLit 💫 #
# Enable Hyprland PPA for Ubuntu 24.04

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || exit 1

# shellcheck source=install-scripts/Global_functions.sh
source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"

LOG="Install-Logs/install-$(date +%d-%H%M%S)_hyprland-ppa-enable.log"

detect_os
if [ "$OS_ID" != "ubuntu" ] || [ "$OS_VERSION_ID" != "24.04" ] || [ "$OS_CODENAME" != "noble" ]; then
  echo -e "${WARN} hyprland-ppa-enable.sh is tuned for Ubuntu 24.04 noble. Detected ${OS_ID} ${OS_VERSION_ID} (${OS_CODENAME})." | tee -a "$LOG"
fi

ensure_ppa_cppiber_hyprland "$LOG"

if ! apt_has_candidate hyprland; then
  echo -e "${ERROR} No hyprland candidate detected after enabling PPA." | tee -a "$LOG"
  exit 1
fi

echo -e "${OK} Hyprland PPA is enabled and candidate packages are available." | tee -a "$LOG"
