import asyncio
import os
from pathlib import Path

import decky


def _user_home() -> Path:
    env = os.environ.get("DECKY_USER_HOME") or os.environ.get("HOME")
    if env:
        return Path(env)
    # Plugin used to ship flags:["root"], which made Path.home() == /root
    # and OpenRGB/profiles disappeared. Always prefer the logged-in user.
    for name in ("bazzite", "deck"):
        p = Path("/home") / name
        if p.is_dir():
            return p
    return Path.home()


class Plugin:
    async def _main(self):
        decky.logger.info("GameModeLEDs backend started (home=%s)", _user_home())
        await self.ensure_server()

    async def _unload(self):
        decky.logger.info("GameModeLEDs backend unloaded")

    def _find_openrgb(self) -> str:
        home = _user_home()
        for c in (
            home / "AppImages" / "openrgb",
            home / "AppImages" / "openrgb.appimage",
            home / "AppImages" / "OpenRGB.AppImage",
        ):
            if c.is_file() and os.access(c, os.X_OK):
                return str(c)
        return "openrgb"

    async def _run(self, *args: str, timeout: float = 25.0):
        openrgb = self._find_openrgb()
        cmd = [openrgb, *args]
        decky.logger.info("openrgb %s", " ".join(args))
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
        except FileNotFoundError:
            return {"ok": False, "error": f"OpenRGB not found ({openrgb})"}
        try:
            out_b, err_b = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        except asyncio.TimeoutError:
            try:
                proc.kill()
            except Exception:
                pass
            return {"ok": False, "error": "OpenRGB timed out"}
        out = (out_b or b"").decode(errors="replace").strip()
        err = (err_b or b"").decode(errors="replace").strip()
        if proc.returncode != 0:
            msg = err or out or f"exit {proc.returncode}"
            decky.logger.warning("openrgb failed: %s", msg)
            return {"ok": False, "error": msg, "code": proc.returncode}
        return {"ok": True, "stdout": out}

    async def list_profiles(self):
        conf = _user_home() / ".config" / "OpenRGB"
        names = []
        if conf.is_dir():
            for p in sorted(conf.glob("*.orp")):
                names.append(p.stem)
        return names

    async def list_devices(self):
        r = await self._run("-l", "--noautoconnect", "--loglevel", "error", timeout=30)
        if not r.get("ok"):
            return r
        lines = []
        for line in (r.get("stdout") or "").splitlines():
            s = line.strip()
            if s:
                lines.append(s)
        return {"ok": True, "devices": lines[:80]}

    async def load_profile(self, name: str):
        if not name:
            return {"ok": False, "error": "no profile name"}
        r = await self._run("--profile", name, "--loglevel", "error")
        if r.get("ok"):
            r["profile"] = name
        return r

    async def set_color(self, r: int, g: int, b: int):
        color = f"{int(r):02x}{int(g):02x}{int(b):02x}"
        # No --mode: RAM sticks here only support Direct, not Static.
        return await self._run("-c", color, "--loglevel", "error")

    async def turn_off(self):
        return await self.set_color(0, 0, 0)

    async def ensure_server(self):
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection("127.0.0.1", 6742), timeout=0.4
            )
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass
            return {"ok": True, "running": True}
        except Exception:
            pass
        openrgb = self._find_openrgb()
        profile = "Blue"
        try:
            await asyncio.create_subprocess_exec(
                openrgb, "--server", "--profile", profile, "--loglevel", "error",
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
        except Exception as e:
            return {"ok": False, "error": str(e)}
        await asyncio.sleep(1.5)
        return {"ok": True, "running": False, "started": True}

    async def status(self):
        home = str(_user_home())
        bin_path = self._find_openrgb()
        profiles = await self.list_profiles()
        server = False
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection("127.0.0.1", 6742), timeout=0.4
            )
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass
            server = True
        except Exception:
            server = False
        return {
            "ok": True,
            "home": home,
            "openrgb": bin_path,
            "server": server,
            "profiles": profiles,
        }
