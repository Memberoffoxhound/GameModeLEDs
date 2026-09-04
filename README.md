# GameModeLEDs

**One-stop RGB control for Bazzite Game Mode (and homemade Steam Machines).**

Control your case lights, RAM LEDs, motherboard ARGB, keyboards, mice, and every other OpenRGB-supported device **while staying in Game Mode**. Profiles load automatically at boot into Gamescope. Optional Decky plugin puts the controls right in the Quick Access Menu.

Grandma-friendly. One script. Sudo only when needed.

## What this does

- Installs the latest OpenRGB AppImage if you don't have it
- Sets up proper permissions (udev rules) so OpenRGB can talk to your hardware (including addressable RAM)
- Creates a systemd user service that starts the OpenRGB **SDK server** and loads your preferred lighting profile every time you boot into Game Mode
- Optionally installs a Decky Loader plugin so you can change profiles / colors / brightness from the Steam Quick Access Menu without ever leaving Game Mode
- All the bells and whistles of OpenRGB (profiles, direct mode, effects plugins, etc.) work under the hood

## Quick Install (copy-paste)

Open a terminal in Desktop Mode and run:

```bash
curl -fsSL https://raw.githubusercontent.com/Memberoffoxhound/GameModeLEDs/main/install.sh | bash
```

Or download and run it yourself:

```bash
curl -fsSL https://raw.githubusercontent.com/Memberoffoxhound/GameModeLEDs/main/install.sh -o install.sh
chmod +x install.sh
./install.sh
```

The script will:
1. Explain what it is doing
2. Ask if you want the Decky plugin (recommended)
3. Handle sudo for permissions and any system changes
4. Set everything up so RGB works the moment you enter Game Mode

After install, reboot into Game Mode. Your lights should come on with the profile you chose.

## First-time profile setup

1. Switch to Desktop Mode
2. Launch OpenRGB (it will be in your Applications menu or `~/AppImages/openrgb`)
3. Set your colors / effects however you like
4. Click **Save Profile** and name it something simple (example: `gamemode` or `purple`)
5. The installer will have asked you for a default profile name — use the same one

You can create as many profiles as you want later and switch them from the Decky plugin (if installed) or by editing the service.

## Requirements

- Bazzite (especially bazzite-deck) or any modern Fedora Atomic / SteamOS-like system with Gamescope
- x86_64
- Internet for the initial download

## Optional Decky plugin

If you said yes during install, a plugin called **GameModeLEDs** appears in Decky Loader.

From the Quick Access Menu it lets you:
- Load any saved OpenRGB profile
- Set common colors
- Turn lights off

(Decky must already be installed or the installer will offer to set it up.)

## Uninstall

```bash
systemctl --user disable --now gamemodeleds.service
rm -f ~/.config/systemd/user/gamemodeleds.service
# Optional: remove the AppImage and Decky plugin manually
```

## Credits

Built on the excellent [OpenRGB](https://openrgb.org) project.  
Designed for the Bazzite / Universal Blue community and homemade Steam Machines.

MIT License.
