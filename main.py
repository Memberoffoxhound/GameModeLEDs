import asyncio
import json
import os
import re
import urllib.request
from collections import Counter
from pathlib import Path

import decky


def _user_home() -> Path:
    env = os.environ.get("DECKY_USER_HOME") or os.environ.get("HOME")
    if env:
        return Path(env)
    for name in ("bazzite", "deck"):
        p = Path("/home") / name
        if p.is_dir():
            return p
    return Path.home()


def _settings_path() -> Path:
    env = os.environ.get("DECKY_PLUGIN_SETTINGS_DIR")
    if env:
        p = Path(env)
    else:
        p = _user_home() / "homebrew" / "settings" / "GameModeLEDs"
    p.mkdir(parents=True, exist_ok=True)
    return p / "settings.json"


def _openrgb_dir() -> Path:
    return _user_home() / ".config" / "OpenRGB"


def _slug(name: str) -> str:
    s = re.sub(r"[^A-Za-z0-9]+", "_", (name or "").strip()).strip("_")
    return s[:48] or "game"


class Plugin:
    def __init__(self):
        self._last_key = None
        self._lock = asyncio.Lock()

    async def _main(self):
        decky.logger.info("GameModeLEDs backend started (home=%s)", _user_home())
        await self.ensure_server()

    async def _unload(self):
        decky.logger.info("GameModeLEDs backend unloaded")

    def _load_settings(self) -> dict:
        path = _settings_path()
        data = {
            "auto": True,
            "idle_profile": "Blue",
            "games": {},
        }
        try:
            if path.is_file():
                data.update(json.loads(path.read_text()))
        except Exception as e:
            decky.logger.warning("settings read: %s", e)
        if "games" not in data or not isinstance(data["games"], dict):
            data["games"] = {}
        return data

    def _save_settings(self, data: dict) -> None:
        try:
            _settings_path().write_text(json.dumps(data, indent=2))
        except Exception as e:
            decky.logger.warning("settings write: %s", e)

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

    def _list_profile_names(self):
        names = []
        conf = _openrgb_dir()
        if conf.is_dir():
            for p in sorted(conf.glob("*.orp")):
                names.append(p.stem)
        return names

    async def list_profiles(self):
        return self._list_profile_names()

    async def list_devices(self):
        r = await self._run("-l", "--noautoconnect", "--loglevel", "error", timeout=30)
        if not r.get("ok"):
            return r
        lines = [ln.strip() for ln in (r.get("stdout") or "").splitlines() if ln.strip()]
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
        return await self._run("-c", color, "--loglevel", "error")

    async def turn_off(self):
        return await self.set_color(0, 0, 0)

    async def ensure_server(self):
        if await self._server_up():
            return {"ok": True, "running": True}
        openrgb = self._find_openrgb()
        settings = self._load_settings()
        profile = settings.get("idle_profile") or "Blue"
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

    async def _server_up(self) -> bool:
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection("127.0.0.1", 6742), timeout=0.4
            )
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass
            return True
        except Exception:
            return False

    def _match_profile(self, name: str, appid, profiles):
        cands = []
        if appid not in (None, "", 0):
            cands += [str(appid), f"GMC-{appid}", f"app{appid}"]
        if name:
            slug = _slug(name)
            cands += [name, slug, f"GMC-{slug}", slug.replace("_", "")]
        lower = {p.lower(): p for p in profiles}
        for c in cands:
            if c and c.lower() in lower:
                return lower[c.lower()]
        return None

    def _find_local_art(self, appid: int):
        home = _user_home()
        roots = [
            home / ".local" / "share" / "Steam" / "appcache" / "librarycache" / str(appid),
            home / ".steam" / "steam" / "appcache" / "librarycache" / str(appid),
        ]
        best = None
        best_size = 0
        for root in roots:
            if not root.is_dir():
                continue
            for p in root.rglob("*"):
                if p.suffix.lower() not in (".jpg", ".jpeg", ".png"):
                    continue
                try:
                    sz = p.stat().st_size
                except OSError:
                    continue
                # Skip tiny icons (32x32 hashes are ~800 bytes)
                if sz < 20_000 or sz > 4_000_000:
                    continue
                if sz > best_size:
                    best, best_size = p, sz
        return str(best) if best else None

    async def _download_header(self, appid: int) -> str | None:
        cache = _user_home() / "homebrew" / "data" / "GameModeLEDs"
        cache.mkdir(parents=True, exist_ok=True)
        dest = cache / f"{appid}-header.jpg"
        if dest.is_file() and dest.stat().st_size > 5000:
            return str(dest)
        urls = [
            f"https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/library_600x900.jpg",
            f"https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/{appid}/library_600x900.jpg",
            f"https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/header.jpg",
            f"https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/{appid}/header.jpg",
        ]

        def fetch():
            for url in urls:
                try:
                    req = urllib.request.Request(url, headers={"User-Agent": "GameModeLEDs"})
                    with urllib.request.urlopen(req, timeout=8) as resp:
                        data = resp.read()
                    if data and len(data) > 5000:
                        dest.write_bytes(data)
                        return str(dest)
                except Exception:
                    continue
            return None

        return await asyncio.to_thread(fetch)

    def _color_from_pixels(self, raw: bytes, n: int):
        if n < 16:
            return None
        buckets: Counter = Counter()
        for i in range(0, n * 3, 3):
            r, g, b = raw[i], raw[i + 1], raw[i + 2]
            mx, mn = max(r, g, b), min(r, g, b)
            if mx < 50:
                continue
            if mn > 235:
                continue
            sat = (mx - mn) / mx if mx else 0
            if sat < 0.18:
                continue
            buckets[(r >> 4, g >> 4, b >> 4)] += 1
        if not buckets:
            # fallback: brightest non-black
            br = (40, 80, 200)
            score = -1
            for i in range(0, n * 3, 3):
                r, g, b = raw[i], raw[i + 1], raw[i + 2]
                s = r + g + b
                if 80 < s < 720 and s > score:
                    score = s
                    br = (r, g, b)
            return br
        best = None
        best_s = -1.0
        for (rq, gq, bq), count in buckets.items():
            r, g, b = rq * 16 + 8, gq * 16 + 8, bq * 16 + 8
            mx = max(r, g, b)
            sat = (mx - min(r, g, b)) / mx
            val = mx / 255.0
            s = (sat ** 2) * val * (count ** 0.45)
            if s > best_s:
                best_s = s
                best = (r, g, b)
        if not best:
            return None
        r, g, b = best
        # Punch up dim colors so RAM LEDs actually show them
        mx = max(r, g, b)
        if mx < 180 and mx > 0:
            k = 180 / mx
            r, g, b = min(255, int(r * k)), min(255, int(g * k)), min(255, int(b * k))
        return (r, g, b)

    async def _extract_color(self, path: str):
        def via_ffmpeg():
            import subprocess
            p = subprocess.run(
                [
                    "ffmpeg", "-v", "error", "-i", path,
                    "-vf", "scale=48:48:flags=area",
                    "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
                ],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=12,
            )
            raw = p.stdout or b""
            n = len(raw) // 3
            return self._color_from_pixels(raw, n)

        def via_pillow():
            from PIL import Image
            im = Image.open(path).convert("RGB")
            im.thumbnail((48, 48))
            raw = im.tobytes()
            return self._color_from_pixels(raw, im.size[0] * im.size[1])

        color = None
        try:
            color = await asyncio.to_thread(via_ffmpeg)
        except Exception as e:
            decky.logger.info("ffmpeg color: %s", e)
        if color is None:
            try:
                color = await asyncio.to_thread(via_pillow)
            except Exception as e:
                decky.logger.info("pillow color: %s", e)
        return color

    async def _create_profile(self, name: str, r: int, g: int, b: int):
        """Apply art color, then save a new OpenRGB profile for this game."""
        color = f"{int(r):02x}{int(g):02x}{int(b):02x}"
        safe = _slug(name)
        # OpenRGB appends .orp itself if missing; passing .orp created *.orp.orp
        fname = f"GMC-{safe}"
        r1 = await self._run(
            "-c", color,
            "--save-profile", fname,
            "--loglevel", "error",
        )
        if not r1.get("ok"):
            # Some OpenRGB builds want color then a second save
            r2 = await self.set_color(r, g, b)
            if not r2.get("ok"):
                return r2
            r1 = await self._run("--save-profile", fname, "--loglevel", "error")
        if r1.get("ok"):
            r1["profile"] = Path(fname).stem
            r1["created"] = True
            r1["r"], r1["g"], r1["b"] = int(r), int(g), int(b)
        return r1

    async def sync_game(self, appid=None, name: str = ""):
        """Follow the running Steam app: load or create an OpenRGB profile
        from its artwork color."""
        settings = self._load_settings()
        if not settings.get("auto", True):
            return {"ok": True, "skipped": True, "reason": "auto off"}

        key = str(appid) if appid not in (None, "", 0) else (name or "")
        idle = not key
        async with self._lock:
            if key == (self._last_key or "") and not idle:
                return {"ok": True, "unchanged": True}
            if idle:
                self._last_key = ""
                idle_prof = settings.get("idle_profile") or "Blue"
                profiles = self._list_profile_names()
                if idle_prof in profiles:
                    r = await self.load_profile(idle_prof)
                    r["game"] = None
                    r["reason"] = "idle"
                    return r
                return {"ok": True, "game": None, "reason": "idle-noprofile"}

            self._last_key = key
            profiles = self._list_profile_names()
            existing = self._match_profile(name or "", appid, profiles)
            cached = settings.get("games", {}).get(key) or {}
            if not existing and cached.get("profile") in profiles:
                existing = cached["profile"]

            if existing:
                r = await self.load_profile(existing)
                r["game"] = name
                r["appid"] = appid
                r["source"] = "profile"
                return r

            art = None
            if appid not in (None, "", 0):
                art = self._find_local_art(int(appid))
                if not art:
                    art = await self._download_header(int(appid))
            color = None
            if art:
                color = await self._extract_color(art)
            if not color:
                color = (0, 80, 255)
            r, g, b = color
            prof_label = f"GMC-{_slug(name or key)}"
            created = await self._create_profile(name or key, r, g, b)
            settings.setdefault("games", {})[key] = {
                "name": name,
                "profile": created.get("profile") or prof_label,
                "r": r, "g": g, "b": b,
            }
            self._save_settings(settings)
            created["game"] = name
            created["appid"] = appid
            created["source"] = "art"
            created["r"], created["g"], created["b"] = r, g, b
            return created

    async def set_auto(self, enabled: bool):
        data = self._load_settings()
        data["auto"] = bool(enabled)
        self._save_settings(data)
        if not enabled:
            self._last_key = None
        return {"ok": True, "auto": bool(enabled)}

    async def set_idle_profile(self, name: str):
        data = self._load_settings()
        data["idle_profile"] = name or ""
        self._save_settings(data)
        return {"ok": True, "idle_profile": data["idle_profile"]}

    async def status(self):
        home = str(_user_home())
        bin_path = self._find_openrgb()
        profiles = self._list_profile_names()
        settings = self._load_settings()
        return {
            "ok": True,
            "home": home,
            "openrgb": bin_path,
            "server": await self._server_up(),
            "profiles": profiles,
            "auto": bool(settings.get("auto", True)),
            "idle_profile": settings.get("idle_profile") or "Blue",
            "games": settings.get("games") or {},
        }
