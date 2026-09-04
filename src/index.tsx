import {
  definePlugin,
  PanelSection,
  PanelSectionRow,
  ButtonItem,
  DropdownItem,
  ToggleField,
  Router,
  staticClasses,
} from "@decky/ui";
import { call } from "@decky/api";
import { useEffect, useState } from "react";
import { FaLightbulb } from "react-icons/fa";

type Status = {
  ok: boolean;
  home?: string;
  openrgb?: string;
  server?: boolean;
  profiles?: string[];
  auto?: boolean;
  idle_profile?: string;
  error?: string;
};

const COLORS: { label: string; r: number; g: number; b: number }[] = [
  { label: "White", r: 255, g: 255, b: 255 },
  { label: "Red", r: 255, g: 0, b: 0 },
  { label: "Orange", r: 255, g: 120, b: 0 },
  { label: "Yellow", r: 255, g: 220, b: 0 },
  { label: "Green", r: 0, g: 200, b: 40 },
  { label: "Cyan", r: 0, g: 200, b: 220 },
  { label: "Blue", r: 0, g: 80, b: 255 },
  { label: "Purple", r: 160, g: 0, b: 255 },
  { label: "Pink", r: 255, g: 40, b: 160 },
];

type Game = { name: string; appid: number | null };

const readRunningGame = (): Game | null => {
  try {
    const app: any = Router.MainRunningApp;
    if (!app) return null;
    return { name: app.display_name || "Game", appid: app.appid ?? null };
  } catch {
    return null;
  }
};

const gameKey = (g: Game | null) =>
  g ? String(g.appid ?? "") + "|" + (g.name || "") : "";

function Content() {
  const [status, setStatus] = useState<Status | null>(null);
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);
  const [profile, setProfile] = useState<string>("");
  const [game, setGame] = useState<Game | null>(readRunningGame());
  const [swatch, setSwatch] = useState<string>("");

  const refresh = async () => {
    try {
      const s = await call<[], Status>("status");
      setStatus(s);
      if (s.profiles && s.profiles.length && !profile) {
        const idle = s.idle_profile && s.profiles.indexOf(s.idle_profile) >= 0
          ? s.idle_profile
          : s.profiles[0];
        setProfile(idle);
      }
    } catch (e) {
      setMsg(String(e));
    }
  };

  useEffect(() => {
    call("ensure_server").catch(() => {});
    refresh();
    const id = window.setInterval(() => setGame(readRunningGame()), 2000);
    return () => window.clearInterval(id);
  }, []);

  const run = async (label: string, fn: () => Promise<any>) => {
    if (busy) return;
    setBusy(true);
    setMsg(label + "…");
    try {
      const r = await fn();
      if (r && r.ok === false) setMsg(r.error || "failed");
      else {
        setMsg(label + " ✓");
        if (r && typeof r.r === "number") {
          setSwatch(`rgb(${r.r},${r.g},${r.b})`);
        }
      }
      await refresh();
    } catch (e) {
      setMsg(String(e));
    } finally {
      setBusy(false);
    }
  };

  const profiles = status?.profiles || [];
  const profileOpts = profiles.map((p) => ({ label: p, data: p }));
  const autoOn = status?.auto !== false;

  return (
    <>
      <PanelSection title="Follow game">
        <PanelSectionRow>
          <ToggleField
            label="Auto color from game art"
            description="When you launch a game, lights match its artwork. A profile is created if you don't already have one."
            checked={autoOn}
            onChange={(v: boolean) => {
              call("set_auto", v).then(() => refresh()).catch((e) => setMsg(String(e)));
            }}
          />
        </PanelSectionRow>
        <PanelSectionRow>
          <div style={{ fontSize: 12, lineHeight: 1.4, display: "flex", alignItems: "center", gap: 8 }}>
            {swatch ? (
              <span style={{
                width: 16, height: 16, borderRadius: 4, background: swatch,
                display: "inline-block", border: "1px solid rgba(255,255,255,0.35)", flexShrink: 0,
              }} />
            ) : null}
            <span style={{ opacity: 0.9 }}>
              {game ? (game.name + (game.appid ? ` (${game.appid})` : "")) : "No game running — idle profile"}
            </span>
          </div>
        </PanelSectionRow>
      </PanelSection>

      <PanelSection title="OpenRGB">
        <PanelSectionRow>
          <div style={{ fontSize: 12, opacity: 0.85, lineHeight: 1.4 }}>
            {status
              ? (status.server ? "SDK server running" : "SDK server off — applying directly")
              : "Checking OpenRGB…"}
            {profiles.length ? ` · ${profiles.length} profile${profiles.length === 1 ? "" : "s"}` : ""}
          </div>
        </PanelSectionRow>
        {msg ? (
          <PanelSectionRow>
            <div style={{ fontSize: 12, color: msg.indexOf("✓") >= 0 ? "#8f8" : "#fc6" }}>{msg}</div>
          </PanelSectionRow>
        ) : null}
      </PanelSection>

      <PanelSection title="Profiles">
        {profiles.length === 0 ? (
          <PanelSectionRow>
            <div style={{ fontSize: 12, opacity: 0.8 }}>
              No saved profiles yet. Launch a game with auto color on, or save one in OpenRGB on the desktop.
            </div>
          </PanelSectionRow>
        ) : (
          <>
            <PanelSectionRow>
              <DropdownItem
                label="Profile"
                rgOptions={profileOpts}
                selectedOption={profile || profiles[0]}
                onChange={(v: { data: string }) => setProfile(v.data)}
              />
            </PanelSectionRow>
            <PanelSectionRow>
              <ButtonItem layout="below" disabled={busy} onClick={() =>
                run("Load " + (profile || profiles[0]), () =>
                  call("load_profile", profile || profiles[0])
                )
              }>
                Load profile
              </ButtonItem>
            </PanelSectionRow>
            <PanelSectionRow>
              <ButtonItem layout="below" disabled={busy} onClick={() =>
                run("Idle = " + (profile || profiles[0]), () =>
                  call("set_idle_profile", profile || profiles[0])
                )
              }>
                Use as idle profile
              </ButtonItem>
            </PanelSectionRow>
          </>
        )}
      </PanelSection>

      <PanelSection title="Quick colors">
        {COLORS.map((c) => (
          <PanelSectionRow key={c.label}>
            <ButtonItem layout="below" disabled={busy} onClick={() =>
              run(c.label, () => call("set_color", c.r, c.g, c.b))
            }>
              {c.label}
            </ButtonItem>
          </PanelSectionRow>
        ))}
        <PanelSectionRow>
          <ButtonItem layout="below" disabled={busy} onClick={() =>
            run("Lights off", () => call("turn_off"))
          }>
            Lights off
          </ButtonItem>
        </PanelSectionRow>
      </PanelSection>
    </>
  );
}

export default definePlugin(() => {
  let last = "";
  let unreg: undefined | (() => void);

  const pushGame = () => {
    const g = readRunningGame();
    const k = gameKey(g);
    if (k === last) return;
    last = k;
    call("sync_game", g ? g.appid : null, g ? g.name : "")
      .catch((e) => console.error("[GameModeLEDs] sync_game", e));
  };

  try {
    const sc: any = (window as any).SteamClient;
    unreg = sc?.GameSessions?.RegisterForAppLifetimeNotifications?.(() => {
      setTimeout(pushGame, 600);
    })?.unregister;
  } catch {}

  const iv = window.setInterval(pushGame, 4000);
  setTimeout(pushGame, 800);

  return {
    title: <div className={staticClasses.Title}>GameModeLEDs</div>,
    content: <Content />,
    icon: <FaLightbulb />,
    alwaysRender: true,
    onDismount() {
      window.clearInterval(iv);
      try { unreg?.(); } catch {}
    },
  };
});
