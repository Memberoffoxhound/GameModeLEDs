import {
  definePlugin,
  PanelSection,
  PanelSectionRow,
  ButtonItem,
  DropdownItem,
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

function Content() {
  const [status, setStatus] = useState<Status | null>(null);
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);
  const [profile, setProfile] = useState<string>("");

  const refresh = async () => {
    try {
      const s = await call<[], Status>("status");
      setStatus(s);
      if (s.profiles && s.profiles.length && !profile) {
        setProfile(s.profiles[0]);
      }
    } catch (e) {
      setMsg(String(e));
    }
  };

  useEffect(() => {
    call("ensure_server").catch(() => {});
    refresh();
  }, []);

  const run = async (label: string, fn: () => Promise<any>) => {
    if (busy) return;
    setBusy(true);
    setMsg(label + "…");
    try {
      const r = await fn();
      if (r && r.ok === false) setMsg(r.error || "failed");
      else setMsg(label + " ✓");
      await refresh();
    } catch (e) {
      setMsg(String(e));
    } finally {
      setBusy(false);
    }
  };

  const profiles = status?.profiles || [];
  const profileOpts = profiles.map((p) => ({ label: p, data: p }));

  return (
    <>
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
              No saved profiles. In Desktop Mode open OpenRGB, set your lights, Save Profile, then come back here.
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
  return {
    title: <div className={staticClasses.Title}>GameModeLEDs</div>,
    content: <Content />,
    icon: <FaLightbulb />,
  };
});
