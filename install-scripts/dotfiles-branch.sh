#!/bin/bash
# 💫 https://github.com/JaKooLit 💫 #
# Hyprland-Dots to download from main #

#specific branch or release
dots_tag="main"

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "${ERROR} Failed to change directory to $PARENT_DIR"; exit 1; }

# Source the global functions script
if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%d-%H%M%S)_dotfiles.log"
stamp="$(date +%Y%m%d-%H%M%S)"
backup_root="$HOME/.config/.hyprland-backups/$stamp"
manifest="$backup_root/manifest.txt"
mkdir -p "$backup_root"

printf "${NOTE} Cloning and Installing ${SKY_BLUE}KooL's Hyprland Dots for Ubuntu${RESET}....\n" | tee -a "$LOG"

if [ -d Hyprland-Dots-Ubuntu/.git ]; then
  cd Hyprland-Dots-Ubuntu || exit 1
  git fetch --all 2>&1 | tee -a "$LOG"
  git checkout "$dots_tag" 2>&1 | tee -a "$LOG"
  git pull --ff-only 2>&1 | tee -a "$LOG"
else
  rm -rf Hyprland-Dots-Ubuntu
  git clone --depth=1 --branch "$dots_tag" https://github.com/JaKooLit/Hyprland-Dots Hyprland-Dots-Ubuntu 2>&1 | tee -a "$LOG"
  cd Hyprland-Dots-Ubuntu || exit 1
fi

echo "Dotfiles backup root: $backup_root" | tee -a "$LOG"
echo "Dotfiles backup root: $backup_root" > "$manifest"

if [ ! -d "Config" ]; then
  echo -e "${ERROR} Expected dotfiles directory 'Config' was not found in Hyprland-Dots-Ubuntu" | tee -a "$LOG"
  exit 1
fi

while IFS= read -r -d '' src_dir; do
  rel_path="${src_dir#./Config/}"
  target_dir="$HOME/.config/$rel_path"

  if [ -d "$target_dir" ]; then
    backed_up_to="$(backup_path "$target_dir")"
    echo "Backed up $target_dir -> $backed_up_to" | tee -a "$LOG" >> "$manifest"
  fi

  mkdir -p "$target_dir"
  rsync -a --delete --backup --backup-dir="$backup_root/.rsync-overwrites/$rel_path" "$src_dir/" "$target_dir/" 2>&1 | tee -a "$LOG" >> "$manifest"
done < <(find ./Config -mindepth 1 -maxdepth 1 -type d -print0)

echo -e "${OK} Dotfiles merged into ~/.config with timestamped backups at $backup_root" | tee -a "$LOG"
printf "\n%.0s" {1..2}
