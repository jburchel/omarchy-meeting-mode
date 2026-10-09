.pragma library

// Settings live in this plugin's entry of ~/.config/omarchy/shell.json
// ("plugins": [{ "id": "io.github.jburchel.meeting-mode", ... }]).
// normalize() turns whatever is there into a complete, valid set.

var DEFAULTS = {
    dnd: true,              // Do Not Disturb during the call
    awake: true,            // no idle lock or screen blank
    nightlight: true,       // night light off, so the camera isn't tinted
    jarvis: true,           // mute the Jarvis voice assistant, if installed
    pauseMedia: false,      // pause music/videos that are playing, resume after
    endDelay: 15,           // seconds without a call before everything is put back
    notify: true,           // a notification when meeting mode starts and ends
    callApps: "chrom|firefox|brave|vivaldi|zen|librewolf|zoom|teams|slack|webex|discord|skype|jitsi|signal|telegram|element",
    onStart: "",            // optional shell command run when a meeting starts
    onEnd: ""               // optional shell command run when it ends
};

var END_DELAY_OPTIONS = [
    { value: "5", label: "5 s" },
    { value: "15", label: "15 s" },
    { value: "30", label: "30 s" },
    { value: "60", label: "1 min" }
];

// Seconds a call app must hold the mic before meeting mode starts. Long
// enough to ignore a quick mic test, short enough that the first
// notification of the call is already silenced.
var START_AFTER = 3;

function normalize(raw) {
    var e = raw && typeof raw === "object" ? raw : {};
    var delay = Number(e.endDelay);
    delay = isFinite(delay) ? Math.max(3, Math.min(600, Math.round(delay))) : DEFAULTS.endDelay;
    var apps = typeof e.callApps === "string" && e.callApps.trim() !== "" ? e.callApps.trim() : DEFAULTS.callApps;
    try {
        new RegExp(apps, "i");
    } catch (err) {
        apps = DEFAULTS.callApps;
    }
    return {
        dnd: e.dnd !== false,
        awake: e.awake !== false,
        nightlight: e.nightlight !== false,
        jarvis: e.jarvis !== false,
        pauseMedia: e.pauseMedia === true,
        endDelay: delay,
        notify: e.notify !== false,
        callApps: apps,
        onStart: typeof e.onStart === "string" ? e.onStart : "",
        onEnd: typeof e.onEnd === "string" ? e.onEnd : ""
    };
}

// The comma list the helper script takes: "dnd,awake,nightlight,jarvis".
function actionList(values) {
    var out = [];
    ["dnd", "awake", "nightlight", "jarvis"].forEach(function(k) {
        if (values[k]) out.push(k);
    });
    return out.join(",");
}

// A PipeWire capture stream belongs to a call when its app name or binary
// matches callApps. Jarvis' wake word (pw-record) and Voxtype never match.
// The caller passes only capture streams (isStream && !isSink); media.class,
// when PipeWire reports it, must agree.
function isCallStream(props, callApps) {
    if (!props) return false;
    var cls = String(props["media.class"] || "");
    if (cls !== "" && cls.indexOf("Input") === -1) return false;
    var who = String(props["application.name"] || "") + " " + String(props["application.process.binary"] || "");
    return new RegExp(callApps, "i").test(who);
}

function callAppName(props) {
    var name = String((props && (props["application.name"] || props["application.process.binary"])) || "");
    return name !== "" ? name : "a call app";
}

// Where the service publishes its state for the bar widget and settings
// panel. It says whether you are in a call and with which app, so it must
// never land somewhere other users can read: $XDG_RUNTIME_DIR is private to
// the user (0700 by spec); without it, use this plugin's state directory,
// which bin/meeting-mode-actions creates 0700. Never /tmp.
function statePath(runtimeDir, stateHome, home) {
    if (runtimeDir)
        return runtimeDir + "/meeting-mode.json";
    var base = stateHome || ((home || "") + "/.local/state");
    return base + "/meeting-mode/state.json";
}

function entryFromConfig(config, pluginId) {
    var plugins = config && Array.isArray(config.plugins) ? config.plugins : [];
    for (var i = 0; i < plugins.length; i++)
        if (plugins[i] && String(plugins[i].id || "") === pluginId)
            return plugins[i];
    return null;
}

if (typeof module !== "undefined")
    module.exports = {
        DEFAULTS: DEFAULTS,
        START_AFTER: START_AFTER,
        normalize: normalize,
        actionList: actionList,
        isCallStream: isCallStream,
        callAppName: callAppName,
        statePath: statePath,
        entryFromConfig: entryFromConfig
    };
