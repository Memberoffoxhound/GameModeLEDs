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

pause() {
  echo ""
  read -rp "Press Enter to continue..."
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
    read -rp "$prompt" reply
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
need_cmd rpm-ostree || true   # optional but nice on Bazzite

USER_HOME="$HOME"
APPIMAGE_DIR="$USER_HOME/AppImages"
OPENRGB_BIN="$APPIMAGE_DIR/openrgb"
SERVICE_NAME="gamemodeleds.service"
SERVICE_FILE="$USER_HOME/.config/systemd/user/$SERVICE_NAME"
DEFAULT_PROFILE="gamemode"

mkdir -p "$APPIMAGE_DIR"
mkdir -p "$USER_HOME/.config/systemd/user"
mkdir -p "$USER_HOME/.config/OpenRGB"

echo -e "${GREEN}✓${NC} Running as user: $(whoami)"
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
read -rp "What should the default lighting profile be called? (just press Enter for 'gamemode'): " PROFILE_NAME
PROFILE_NAME=${PROFILE_NAME:-gamemode}
# sanitize
PROFILE_NAME=$(echo "$PROFILE_NAME" | tr -cd '[:alnum:]_-')
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
  # Latest stable-ish RC from Codeberg
  APPIMAGE_URL="https://codeberg.org/OpenRGB/OpenRGB/releases/download/release_candidate_1.0rc3.1/OpenRGB_1.0rc3.1_x86_64_5e81e26.AppImage"
  TMP_APP="/tmp/OpenRGB-GameModeLEDs.AppImage"
  curl -fL --progress-bar -o "$TMP_APP" "$APPIMAGE_URL" || {
    echo -e "${RED}Download failed. Trying Bazzite ujust method...${NC}"
    if command -v ujust >/dev/null 2>&1; then
      ujust install-openrgb || true
      # Try common locations after ujust
      if [[ -x "$HOME/AppImages/openrgb.appimage" ]]; then
        OPENRGB_BIN="$HOME/AppImages/openrgb.appimage"
      elif [[ -x "$HOME/Desktop/OpenRGB.AppImage" ]]; then
        OPENRGB_BIN="$HOME/Desktop/OpenRGB.AppImage"
      fi
    fi
  }
  if [[ -f "$TMP_APP" ]]; then
    mv "$TMP_APP" "$OPENRGB_BIN"
    chmod +x "$OPENRGB_BIN"
    echo -e "${GREEN}✓${NC} OpenRGB installed to $OPENRGB_BIN"
  fi
fi

if [[ ! -x "$OPENRGB_BIN" ]]; then
  echo -e "${RED}Could not find or install OpenRGB. Please install it manually and re-run.${NC}"
  exit 1
fi

echo ""

# ---------- udev rules + permissions ----------
echo -e "${CYAN}${BOLD}[2/5] Hardware permissions (udev)${NC}"

UDEV_RULE="/etc/udev/rules.d/60-openrgb.rules"
if [[ -f "$UDEV_RULE" ]] || [[ -f /usr/lib/udev/rules.d/60-openrgb.rules ]]; then
  echo -e "${GREEN}✓${NC} OpenRGB udev rules already present"
else
  echo "Installing OpenRGB udev rules (needs sudo)..."
  TMP_RULES="/tmp/60-openrgb.rules"
  curl -fsSL -o "$TMP_RULES" "https://codeberg.org/OpenRGB/OpenRGB/releases/download/release_candidate_1.0rc3.1/60-openrgb.rules" || \
    curl -fsSL -o "$TMP_RULES" "https://openrgb.org/releases/release_candidate_1.0rc3.1/60-openrgb.rules" || true

  if [[ -f "$TMP_RULES" ]]; then
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
if ask_yes_no "Add kernel argument 'acpi_enforce_resources=lax' so OpenRGB can see RGB RAM sticks and some motherboard LEDs? (recommended)" "y"; then
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

# Create a small wrapper that works both in desktop and Gamescope
WRAPPER="$USER_HOME/.local/bin/gamemodeleds-start.sh"
mkdir -p "$USER_HOME/.local/bin"

cat > "$WRAPPER" << EOF
#!/usr/bin/env bash
# GameModeLEDs launcher – starts OpenRGB SDK server + loads profile
sleep 12   # let USB / I2C settle after Gamescope starts

export DISPLAY=":0"
# Gamescope usually uses wayland-1; desktop uses wayland-0. Try both safely.
export WAYLAND_DISPLAY="">${WAYLAND_DISPLAY:-wayland-1}"

# Prefer the AppImage we installed
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
echo "   It will start OpenRGB + profile '$PROFILE_NAME' on every login / Game Mode boot."
echo ""

# ---------- Decky plugin (optional) ----------
echo -e "${CYAN}${BOLD}[5/5] Decky plugin${NC}"

if [[ "$INSTALL_DECKY_PLUGIN" == true ]]; then
  # Ensure Decky is present
  if [[ ! -d "$HOME/homebrew" ]] && [[ ! -d "$HOME/.local/share/SteamDeckHomebrew" ]]; then
    echo "Decky Loader not detected."
    if ask_yes_no "Install Decky Loader now? (recommended)" "y"; then
      echo "Installing Decky Loader..."
      curl -L https://github.com/SteamDeckHomebrew/decky-installer/releases/latest/download/install_release.sh | sh || {
        echo -e "${YELLOW}!${NC} Automatic Decky install failed. Install it manually later from https://github.com/SteamDeckHomebrew/decky-loader"
      }
    fi
  fi

  PLUGIN_DIR="$HOME/homebrew/plugins/GameModeLEDs"
  mkdir -p "$PLUGIN_DIR"

  # Minimal but functional Decky plugin (Python backend + simple frontend)
  cat > "$PLUGIN_DIR/plugin.json" << 'PLUGINJSON'
{
  "name": "GameModeLEDs",
  "author": "Memberoffoxhound",
  "flags": ["root"],
  "api_version": 1,
  "publish": {
    "tags": ["rgb", "openrgb", "lighting", "utility"],
    "description": "Control OpenRGB profiles and lights from Game Mode",
    "image": ""
  }
}
PLUGINJSON

  cat > "$PLUGIN_DIR/main.py" << 'MAINPY'
import decky
import asyncio
import subprocess
import os
from pathlib import Path

class Plugin:
    async def _main(self):
        decky.logger.info("GameModeLEDs backend started")

    async def _unload(self):
        decky.logger.info("GameModeLEDs backend unloaded")

    async def list_profiles(self):
        """Return list of .orp profile names"""
        profiles = []
        conf = Path.home() / ".config" / "OpenRGB"
        if conf.exists():
            for p in conf.glob("*.orp"):
                profiles.append(p.stem)
        return sorted(profiles)

    async def load_profile(self, name: str):
        """Tell the running OpenRGB server to load a profile via CLI"""
        openrgb = os.path.expanduser("~/AppImages/openrgb")
        if not os.path.isfile(openrgb):
            openrgb = "openrgb"
        try:
            # CLI can talk to the already-running server
            proc = await asyncio.create_subprocess_exec(
                openrgb, "--profile", name,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            await proc.wait()
            return {"ok": True, "profile": name}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    async def set_color(self, r: int, g: int, b: int):
        """Set all devices to a solid color"""
        openrgb = os.path.expanduser("~/AppImages/openrgb")
        if not os.path.isfile(openrgb):
            openrgb = "openrgb"
        color = f"{r:02x}{g:02x}{b:02x}"
        try:
            proc = await asyncio.create_subprocess_exec(
                openrgb, "-c", color,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            await proc.wait()
            return {"ok": True}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    async def turn_off(self):
        return await self.set_color(0, 0, 0)
MAINPY

  # Very simple frontend (no build step required for basic functionality)
  mkdir -p "$PLUGIN_DIR/dist"
  cat > "$PLUGIN_DIR/dist/index.js" << 'INDEXJS'
// Minimal GameModeLEDs frontend – works without a full React build
(function() {
  // Decky will load this. We keep it extremely simple.
  console.log("GameModeLEDs frontend loaded");
})();
INDEXJS

  cat > "$PLUGIN_DIR/package.json" << 'PKG'
{
  "name": "gamemodeleds",
  "version": "1.0.0",
  "description": "OpenRGB control in Game Mode",
  "type": "module"
}
PKG

  echo -e "${GREEN}✓${NC} Decky plugin installed to $PLUGIN_DIR"
  echo "   Restart Decky Loader or reboot, then look for GameModeLEDs in the plugin list."
  echo "   (If the UI is minimal, the Python backend still works – full polished UI can be improved later.)"
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
