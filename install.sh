#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# GameModeLEDs - One-stop OpenRGB for Bazzite Game Mode
# https://github.com/Memberoffoxhound/GameModeLEDs
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${CYAN}${BOLD}"
echo "  ██████╗  █████╗ ███╗   ███╗███████╗███╗   ███╗ ██████╗ ██████╗ ███████╗"
echo " ██╔════╝ ██╔══██╗████╗ ████║██╔════╝████╗ ████║██╔═══██╗██╔══██╗██╔════╝"
echo " ██║  ███╗███████║██╔████╔██║█████╗  ██╔████╔██║██║   ██║██║  ██║█████╗  "
echo " ██║   ██║██╔══██║██║╚██╔╝██║██╔══╝  ██║╚██╔╝██║██║   ██║██║  ██║██╔══╝  "
echo " ╚██████╔╝██║  ██║██║ ╚═╝ ██║███████╗██║ ╚═╝ ██║╚██████╔╝██████╔╝███████╗"
echo "  ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚═╝     ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝"
echo -e "${NC}"
echo -e "${BOLD}GameModeLEDs${NC} — RGB control that actually works in Steam Game Mode"
echo ""
echo -e "This installer will:"
echo "  • Download & install the latest OpenRGB AppImage (if needed)"
echo "  • Give OpenRGB permission to control case lights, RAM LEDs, peripherals"
echo "  • Create a service that starts OpenRGB + your lighting profile"
echo "    automatically every time you boot into Game Mode"
echo "  • Optionally install a Decky plugin so you can change lights"
echo "    from the Quick Access Menu without leaving Game Mode"
echo ""
echo -e "${YELLOW}You will be asked for your password when sudo is required.${NC}"
echo ""

# ---------- helpers ----------
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo -e "${RED}Missing required command: $1${NC}"; exit 1; }
}

ask_yes_no() {
  local prompt="$1"
  local default="${2:-y}"
  local reply
  if [[ "$default" == "y" ]]; then
    prompt+=" [Y/n] "
  else
    prompt+=" [y/N] "
  fi
  while true; do
    # Print prompt on its own line for clarity on small terminals
    echo -en "${prompt}"
    read -r reply
    reply=${reply:-$default}
    case "${reply,,}" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

# ---------- preflight ----------
need_cmd curl
need_cmd systemctl

USER_HOME="$HOME"
APPIMAGE_DIR="$USER_HOME/AppImages"
OPENRGB_BIN="$APPIMAGE_DIR/openrgb"
SERVICE_NAME="gamemodeleds.service"
SERVICE_FILE="$USER_HOME/.config/systemd/user/$SERVICE_NAME"

mkdir -p "$APPIMAGE_DIR"
mkdir -p "$USER_HOME/.config/systemd/user"
mkdir -p "$USER_HOME/.config/OpenRGB"
mkdir -p "$USER_HOME/.local/bin"

echo -e "${GREEN}✓${NC} Running as user: $(whoami)  (HOME=$USER_HOME)"
echo ""

# ---------- Decky prompt (up front) ----------
INSTALL_DECKY_PLUGIN=false
if ask_yes_no "Do you want the Decky Loader plugin so you can control RGB from the Quick Access Menu in Game Mode?" "y"; then
  INSTALL_DECKY_PLUGIN=true
  echo -e "${GREEN}→${NC} Decky plugin will be installed."
else
  echo -e "${YELLOW}→${NC} Skipping Decky plugin. You can still control everything via profiles and the OpenRGB server."
fi
echo ""

# ---------- Profile name ----------
echo -n "What should the default lighting profile be called? (just press Enter for 'gamemode'): "
read -r PROFILE_NAME
PROFILE_NAME=${PROFILE_NAME:-gamemode}
# sanitize: only keep safe characters
PROFILE_NAME=$(echo "$PROFILE_NAME" | tr -cd '[:alnum:]_-')
if [[ -z "$PROFILE_NAME" ]]; then
  PROFILE_NAME="gamemode"
fi
echo -e "${GREEN}→${NC} Default profile will be: ${BOLD}$PROFILE_NAME${NC}"
echo ""

# ---------- Install / locate OpenRGB ----------
echo -e "${CYAN}${BOLD}[1/5] OpenRGB${NC}"

if [[ -x "$OPENRGB_BIN" ]]; then
  echo -e "${GREEN}✓${NC} OpenRGB AppImage already present at $OPENRGB_BIN"
elif command -v openrgb >/dev/null 2>&1; then
  OPENRGB_BIN=$(command -v openrgb)
  echo -e "${GREEN}✓${NC} Found system OpenRGB at $OPENRGB_BIN"
else
  echo "Downloading latest OpenRGB AppImage (x86_64)..."
  APPIMAGE_URL="https://codeberg.org/OpenRGB/OpenRGB/releases/download/release_candidate_1.0rc3.1/OpenRGB_1.0rc3.1_x86_64_5e81e26.AppImage"
  TMP_APP="/tmp/OpenRGB-GameModeLEDs.AppImage"
  if curl -fL --progress-bar -o "$TMP_APP" "$APPIMAGE_URL"; then
    mv "$TMP_APP" "$OPENRGB_BIN"
    chmod +x "$OPENRGB_BIN"
    echo -e "${GREEN}✓${NC} OpenRGB installed to $OPENRGB_BIN"
  else
    echo -e "${YELLOW}Download failed. Trying Bazzite ujust method...${NC}"
    if command -v ujust >/dev/null 2>&1; then
      ujust install-openrgb || true
      if [[ -x "$USER_HOME/AppImages/openrgb.appimage" ]]; then
        OPENRGB_BIN="$USER_HOME/AppImages/openrgb.appimage"
      elif [[ -x "$USER_HOME/Desktop/OpenRGB.AppImage" ]]; then
        OPENRGB_BIN="$USER_HOME/Desktop/OpenRGB.AppImage"
      elif [[ -x "$USER_HOME/AppImages/OpenRGB.AppImage" ]]; then
        OPENRGB_BIN="$USER_HOME/AppImages/OpenRGB.AppImage"
      fi
    fi
  fi
fi

if [[ ! -x "$OPENRGB_BIN" ]]; then
  echo -e "${RED}Could not find or install OpenRGB. Please install it manually (ujust install-openrgb) and re-run.${NC}"
  exit 1
fi

echo ""

# ---------- udev rules + permissions ----------
echo -e "${CYAN}${BOLD}[2/5] Hardware permissions (udev)${NC}"

if [[ -f /etc/udev/rules.d/60-openrgb.rules ]] || [[ -f /usr/lib/udev/rules.d/60-openrgb.rules ]]; then
  echo -e "${GREEN}✓${NC} OpenRGB udev rules already present"
else
  echo "Installing OpenRGB udev rules (needs sudo)..."
  TMP_RULES="/tmp/60-openrgb.rules"
  if curl -fsSL -o "$TMP_RULES" "https://codeberg.org/OpenRGB/OpenRGB/releases/download/release_candidate_1.0rc3.1/60-openrgb.rules"; then
    sudo cp "$TMP_RULES" /etc/udev/rules.d/60-openrgb.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    echo -e "${GREEN}✓${NC} udev rules installed"
  else
    echo -e "${YELLOW}!${NC} Could not download udev rules. OpenRGB may still work if Bazzite already ships them."
  fi
fi

echo ""

# ---------- Optional kernel arg for RAM / SMBus ----------
echo -e "${CYAN}${BOLD}[3/5] Addressable RAM / motherboard SMBus support${NC}"
echo "This adds the kernel argument 'acpi_enforce_resources=lax' so OpenRGB can"
echo "detect RGB RAM sticks and certain motherboard LEDs. A reboot is required"
echo "after this step for the change to take effect."
echo ""
if ask_yes_no "Add the kernel argument now? (recommended)" "y"; then
  if command -v rpm-ostree >/dev/null 2>&1; then
    if rpm-ostree kargs | grep -q 'acpi_enforce_resources=lax'; then
      echo -e "${GREEN}✓${NC} Kernel argument already present"
    else
      echo "Adding kernel argument (needs sudo + reboot later)..."
      sudo rpm-ostree kargs --append=acpi_enforce_resources=lax
      echo -e "${GREEN}✓${NC} Kernel argument added. You must reboot for RAM LEDs to appear."
    fi
  else
    echo -e "${YELLOW}!${NC} Not on rpm-ostree. You may need to add acpi_enforce_resources=lax manually to your bootloader."
  fi
else
  echo "Skipped. RAM RGB may not be detected until you add the argument yourself."
fi
echo ""

# ---------- systemd user service ----------
echo -e "${CYAN}${BOLD}[4/5] Game Mode auto-start service${NC}"

WRAPPER="$USER_HOME/.local/bin/gamemodeleds-start.sh"

cat > "$WRAPPER" << EOF
#!/usr/bin/env bash
# GameModeLEDs launcher – starts OpenRGB SDK server + loads profile
sleep 12   # let USB / I2C settle after Gamescope starts

export DISPLAY=":0"
# Gamescope usually uses wayland-1; desktop uses wayland-0
export WAYLAND_DISPLAY="\${WAYLAND_DISPLAY:-wayland-1}"

OPENRGB="$OPENRGB_BIN"

if [[ ! -x "\$OPENRGB" ]]; then
  OPENRGB=\$(command -v openrgb || true)
fi

if [[ -z "\$OPENRGB" || ! -x "\$OPENRGB" ]]; then
  echo "GameModeLEDs: OpenRGB binary not found" >&2
  exit 1
fi

# Start server and load profile (headless)
exec "\$OPENRGB" --server --profile "$PROFILE_NAME" --loglevel error
EOF

chmod +x "$WRAPPER"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=GameModeLEDs – OpenRGB server + profile for Game Mode
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
ExecStart=$WRAPPER
Restart=on-failure
RestartSec=5
Environment=HOME=$USER_HOME

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE_NAME" || true

echo -e "${GREEN}✓${NC} Service installed and enabled: $SERVICE_NAME"
echo "   It will start OpenRGB + profile '${PROFILE_NAME}' on every login / Game Mode boot."
echo ""

# ---------- Decky plugin (optional) ----------
echo -e "${CYAN}${BOLD}[5/5] Decky plugin${NC}"

if [[ "$INSTALL_DECKY_PLUGIN" == true ]]; then
  if [[ ! -d "$USER_HOME/homebrew" ]] && [[ ! -d "$USER_HOME/.local/share/SteamDeckHomebrew" ]]; then
    echo "Decky Loader not detected."
    if ask_yes_no "Install Decky Loader now? (recommended)" "y"; then
      echo "Installing Decky Loader..."
      curl -L https://github.com/SteamDeckHomebrew/decky-installer/releases/latest/download/install_release.sh | sh || {
        echo -e "${YELLOW}!${NC} Automatic Decky install failed. Install it manually later from https://github.com/SteamDeckHomebrew/decky-loader"
      }
    fi
  fi

  PLUGIN_DIR="$USER_HOME/homebrew/plugins/GameModeLEDs"

  # --- Robust directory creation (fixes the common "Permission denied" on Bazzite) ---
  if [[ -d "$USER_HOME/homebrew" ]] && [[ ! -w "$USER_HOME/homebrew" ]]; then
    echo -e "${YELLOW}!${NC} ~/homebrew exists but is not writable (often left owned by root)."
    echo "   Fixing ownership (needs sudo)..."
    if sudo chown -R "$USER:$USER" "$USER_HOME/homebrew"; then
      echo -e "${GREEN}✓${NC} Ownership fixed"
    else
      echo -e "${RED}Failed to fix permissions on ~/homebrew.${NC}"
      echo "Please run this command yourself, then re-run the installer:"
      echo "  sudo chown -R \$USER:\$USER ~/homebrew"
      exit 1
    fi
  fi

  if ! mkdir -p "$PLUGIN_DIR/dist" 2>/dev/null; then
    echo -e "${YELLOW}!${NC} Could not create plugin directory as user. Trying with sudo + chown..."
    sudo mkdir -p "$PLUGIN_DIR/dist"
    sudo chown -R "$USER:$USER" "$USER_HOME/homebrew"
    if [[ ! -w "$PLUGIN_DIR" ]]; then
      echo -e "${RED}Still cannot write to $PLUGIN_DIR${NC}"
      echo "Please run:  sudo chown -R \$USER:\$USER ~/homebrew"
      exit 1
    fi
  fi

  BASE_URL="https://raw.githubusercontent.com/Memberoffoxhound/GameModeLEDs/main"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || true)"
  copy_plugin_file() {
    local rel="$1" dest="$2"
    if [[ -n "${SCRIPT_DIR:-}" && -f "$SCRIPT_DIR/$rel" ]]; then
      cp -a "$SCRIPT_DIR/$rel" "$dest"
    else
      curl -fsSL "$BASE_URL/$rel" -o "$dest"
    fi
  }
  mkdir -p "$PLUGIN_DIR/dist"
  copy_plugin_file plugin.json "$PLUGIN_DIR/plugin.json"
  copy_plugin_file main.py "$PLUGIN_DIR/main.py"
  copy_plugin_file package.json "$PLUGIN_DIR/package.json"
  copy_plugin_file dist/index.js "$PLUGIN_DIR/dist/index.js"
  [[ -s "$PLUGIN_DIR/dist/index.js" ]] || { echo -e "${RED}Failed to install QAM frontend (dist/index.js)${NC}"; exit 1; }
  [[ -s "$PLUGIN_DIR/main.py" ]] || { echo -e "${RED}Failed to install plugin backend (main.py)${NC}"; exit 1; }

  echo -e "${GREEN}✓${NC} Decky plugin installed to $PLUGIN_DIR"
  echo "   Restart Decky Loader or reopen the QAM, then open GameModeLEDs to change colors and profiles."
else
  echo "Skipped Decky plugin."
fi

echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  Installation complete!${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════${NC}"
echo ""
echo "Next steps:"
echo "  1. Switch to Desktop Mode and open OpenRGB."
echo "  2. Configure your lights exactly how you want them."
echo "  3. Save a profile named: ${BOLD}$PROFILE_NAME${NC}"
echo "  4. Reboot (or just switch back to Game Mode)."
echo ""
echo "Your RGB should now light up automatically in Game Mode"
echo "with the profile you saved. The OpenRGB SDK server is"
echo "running so tools and the optional Decky plugin can talk to it."
echo ""
if [[ "$INSTALL_DECKY_PLUGIN" == true ]]; then
  echo "In Game Mode open the Quick Access Menu → Decky → GameModeLEDs"
  echo "to switch profiles or change colors."
fi
echo ""
echo -e "Questions / issues: ${CYAN}https://github.com/Memberoffoxhound/GameModeLEDs${NC}"
echo ""

if ask_yes_no "Reboot now so the kernel argument (if added) and service take full effect?" "n"; then
  echo "Rebooting..."
  systemctl reboot
fi

echo "Done. Enjoy your lights."
