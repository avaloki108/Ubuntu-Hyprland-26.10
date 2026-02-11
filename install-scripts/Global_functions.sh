#!/bin/bash
# 💫 https://github.com/JaKooLit 💫 #
# Global Functions for Scripts #

set -e

# Set some colors for output messages
OK="$(tput setaf 2)[OK]$(tput sgr0)"
ERROR="$(tput setaf 1)[ERROR]$(tput sgr0)"
NOTE="$(tput setaf 3)[NOTE]$(tput sgr0)"
INFO="$(tput setaf 4)[INFO]$(tput sgr0)"
WARN="$(tput setaf 1)[WARN]$(tput sgr0)"
CAT="$(tput setaf 6)[ACTION]$(tput sgr0)"
MAGENTA="$(tput setaf 5)"
ORANGE="$(tput setaf 214)"
WARNING="$(tput setaf 1)"
YELLOW="$(tput setaf 3)"
GREEN="$(tput setaf 2)"
BLUE="$(tput setaf 4)"
SKY_BLUE="$(tput setaf 6)"
RESET="$(tput sgr0)"

DRY_RUN="${DRY_RUN:-0}"

# Resolve repo root and build directories based on this file location
GF_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(readlink -f "$GF_DIR/..")"
export REPO_ROOT

# Build directories (override with env to customize)
BUILD_ROOT="${BUILD_ROOT:-$REPO_ROOT/build}"
BUILD_SRC="${BUILD_SRC:-$BUILD_ROOT/src}"
BUILD_BIN="${BUILD_BIN:-$BUILD_ROOT/bin}"
export BUILD_ROOT BUILD_SRC BUILD_BIN

# Ensure standard directories exist
mkdir -p "$REPO_ROOT/Install-Logs" "$BUILD_SRC" "$BUILD_BIN"

run_with_dry_run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo -e "${NOTE} [DRY-RUN] $*"
    return 0
  fi
  "$@"
}

detect_os() {
  if [ ! -r /etc/os-release ]; then
    echo -e "${ERROR} Cannot read /etc/os-release"
    return 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_VERSION_ID="${VERSION_ID:-unknown}"
  OS_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-unknown}}"

  export OS_ID OS_VERSION_ID OS_CODENAME
}

apt_has_candidate() {
  local pkg="$1"
  local candidate
  candidate="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
  [ -n "$candidate" ] && [ "$candidate" != "(none)" ]
}

install_if_available() {
  local pkg="$1"
  local log_file="${2:-${LOG:-/tmp/hypr-install.log}}"

  if dpkg -l | grep -q -w "^ii  ${pkg} "; then
    echo -e "${INFO} ${MAGENTA}${pkg}${RESET} is already installed. Skipping..." | tee -a "$log_file"
    return 0
  fi

  if ! apt_has_candidate "$pkg"; then
    echo -e "${NOTE} ${YELLOW}${pkg}${RESET} has no apt candidate on this release. Skipping." | tee -a "$log_file"
    return 0
  fi

  run_with_dry_run sudo apt install -y "$pkg" >> "$log_file" 2>&1 || {
    echo -e "${WARN} Failed to install ${YELLOW}${pkg}${RESET}. Continuing." | tee -a "$log_file"
    return 1
  }

  if dpkg -l | grep -q -w "^ii  ${pkg} "; then
    echo -e "${OK} Package ${YELLOW}${pkg}${RESET} installed." | tee -a "$log_file"
  fi
}

apt_repair() {
  local log_file="${1:-${LOG:-/tmp/hypr-install.log}}"

  echo -e "${INFO} Running APT repair checks..." | tee -a "$log_file"
  run_with_dry_run sudo dpkg --configure -a >> "$log_file" 2>&1 || true
  run_with_dry_run sudo apt --fix-broken install -y >> "$log_file" 2>&1 || true
}

ensure_ppa_cppiber_hyprland() {
  local log_file="${1:-${LOG:-/tmp/hypr-install.log}}"
  install_if_available software-properties-common "$log_file" || true

  if grep -R "^[[:space:]]*deb .*cppiber.*hyprland" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null | grep -q .; then
    echo -e "${NOTE} ppa:cppiber/hyprland already configured." | tee -a "$log_file"
  else
    run_with_dry_run sudo add-apt-repository -y ppa:cppiber/hyprland >> "$log_file" 2>&1
  fi

  run_with_dry_run sudo apt update >> "$log_file" 2>&1
}

backup_path() {
  local target="$1"
  local stamp backup_root rel dest

  [ -e "$target" ] || return 0

  stamp="${BACKUP_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
  BACKUP_TIMESTAMP="$stamp"
  backup_root="$HOME/.config/.hyprland-backups/$stamp"
  mkdir -p "$backup_root"

  rel="${target#$HOME/}"
  [ "$rel" = "$target" ] && rel="$(basename "$target")"
  dest="$backup_root/$rel"
  mkdir -p "$(dirname "$dest")"

  if [ -d "$target" ]; then
    run_with_dry_run rsync -a "$target/" "$dest/"
  else
    run_with_dry_run cp -a "$target" "$dest"
  fi

  echo "$dest"
}

# Show progress function
show_progress() {
    local pid=$1
    local package_name=$2
    local spin_chars=("●○○○○○○○○○" "○●○○○○○○○○" "○○●○○○○○○○" "○○○●○○○○○○" "○○○○●○○○○" \
                      "○○○○○●○○○○" "○○○○○○●○○○" "○○○○○○○●○○" "○○○○○○○○●○" "○○○○○○○○○●")
    local i=0

    tput civis
    printf "\r${INFO} Installing ${YELLOW}%s${RESET} ..." "$package_name"

    while ps -p $pid &> /dev/null; do
        printf "\r${INFO} Installing ${YELLOW}%s${RESET} %s" "$package_name" "${spin_chars[i]}"
        i=$(( (i + 1) % 10 ))
        sleep 0.3
    done

    printf "\r${INFO} Installing ${YELLOW}%s${RESET} ... Done!%-20s \n\n" "$package_name" ""
    tput cnorm
}


# Function for installing packages with a progress bar
install_package() {
  if dpkg -l | grep -q -w "$1" ; then
    echo -e "${INFO} ${MAGENTA}$1${RESET} is already installed. Skipping..."
  else
    (
      stdbuf -oL sudo apt install -y "$1" 2>&1
    ) >> "$LOG" 2>&1 &
    PID=$!
    show_progress $PID "$1"

    # Double check if the package successfully installed
    if dpkg -l | grep -q -w "$1"; then
        echo -e "\e[1A\e[K${OK} Package ${YELLOW}$1${RESET} has been successfully installed!"
    else
        echo -e "\e[1A\e[K${ERROR} ${YELLOW}$1${RESET} failed to install. Please check the install.log. You may need to install it manually. Sorry, I have tried :("
    fi
  fi
}

# Function for build depencies with a progress bar
build_dep() {
  echo -e "${INFO} building dependencies for ${MAGENTA}$1${RESET} "
    (
      stdbuf -oL sudo apt build-dep -y "$1" 2>&1
    ) >> "$LOG" 2>&1 &
    PID=$!
    show_progress $PID "$1"
}

# Function for cargo install with a progress bar
cargo_install() {
  echo -e "${INFO} installing ${MAGENTA}$1${RESET} using cargo..."
    (
      stdbuf -oL cargo install "$1" 2>&1
    ) >> "$LOG" 2>&1 &
    PID=$!
    show_progress $PID "$1"
}

# Function for re-installing packages with a progress bar
re_install_package() {
    (
        stdbuf -oL sudo apt install --reinstall -y "$1" 2>&1
    ) >> "$LOG" 2>&1 &

    PID=$!
    show_progress $PID "$1"

    if dpkg -l | grep -q -w "$1"; then
        echo -e "\e[1A\e[K${OK} Package ${YELLOW}$1${RESET} has been successfully re-installed!"
    else
        # Package not found, reinstallation failed
        echo -e "${ERROR} ${YELLOW}$1${RESET} failed to re-install. Please check the install.log. You may need to install it manually. Sorry, I have tried :("
    fi
}

# Function for removing packages
uninstall_package() {
  local pkg="$1"

  # Checking if package is installed
  if sudo dpkg -l | grep -q -w "^ii  $1" ; then
    echo -e "${NOTE} removing $pkg ..."
    run_with_dry_run sudo apt autoremove -y "$1" >> "$LOG" 2>&1 || true

    if ! dpkg -l | grep -q -w "^ii  $1" ; then
      echo -e "\e[1A\e[K${OK} ${MAGENTA}$1${RESET} removed."
    else
      echo -e "\e[1A\e[K${ERROR} $pkg Removal failed. No actions required."
      return 1
    fi
  else
    echo -e "${INFO} Package $pkg not installed, skipping."
  fi
  return 0
}
