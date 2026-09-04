const manifest = {"name":"GameModeLEDs","author":"Memberoffoxhound","flags":[],"api_version":1,"publish":{"tags":["rgb","openrgb","lighting","utility"],"description":"Control OpenRGB profiles and lights from Game Mode","image":""}};
const API_VERSION = 2;
if (!manifest?.name) {
    throw new Error('[@decky/api]: Failed to find plugin manifest.');
}
const internalAPIConnection = window.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit;
if (!internalAPIConnection) {
    throw new Error('[@decky/api]: Failed to connect to the loader as as the loader API was not initialized. This is likely a bug in Decky Loader.');
}
let api;
try {
    api = internalAPIConnection.connect(API_VERSION, manifest.name);
}
catch {
    api = internalAPIConnection.connect(1, manifest.name);
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version 1. Some features may not work.`);
}
if (api._version != API_VERSION) {
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version ${api._version}. Some features may not work.`);
}
const call = api.call;

var DefaultContext = {
  color: undefined,
  size: undefined,
  className: undefined,
  style: undefined,
  attr: undefined
};
var IconContext = SP_REACT.createContext && SP_REACT.createContext(DefaultContext);

var __assign = window && window.__assign || function () {
  __assign = Object.assign || function (t) {
    for (var s, i = 1, n = arguments.length; i < n; i++) {
      s = arguments[i];
      for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p)) t[p] = s[p];
    }
    return t;
  };
  return __assign.apply(this, arguments);
};
var __rest = window && window.__rest || function (s, e) {
  var t = {};
  for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p) && e.indexOf(p) < 0) t[p] = s[p];
  if (s != null && typeof Object.getOwnPropertySymbols === "function") for (var i = 0, p = Object.getOwnPropertySymbols(s); i < p.length; i++) {
    if (e.indexOf(p[i]) < 0 && Object.prototype.propertyIsEnumerable.call(s, p[i])) t[p[i]] = s[p[i]];
  }
  return t;
};
function Tree2Element(tree) {
  return tree && tree.map(function (node, i) {
    return SP_REACT.createElement(node.tag, __assign({
      key: i
    }, node.attr), Tree2Element(node.child));
  });
}
function GenIcon(data) {
  // eslint-disable-next-line react/display-name
  return function (props) {
    return SP_REACT.createElement(IconBase, __assign({
      attr: __assign({}, data.attr)
    }, props), Tree2Element(data.child));
  };
}
function IconBase(props) {
  var elem = function (conf) {
    var attr = props.attr,
      size = props.size,
      title = props.title,
      svgProps = __rest(props, ["attr", "size", "title"]);
    var computedSize = size || conf.size || "1em";
    var className;
    if (conf.className) className = conf.className;
    if (props.className) className = (className ? className + " " : "") + props.className;
    return SP_REACT.createElement("svg", __assign({
      stroke: "currentColor",
      fill: "currentColor",
      strokeWidth: "0"
    }, conf.attr, attr, svgProps, {
      className: className,
      style: __assign(__assign({
        color: props.color || conf.color
      }, conf.style), props.style),
      height: computedSize,
      width: computedSize,
      xmlns: "http://www.w3.org/2000/svg"
    }), title && SP_REACT.createElement("title", null, title), props.children);
  };
  return IconContext !== undefined ? SP_REACT.createElement(IconContext.Consumer, null, function (conf) {
    return elem(conf);
  }) : elem(DefaultContext);
}

// THIS FILE IS AUTO GENERATED
function FaLightbulb (props) {
  return GenIcon({"tag":"svg","attr":{"viewBox":"0 0 352 512"},"child":[{"tag":"path","attr":{"d":"M96.06 454.35c.01 6.29 1.87 12.45 5.36 17.69l17.09 25.69a31.99 31.99 0 0 0 26.64 14.28h61.71a31.99 31.99 0 0 0 26.64-14.28l17.09-25.69a31.989 31.989 0 0 0 5.36-17.69l.04-38.35H96.01l.05 38.35zM0 176c0 44.37 16.45 84.85 43.56 115.78 16.52 18.85 42.36 58.23 52.21 91.45.04.26.07.52.11.78h160.24c.04-.26.07-.51.11-.78 9.85-33.22 35.69-72.6 52.21-91.45C335.55 260.85 352 220.37 352 176 352 78.61 272.91-.3 175.45 0 73.44.31 0 82.97 0 176zm176-80c-44.11 0-80 35.89-80 80 0 8.84-7.16 16-16 16s-16-7.16-16-16c0-61.76 50.24-112 112-112 8.84 0 16 7.16 16 16s-7.16 16-16 16z"}}]})(props);
}

const COLORS = [
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
const readRunningGame = () => {
    try {
        const app = DFL.Router.MainRunningApp;
        if (!app)
            return null;
        return { name: app.display_name || "Game", appid: app.appid ?? null };
    }
    catch {
        return null;
    }
};
const gameKey = (g) => g ? String(g.appid ?? "") + "|" + (g.name || "") : "";
function Content() {
    const [status, setStatus] = SP_REACT.useState(null);
    const [msg, setMsg] = SP_REACT.useState("");
    const [busy, setBusy] = SP_REACT.useState(false);
    const [profile, setProfile] = SP_REACT.useState("");
    const [game, setGame] = SP_REACT.useState(readRunningGame());
    const [swatch, setSwatch] = SP_REACT.useState("");
    const refresh = async () => {
        try {
            const s = await call("status");
            setStatus(s);
            if (s.profiles && s.profiles.length && !profile) {
                const idle = s.idle_profile && s.profiles.indexOf(s.idle_profile) >= 0
                    ? s.idle_profile
                    : s.profiles[0];
                setProfile(idle);
            }
        }
        catch (e) {
            setMsg(String(e));
        }
    };
    SP_REACT.useEffect(() => {
        call("ensure_server").catch(() => { });
        refresh();
        const id = window.setInterval(() => setGame(readRunningGame()), 2000);
        return () => window.clearInterval(id);
    }, []);
    const run = async (label, fn) => {
        if (busy)
            return;
        setBusy(true);
        setMsg(label + "…");
        try {
            const r = await fn();
            if (r && r.ok === false)
                setMsg(r.error || "failed");
            else {
                setMsg(label + " ✓");
                if (r && typeof r.r === "number") {
                    setSwatch(`rgb(${r.r},${r.g},${r.b})`);
                }
            }
            await refresh();
        }
        catch (e) {
            setMsg(String(e));
        }
        finally {
            setBusy(false);
        }
    };
    const profiles = status?.profiles || [];
    const profileOpts = profiles.map((p) => ({ label: p, data: p }));
    const autoOn = status?.auto !== false;
    return (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
        window.SP_REACT.createElement(DFL.PanelSection, { title: "Follow game" },
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.ToggleField, { label: "Auto color from game art", description: "When you launch a game, lights match its artwork. A profile is created if you don't already have one.", checked: autoOn, onChange: (v) => {
                        call("set_auto", v).then(() => refresh()).catch((e) => setMsg(String(e)));
                    } })),
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement("div", { style: { fontSize: 12, lineHeight: 1.4, display: "flex", alignItems: "center", gap: 8 } },
                    swatch ? (window.SP_REACT.createElement("span", { style: {
                            width: 16, height: 16, borderRadius: 4, background: swatch,
                            display: "inline-block", border: "1px solid rgba(255,255,255,0.35)", flexShrink: 0,
                        } })) : null,
                    window.SP_REACT.createElement("span", { style: { opacity: 0.9 } }, game ? (game.name + (game.appid ? ` (${game.appid})` : "")) : "No game running — idle profile")))),
        window.SP_REACT.createElement(DFL.PanelSection, { title: "OpenRGB" },
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement("div", { style: { fontSize: 12, opacity: 0.85, lineHeight: 1.4 } },
                    status
                        ? (status.server ? "SDK server running" : "SDK server off — applying directly")
                        : "Checking OpenRGB…",
                    profiles.length ? ` · ${profiles.length} profile${profiles.length === 1 ? "" : "s"}` : "")),
            msg ? (window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement("div", { style: { fontSize: 12, color: msg.indexOf("✓") >= 0 ? "#8f8" : "#fc6" } }, msg))) : null),
        window.SP_REACT.createElement(DFL.PanelSection, { title: "Profiles" }, profiles.length === 0 ? (window.SP_REACT.createElement(DFL.PanelSectionRow, null,
            window.SP_REACT.createElement("div", { style: { fontSize: 12, opacity: 0.8 } }, "No saved profiles yet. Launch a game with auto color on, or save one in OpenRGB on the desktop."))) : (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.DropdownItem, { label: "Profile", rgOptions: profileOpts, selectedOption: profile || profiles[0], onChange: (v) => setProfile(v.data) })),
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", disabled: busy, onClick: () => run("Load " + (profile || profiles[0]), () => call("load_profile", profile || profiles[0])) }, "Load profile")),
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", disabled: busy, onClick: () => run("Idle = " + (profile || profiles[0]), () => call("set_idle_profile", profile || profiles[0])) }, "Use as idle profile"))))),
        window.SP_REACT.createElement(DFL.PanelSection, { title: "Quick colors" },
            COLORS.map((c) => (window.SP_REACT.createElement(DFL.PanelSectionRow, { key: c.label },
                window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", disabled: busy, onClick: () => run(c.label, () => call("set_color", c.r, c.g, c.b)) }, c.label)))),
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", disabled: busy, onClick: () => run("Lights off", () => call("turn_off")) }, "Lights off")))));
}
var index = DFL.definePlugin(() => {
    let last = "";
    let unreg;
    const pushGame = () => {
        const g = readRunningGame();
        const k = gameKey(g);
        if (k === last)
            return;
        last = k;
        call("sync_game", g ? g.appid : null, g ? g.name : "")
            .catch((e) => console.error("[GameModeLEDs] sync_game", e));
    };
    try {
        const sc = window.SteamClient;
        unreg = sc?.GameSessions?.RegisterForAppLifetimeNotifications?.(() => {
            setTimeout(pushGame, 600);
        })?.unregister;
    }
    catch { }
    const iv = window.setInterval(pushGame, 4000);
    setTimeout(pushGame, 800);
    return {
        title: window.SP_REACT.createElement("div", { className: DFL.staticClasses.Title }, "GameModeLEDs"),
        content: window.SP_REACT.createElement(Content, null),
        icon: window.SP_REACT.createElement(FaLightbulb, null),
        alwaysRender: true,
        onDismount() {
            window.clearInterval(iv);
            try {
                unreg?.();
            }
            catch { }
        },
    };
});

export { index as default };
//# sourceMappingURL=index.js.map
