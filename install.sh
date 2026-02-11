#!/bin/bash
# https://github.com/JaKooLit

clear

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

# CLI options
INSTALL_MODE="${INSTALL_MODE:-auto}"
HYPRLAND_SOURCE_REPO="${HYPRLAND_SOURCE_REPO:-https://github.com/hyprwm/Hyprland.git}"
HYPRLAND_SOURCE_BRANCH="${HYPRLAND_SOURCE_BRANCH:-26.04}"
DO_DRY_RUN=0
SHOW_HELP=0
for arg in "$@"; do
    case "$arg" in
        --install-source)
            INSTALL_MODE=source
            ;;
        --install-ubuntu|--install-ppa)
            # Install Hyprland from apt/ppa
            INSTALL_MODE=ppa
            ;;
        --dry-run)
            DO_DRY_RUN=1
            ;;
        -h|--help)
            SHOW_HELP=1
            ;;
    esac
done

if [ "$SHOW_HELP" = "1" ]; then
    cat <<USAGE
Usage: ./install.sh [options]

Options:
  --install-source    Build Hyprland from source
  --install-ubuntu    Install Hyprland via apt/ppa
  --install-ppa       Install Hyprland via apt/ppa
  --dry-run           Print what would be done and exit (non-interactive)
  -h, --help          Show this help and exit

Notes:
- On Ubuntu 24.04, installer defaults to PPA mode unless --install-source is set.
- Source checkout is locked to branch '${HYPRLAND_SOURCE_BRANCH}'.
USAGE
    exit 0
fi

# Dry-run mode is forwarded to child scripts
if [ "$DO_DRY_RUN" = "1" ]; then
    export DRY_RUN=1
fi

# Function to print colorful text
print_color() {
    printf "%b%s%b\n" "$1" "$2" "$RESET"
}

# Source global helpers for OS detection and apt strategy
source "$(dirname "$(readlink -f "$0")")/install-scripts/Global_functions.sh"

detect_os
if [ "$OS_ID" != "ubuntu" ]; then
    echo -e "${ERROR} This installer supports Ubuntu only. Detected: ${OS_ID}" 
    exit 1
fi

if [ "$OS_VERSION_ID" = "24.04" ] && [ "$OS_CODENAME" = "noble" ] && [ "$INSTALL_MODE" = "auto" ]; then
    INSTALL_MODE="ppa"
elif [ "$INSTALL_MODE" = "auto" ]; then
    INSTALL_MODE="source"
fi

if [ "$OS_VERSION_ID" != "24.04" ] && [ "$INSTALL_MODE" = "ppa" ]; then
    echo -e "${WARN} PPA mode is optimized for Ubuntu 24.04. Continuing with current selection."
fi

if [ "$OS_VERSION_ID" != "24.04" ] || [ "$OS_CODENAME" != "noble" ]; then
    if [ "${ALLOW_UNSUPPORTED_OS:-0}" != "1" ]; then
        echo -e "${ERROR} This adapted installer targets Ubuntu 24.04 (noble). Detected ${OS_VERSION_ID} (${OS_CODENAME})."
        echo -e "${NOTE} Set ALLOW_UNSUPPORTED_OS=1 to bypass this guard."
        exit 1
    fi
fi

if [ "$DO_DRY_RUN" = "1" ]; then
    echo "[DRY-RUN] OS detected: ${OS_ID} ${OS_VERSION_ID} (${OS_CODENAME})"
    echo "[DRY-RUN] Install mode: ${INSTALL_MODE}"
    echo "[DRY-RUN] Portal backend: ${PORTAL_BACKEND:-hyprland}"
    echo "[DRY-RUN] Would execute dependency, package, and optional component scripts without making changes."
    exit 0
fi

# Display warning message
printf "\n%.0s" {1..2}
print_color $WARNING "
    █▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀█
                KooL's UBUNTU Hyprland Installer               
    █▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄█

    Installer mode: ${INSTALL_MODE}.
    Ubuntu 24.04 (noble) is supported with PPA mode.
    Source mode is available for advanced users.
         
"
printf "\n%.0s" {1..2}

# Prompt user to continue or exit
read -rp "$YELLOW Do you still want to continue with Hyprland installation using this script? [y/N]: " confirm
case "$confirm" in
[yY][eE][sS] | [yY])
    echo -e "${OK} Continuing with installation..."
    ;;
*)
    echo
    echo
    echo -e "${NOTE} You chose not to continue. Exiting..."
    echo
    exit 1
    ;;
esac

# Create Directory for Install Logs
if [ ! -d Install-Logs ]; then
    mkdir Install-Logs
fi

# Set the name of the log file to include the current date and time
LOG="Install-Logs/01-Hyprland-Install-Scripts-$(date +%d-%H%M%S).log"

# Initialize build directories under repo root so child scripts build in build/src and drop artifacts in build/bin
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT="$SCRIPT_DIR"
: "${BUILD_ROOT:=$REPO_ROOT/build}"
: "${BUILD_SRC:=$BUILD_ROOT/src}"
: "${BUILD_BIN:=$BUILD_ROOT/bin}"
export BUILD_ROOT BUILD_SRC BUILD_BIN
mkdir -p "$BUILD_SRC" "$BUILD_BIN" "$REPO_ROOT/Install-Logs"


# Check if running as root. If root, script will exit
if [[ $EUID -eq 0 ]]; then
    echo "${ERROR}  This script should ${WARNING}NOT${RESET} be executed as root!! Exiting......." | tee -a "$LOG"
    printf "\n%.0s" {1..2}
    exit 1
fi

# Ensure locally installed libraries are discoverable by pkg-config and CMake across all child scripts
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig:${PKG_CONFIG_PATH:-}"
export CMAKE_PREFIX_PATH="/usr/local:${CMAKE_PREFIX_PATH:-}"

# install whiptails if detected not installed. Necessary for this version
if ! command -v whiptail >/dev/null; then
    echo "${NOTE} - whiptail is not installed. Installing..." | tee -a "$LOG"
    sudo apt install -y whiptail
    printf "\n%.0s" {1..1}
fi

printf "\n%.0s" {1..2}
echo -e "\e[35m
	╦╔═┌─┐┌─┐╦    ╦ ╦┬ ┬┌─┐┬─┐┬  ┌─┐┌┐┌┌┬┐
	╠╩╗│ ││ │║    ╠═╣└┬┘├─┘├┬┘│  ├─┤│││ ││ 2025
	╩ ╩└─┘└─┘╩═╝  ╩ ╩ ┴ ┴  ┴└─┴─┘┴ ┴┘└┘─┴┘ Ubuntu 25.10+
\e[0m"
printf "\n%.0s" {1..1}

# Welcome message using whiptail (for displaying information)
whiptail --title "KooL Ubuntu 26.04+ - Hyprland (2025) Install Script" \
    --msgbox "Welcome to KooL Ubuntu 26.04+ - Hyprland (2025) Install Script!!!\n\n\
ATTENTION: Run a full system update and Reboot first !!! (Highly Recommended)\n\n\
NOTE: If you are installing on a VM, ensure to enable 3D acceleration else Hyprland may NOT start!" \
    15 80

# Ask if the user wants to proceed
if ! whiptail --title "Proceed with Installation?" \
    --yesno "Would you like to proceed?" 7 50; then
    echo -e "\n"
    echo "❌ ${INFO} You 🫵 chose ${YELLOW}NOT${RESET} to proceed. ${YELLOW}Exiting...${RESET}" | tee -a "$LOG"
    echo -e "\n"
    exit 1
fi

echo "👌 ${OK} 🇵🇭 ${MAGENTA}KooL..${RESET} ${SKY_BLUE}lets continue with the installation...${RESET}" | tee -a "$LOG"

sleep 1
printf "\n%.0s" {1..1}

# install pciutils if detected not installed. Necessary for detecting GPU
if ! dpkg -l | grep -w pciutils >/dev/null; then
    echo "pciutils is not installed. Installing..." | tee -a "$LOG"
    sudo apt install -y pciutils
    printf "\n%.0s" {1..1}
fi

PORTAL_BACKEND="${PORTAL_BACKEND:-hyprland}"
if [ "$OS_VERSION_ID" = "24.04" ] && [ "$INSTALL_MODE" = "ppa" ]; then
    PORTAL_BACKEND="${PORTAL_BACKEND:-hyprland}"
fi
export PORTAL_BACKEND
echo "${INFO} Portal backend strategy: ${PORTAL_BACKEND}" | tee -a "$LOG"

# Path to the install-scripts directory
script_directory=install-scripts


# Function to execute a script if it exists and make it executable
execute_script() {
    local script="$1"
    local script_path="$script_directory/$script"
    if [ -f "$script_path" ]; then
        chmod +x "$script_path"
        if [ -x "$script_path" ]; then
            env "$script_path"
        else
            echo "Failed to make script '$script' executable." | tee -a "$LOG"
        fi
    else
        echo "Script '$script' not found in '$script_directory'." | tee -a "$LOG"
    fi
}

build_hyprland_from_2604_branch() {
    local src_dir="$BUILD_SRC/Hyprland"
    local jobs
    jobs="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN || echo 1)"

    if [[ "$HYPRLAND_SOURCE_BRANCH" == *dev* ]] || [[ "$HYPRLAND_SOURCE_BRANCH" == *src-build* ]]; then
        echo "${ERROR} Refusing Hyprland source branch '$HYPRLAND_SOURCE_BRANCH'. Use branch '26.04' only." | tee -a "$LOG"
        exit 1
    fi

    echo "${INFO} Installing ${SKY_BLUE}Hyprland source build dependencies...${RESET}" | tee -a "$LOG"
    sudo apt install -y \
        build-essential \
        ccache \
        clang \
        cmake \
        git \
        libglaze-dev \
        libre2-dev \
        libudis86-dev \
        libxcb-errors-dev \
        llvm \
        meson \
        ninja-build \
        pkg-config 2>&1 | tee -a "$LOG"

    echo "${INFO} Checking out ${SKY_BLUE}Hyprland ${HYPRLAND_SOURCE_BRANCH}${RESET} from ${SKY_BLUE}${HYPRLAND_SOURCE_REPO}${RESET}..." | tee -a "$LOG"
    if [ -d "$src_dir/.git" ]; then
        git -C "$src_dir" fetch --all --tags --prune 2>&1 | tee -a "$LOG"
    else
        rm -rf "$src_dir"
        git clone --recursive "$HYPRLAND_SOURCE_REPO" "$src_dir" 2>&1 | tee -a "$LOG"
    fi

    if ! git -C "$src_dir" checkout -f "$HYPRLAND_SOURCE_BRANCH" 2>&1 | tee -a "$LOG"; then
        echo "${ERROR} Could not checkout '$HYPRLAND_SOURCE_BRANCH'. Set HYPRLAND_SOURCE_REPO/HYPRLAND_SOURCE_BRANCH to a valid 26.04 source branch." | tee -a "$LOG"
        exit 1
    fi
    git -C "$src_dir" submodule update --init --recursive 2>&1 | tee -a "$LOG"

    echo "${INFO} Building ${SKY_BLUE}Hyprland${RESET} from branch ${SKY_BLUE}${HYPRLAND_SOURCE_BRANCH}${RESET}..." | tee -a "$LOG"
    CC="${CC:-clang}" CXX="${CXX:-clang++}" \
        cmake -S "$src_dir" -B "$src_dir/build" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_C_COMPILER="${CC:-clang}" \
            -DCMAKE_CXX_COMPILER="${CXX:-clang++}" \
            -DCMAKE_CXX_STANDARD=26 \
            -DCMAKE_CXX_STANDARD_REQUIRED=ON \
            -DCMAKE_CXX_EXTENSIONS=ON 2>&1 | tee -a "$LOG"
    cmake --build "$src_dir/build" -j "$jobs" 2>&1 | tee -a "$LOG"
    sudo cmake --install "$src_dir/build" 2>&1 | tee -a "$LOG"
}

install_terminal_stack() {
    echo "${INFO} Installing ${SKY_BLUE}terminal stack${RESET} (alacritty, zellij, tmux)..." | tee -a "$LOG"
    sudo apt install -y alacritty zellij tmux 2>&1 | tee -a "$LOG"
}

set_alacritty_default_terminal() {
    if ! command -v update-alternatives >/dev/null 2>&1; then
        return
    fi

    if [ ! -x /usr/bin/alacritty ]; then
        echo "${WARN} alacritty binary not found in /usr/bin. Skipping default terminal setup." | tee -a "$LOG"
        return
    fi

    if sudo update-alternatives --query x-terminal-emulator >/dev/null 2>&1; then
        if ! sudo update-alternatives --list x-terminal-emulator 2>/dev/null | grep -qx "/usr/bin/alacritty"; then
            sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/alacritty 90 2>&1 | tee -a "$LOG"
        fi
        sudo update-alternatives --set x-terminal-emulator /usr/bin/alacritty 2>&1 | tee -a "$LOG"
    fi
}

apt_pkg_exists() {
    apt-cache show "$1" >/dev/null 2>&1
}

install_cosmic_stack() {
    local launcher_pkg=""
    local installable=()
    local cosmic_core=(
        cosmic-panel
        cosmic-session
        cosmic-comp
        cosmic-bg
        cosmic-files
        cosmic-settings
        xdg-desktop-portal-cosmic
    )

    for launcher_candidate in cosmic-launcher cosmic-run; do
        if apt_pkg_exists "$launcher_candidate"; then
            launcher_pkg="$launcher_candidate"
            break
        fi
    done

    if [ -n "$launcher_pkg" ]; then
        cosmic_core+=("$launcher_pkg")
    else
        echo "${WARN} Neither cosmic-launcher nor cosmic-run found in apt cache." | tee -a "$LOG"
    fi

    for pkg in "${cosmic_core[@]}"; do
        if apt_pkg_exists "$pkg"; then
            installable+=("$pkg")
        else
            echo "${WARN} Package ${YELLOW}$pkg${RESET} is not available in apt for this system. Skipping." | tee -a "$LOG"
        fi
    done

    if [ ${#installable[@]} -eq 0 ]; then
        echo "${WARN} No COSMIC packages were available to install." | tee -a "$LOG"
        return
    fi

    echo "${INFO} Installing ${SKY_BLUE}COSMIC desktop components${RESET}..." | tee -a "$LOG"
    sudo apt install -y "${installable[@]}" 2>&1 | tee -a "$LOG"

    for unit in cosmic-panel.service cosmic-comp.service cosmic-bg.service cosmic-launcher.service cosmic-run.service; do
        if [ -f "/usr/lib/systemd/user/$unit" ] || [ -f "/lib/systemd/user/$unit" ] || [ -f "/etc/systemd/user/$unit" ]; then
            systemctl --user enable --now "$unit" 2>&1 | tee -a "$LOG" || true
        fi
    done
}

#################
## Default values for the options (will be overwritten by preset file if available)
gtk_themes="OFF"
bluetooth="OFF"
thunar="OFF"
ags="OFF"
quickshell="OFF"
sddm="OFF"
sddm_theme="OFF"
zsh="OFF"
pokemon="OFF"
rog="OFF"
dots="OFF"
input_group="OFF"
nvidia="OFF"

UPGRADE_MODE="${UPGRADE_MODE:-0}"
if [ -d "$HOME/.config/hypr" ] || [ -f "$HOME/.hyprland-install-marker" ]; then
    UPGRADE_MODE=1
fi
export UPGRADE_MODE

if [ "$UPGRADE_MODE" = "1" ]; then
    echo "${NOTE} Existing Hyprland configuration detected. Running in UPGRADE_MODE=1" | tee -a "$LOG"
fi

# Function to load preset file
load_preset() {
    if [ -f "$1" ]; then
        echo "✅ Loading preset: $1"
        source "$1"
    else
        echo "⚠️ Preset file not found: $1. Using default values."
    fi
}

# Check if --preset argument is passed
if [[ "$1" == "--preset" && -n "$2" ]]; then
    load_preset "$2"
fi

# List of services to check for active login managers
services=("gdm.service" "gdm3.service" "lightdm.service" "lxdm.service")

# Function to check if any login services are active
check_services_running() {
    active_services=() # Array to store active services
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc"; then
            active_services+=("$svc")
        fi
    done

    if [ ${#active_services[@]} -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

if check_services_running; then
    active_list=$(printf "%s\n" "${active_services[@]}")

    # Display the active login manager(s) in the whiptail message box
    whiptail --title "Active non-SDDM login manager(s) detected" \
        --msgbox "The following login manager(s) are active:\n\n$active_list\n\nIf you want to install SDDM and SDDM theme, stop and disable first the active services above, and reboot before running this script\nRefer to README on switching to SDDM if you really want SDDM\n\nNOTE: Your option to install SDDM and SDDM theme has now been removed\n\n- Ja " 28 80
fi

# Check if NVIDIA GPU is detected
nvidia_detected=false
if lspci | grep -i "nvidia" &>/dev/null; then
    nvidia_detected=true
    whiptail --title "NVIDIA GPU Detected" --msgbox "NVIDIA GPU detected in your system.\n\nNOTE: The script will install nvidia drivers via automatic detection if you chose to configure nvidia.\nSee the README" 14 60
fi

# Initialize the options array for whiptail checklist
options_command=(
    whiptail --title "Select Options" --checklist "Choose options to install or configure\nNOTE: 'SPACEBAR' to select & 'TAB' key to change selection" 28 85 20
)

# Add NVIDIA options if detected
if [ "$nvidia_detected" == "true" ]; then
    options_command+=(
        "nvidia" "Do you want script to configure NVIDIA GPU?" "OFF"
    )
fi

# Add 'input_group' option if user is not in input group
input_group_detected=false
if ! groups "$(whoami)" | grep -q '\binput\b'; then
    input_group_detected=true
    whiptail --title "Input Group" --msgbox "You are not currently in the input group.\n\nAdding you to the input group might be necessary for the Waybar keyboard-state functionality." 12 60
fi

# Add 'input_group' option if necessary
if [ "$input_group_detected" == "true" ]; then
    options_command+=(
        "input_group" "Add your USER to input group for some waybar functionality?" "OFF"
    )
fi

# Conditionally add SDDM and SDDM theme options if no active login manager is found
if [ "$UPGRADE_MODE" != "1" ] && ! check_services_running; then
    options_command+=(
        "sddm" "Install & configure SDDM login manager?" "OFF"
        "sddm_theme" "Download & Install Additional SDDM theme?" "OFF"
    )
fi

# Add the remaining static options
options_command+=(
    "gtk_themes" "Install GTK themes (required for Dark/Light function)" "OFF"
    "bluetooth" "Do you want script to configure Bluetooth?" "OFF"
    "thunar" "Do you want Thunar file manager to be installed?" "OFF"
    "ags" "Install AGS v1 for Desktop-Like Overview" "OFF"
    "quickshell" "Install Quickshell (QtQuick-based shell toolkit)?" "OFF"
    "zsh" "Install zsh shell with Oh-My-Zsh?" "OFF"
    "pokemon" "Add Pokemon color scripts to your terminal?" "OFF"
    "rog" "Are you installing on Asus ROG laptops?" "OFF"
    "dots" "Install KooL's Hyprland dotfiles?" "OFF"
)

# Capture the selected options before the while loop starts
while true; do
    selected_options=$("${options_command[@]}" 3>&1 1>&2 2>&3)

    # Check if the user pressed Cancel (exit status 1)
    if [ $? -ne 0 ]; then
        echo -e "\n"
        echo "❌ ${INFO} You 🫵 cancelled the selection. ${YELLOW}Goodbye!${RESET}" | tee -a "$LOG"
        exit 0 # Exit the script if Cancel is pressed
    fi

    # If no option was selected, notify and restart the selection
    if [ -z "$selected_options" ]; then
        whiptail --title "Warning" --msgbox "No options were selected. Please select at least one option." 10 60
        continue # Return to selection if no options selected
    fi

    # Strip the quotes and trim spaces if necessary (sanitize the input)
    selected_options=$(echo "$selected_options" | tr -d '"' | tr -s ' ')

    # Convert selected options into an array (preserving spaces in values)
    IFS=' ' read -r -a options <<<"$selected_options"

    # Check if the "dots" option was selected
    dots_selected="OFF"
    for option in "${options[@]}"; do
        if [[ "$option" == "dots" ]]; then
            dots_selected="ON"
            break
        fi
    done

    # If "dots" is not selected, show a note and ask the user to proceed or return to choices
    if [[ "$dots_selected" == "OFF" ]]; then
        # Show a note about not selecting the "dots" option
        if ! whiptail --title "KooL Hyprland Dot Files" --yesno \
            "You have not selected to install the pre-configured KooL Hyprland dotfiles.\n\nKindly NOTE that if you proceed without Dots, Hyprland will start with default vanilla Hyprland configuration and I won't be able to give you support.\n\nWould you like to continue install without KooL Hyprland Dots or return to choices/options?" \
            --yes-button "Continue" --no-button "Return" 15 90; then
            echo "🔙 Returning to options..." | tee -a "$LOG"
            continue
        else
            # User chose to continue
            echo "${INFO} ⚠️ Continuing WITHOUT the dotfiles installation..." | tee -a "$LOG"
            printf "\n%.0s" {1..1}
        fi
    fi

    # Prepare the confirmation message
    confirm_message="You have selected the following options:\n\n"
    for option in "${options[@]}"; do
        confirm_message+=" - $option\n"
    done
    confirm_message+="\nAre you happy with these choices?"

    # Confirmation prompt
    if ! whiptail --title "Confirm Your Choices" --yesno "$(printf "%s" "$confirm_message")" 25 80; then
        echo -e "\n"
        echo "❌ ${SKY_BLUE}You're not 🫵 happy${RESET}. ${YELLOW}Returning to options...${RESET}" | tee -a "$LOG"
        continue
    fi

    echo "👌 ${OK} You confirmed your choices. Proceeding with ${SKY_BLUE}KooL 🇵🇭 Hyprland Installation...${RESET}" | tee -a "$LOG"
    break
done

printf "\n%.0s" {1..1}

echo "${INFO} Running a ${SKY_BLUE}full system update...${RESET}" | tee -a "$LOG"
if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[DRY-RUN] sudo apt update" | tee -a "$LOG"
else
    sudo apt update
fi

if [ "$INSTALL_MODE" = "ppa" ] && [ "$OS_VERSION_ID" = "24.04" ]; then
    export HYPR_USE_PPA=1
    execute_script "hyprland-ppa-enable.sh"
fi

sleep 1
# execute pre clean up
execute_script "02-pre-cleanup.sh"

echo "${INFO} Installing ${SKY_BLUE}necessary dependencies...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "00-dependencies.sh" | tee -a "$LOG"

echo "${INFO} Installing ${SKY_BLUE}necessary fonts...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "fonts.sh"

echo "${INFO} Installing ${SKY_BLUE}KooL Hyprland packages...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "01-hypr-pkgs.sh"

# Install terminal stack and set alacritty as default terminal
sleep 1
install_terminal_stack
set_alacritty_default_terminal

# Build Hyprland from source branch 26.04
case "$INSTALL_MODE" in
  source)
    echo "${INFO} Building Hyprland from ${SKY_BLUE}source branch ${HYPRLAND_SOURCE_BRANCH}${RESET}..." | tee -a "$LOG"
    sleep 1
    build_hyprland_from_2604_branch
    ;;
  ppa)
    echo "${INFO} Installing Hyprland via ${SKY_BLUE}apt/PPA mode${RESET}..." | tee -a "$LOG"
    sleep 1
    export HYPR_USE_PPA=1
    execute_script "hyprland-ppa.sh"
    ;;
  *)
    echo "${ERROR} Unknown install mode: $INSTALL_MODE" | tee -a "$LOG"
    exit 1
    ;;
esac

# Rest of the desktop stack
sleep 1
execute_script "wallust.sh"
sleep 1
execute_script "swww.sh"
sleep 1
execute_script "hyprlock.sh"
sleep 1
execute_script "hypridle.sh"
sleep 1
install_cosmic_stack

#execute_script "imagemagick.sh" #this is for compiling from source. 07 Sep 2024
# execute_script "waybar-git.sh" only if waybar on repo is old

sleep 1
# Clean up the selected options (remove quotes and trim spaces)
selected_options=$(echo "$selected_options" | tr -d '"' | tr -s ' ')

# Convert selected options into an array (splitting by spaces)
IFS=' ' read -r -a options <<<"$selected_options"

# Loop through selected options
for option in "${options[@]}"; do
    case "$option" in
    sddm)
        if check_services_running; then
            active_list=$(printf "%s\n" "${active_services[@]}")
            whiptail --title "Error" --msgbox "One of the following login services is running:\n$active_list\n\nPlease stop & disable it or DO not choose SDDM." 12 60
            exec "$0"
        else
            echo "${INFO} Installing and configuring ${SKY_BLUE}SDDM...${RESET}" | tee -a "$LOG"
            execute_script "sddm.sh"
        fi
        ;;
    nvidia)
        echo "${INFO} Configuring ${SKY_BLUE}nvidia stuff${RESET}" | tee -a "$LOG"
        execute_script "nvidia.sh"
        ;;
    gtk_themes)
        echo "${INFO} Installing ${SKY_BLUE}GTK themes...${RESET}" | tee -a "$LOG"
        execute_script "gtk_themes.sh"
        ;;
    input_group)
        echo "${INFO} Adding user into ${SKY_BLUE}input group...${RESET}" | tee -a "$LOG"
        execute_script "InputGroup.sh"
        ;;
    ags)
        echo "${INFO} Installing ${SKY_BLUE}AGS v1 for Desktop Overview...${RESET}" | tee -a "$LOG"
        execute_script "ags.sh"
        ;;
    quickshell)
        echo "${INFO} Installing ${SKY_BLUE}Quickshell${RESET} (QtQuick-based shell toolkit)..." | tee -a "$LOG"
        execute_script "quickshell.sh"
        ;;
    bluetooth)
        echo "${INFO} Configuring ${SKY_BLUE}Bluetooth...${RESET}" | tee -a "$LOG"
        execute_script "bluetooth.sh"
        ;;
    thunar)
        echo "${INFO} Installing ${SKY_BLUE}Thunar file manager...${RESET}" | tee -a "$LOG"
        execute_script "thunar.sh"
        execute_script "thunar_default.sh"
        ;;
    sddm_theme)
        echo "${INFO} Downloading & Installing ${SKY_BLUE}Additional SDDM theme...${RESET}" | tee -a "$LOG"
        execute_script "sddm_theme.sh"
        ;;
    zsh)
        echo "${INFO} Installing ${SKY_BLUE}zsh with Oh-My-Zsh...${RESET}" | tee -a "$LOG"
        execute_script "zsh.sh"
        ;;
    pokemon)
        echo "${INFO} Adding ${SKY_BLUE}Pokemon color scripts to terminal...${RESET}" | tee -a "$LOG"
        execute_script "zsh_pokemon.sh"
        ;;
    rog)
        echo "${INFO} Installing ${SKY_BLUE}ROG laptop packages...${RESET}" | tee -a "$LOG"
        execute_script "rog.sh"
        ;;
    dots)
        echo "${INFO} Installing pre-configured ${SKY_BLUE}KooL Hyprland dotfiles...${RESET}" | tee -a "$LOG"
        execute_script "dotfiles-branch.sh"
        ;;
    *)
        echo "Unknown option: $option" | tee -a "$LOG"
        ;;
    esac
done

# Perform cleanup
printf "\n${OK} Performing some clean up.\n"
files_to_delete=("JetBrainsMono.tar.xz" "VictorMonoAll.zip" "FantasqueSansMono.zip")
for file in "${files_to_delete[@]}"; do
    if [ -e "$file" ]; then
        echo "$file found. Deleting..." | tee -a "$LOG"
        rm "$file"
        echo "$file deleted successfully." | tee -a "$LOG"
    fi
done

clear

# copy fastfetch config if ubuntu is not present
if [ ! -f "$HOME/.config/fastfetch/ubuntu.png" ]; then
    cp -r assets/fastfetch "$HOME/.config/"
fi

printf "\n%.0s" {1..2}
# final check essential packages if it is installed
execute_script "03-Final-Check.sh"

printf "\n%.0s" {1..1}

# Final verification: detect Hyprland from PATH or package
hypr_cmd=""
if command -v Hyprland >/dev/null 2>&1; then
    hypr_cmd="$(command -v Hyprland)"
elif command -v hyprland >/dev/null 2>&1; then
    hypr_cmd="$(command -v hyprland)"
elif dpkg -l | grep -qw hyprland; then
    # Fallback: deb package present even if binary not on PATH in this shell
    hypr_cmd="hyprland (dpkg)"
fi

if [ -n "$hypr_cmd" ]; then
    printf "\n ${OK} 👌 Hyprland detected at ${MAGENTA}%s${RESET}. However, some essential packages may not be installed. Please see above!" "$hypr_cmd"
    printf "\n${CAT} Ignore this message if it states ${YELLOW}All essential packages${RESET} are installed as per above\n"
    sleep 2
    printf "\n%.0s" {1..2}

    printf "${SKY_BLUE}Thank you${RESET} 🫰 for using 🇵🇭 ${MAGENTA}KooL's Hyprland Dots${RESET}. ${YELLOW}Enjoy and Have a good day!${RESET}"
    printf "\n%.0s" {1..2}

    printf "\n${NOTE} You can start Hyprland by typing ${SKY_BLUE}Hyprland${RESET} (IF SDDM is not installed)."
    if command -v hyprland >/dev/null 2>&1; then
        printf "\n${NOTE} Lowercase 'hyprland' wrapper is also available at ${SKY_BLUE}%s${RESET}.\n" "$(command -v hyprland)"
    else
        printf "\n"
    fi
    printf "\n${NOTE} Reboot or re-login, then choose the ${SKY_BLUE}COSMIC desktop${RESET} session to apply the changes.\n\n"

    while true; do
        echo -n "${CAT} Would you like to reboot now? (y/n): "
        read HYP
        HYP=$(echo "$HYP" | tr '[:upper:]' '[:lower:]')

        if [[ "$HYP" == "y" || "$HYP" == "yes" ]]; then
            echo "${INFO} Rebooting now..."
            systemctl reboot
            break
        elif [[ "$HYP" == "n" || "$HYP" == "no" ]]; then
            echo "👌 ${OK} You chose NOT to reboot"
            printf "\n%.0s" {1..1}
            # Check if NVIDIA GPU is present
            if lspci | grep -i "nvidia" &>/dev/null; then
                echo "${INFO} HOWEVER ${YELLOW}NVIDIA GPU${RESET} detected. Reminder that you must REBOOT your SYSTEM..."
                printf "\n%.0s" {1..1}
            fi
            break
        else
            echo "${WARN} Invalid response. Please answer with 'y' or 'n'."
        fi
    done
else
    # Print error message if neither package nor PATH binary is detected
    printf "\n${WARN} Hyprland is NOT detected. Please check 00_CHECK-time_installed.log and other files in the Install-Logs/ directory..."
    printf "\n%.0s" {1..3}
    exit 1
fi

printf "\n%.0s" {1..2}
