import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons // qmllint disable import
import qs.Ui // qmllint disable import

// Meeting Mode bar indicator. The service does the work (one instance, so
// actions never run twice with several monitors); this only shows its state,
// read from $XDG_RUNTIME_DIR/meeting-mode.json, and sends commands over IPC.
//
//   left click    turn meeting mode on / off now
//   right click   settings
//   middle click  back to automatic
BarWidget {
    id: root
    moduleName: "io.github.jburchel.meeting-mode"

    property var state: ({})
    readonly property bool active: state.active === true

    readonly property var labels: ({
        dnd: "Do Not Disturb on",
        awake: "staying awake",
        nightlight: "night light off",
        "jarvis-mute": "Jarvis muted",
        "jarvis-listen": "wake word paused"
    })

    property double now: Date.now()

    function duration() {
        if (!root.state.since) return "";
        var mins = Math.floor((root.now - root.state.since) / 60000);
        if (mins < 1) return "just started";
        if (mins < 60) return mins + " min";
        return Math.floor(mins / 60) + " h " + (mins % 60) + " min";
    }

    readonly property string tip: {
        var s = root.state;
        if (!root.active) {
            var head = s.suppressed ? "Meeting mode off for this call" : "Meeting mode: waiting for a call";
            return head + "\nClick to turn it on now · Right-click for settings";
        }
        var why = s.reason === "manual" ? "turned on by hand" : (s.reason === "restored" ? "carried over a shell restart" : "call in " + s.reason);
        var done = (s.changed || []).map(function(c) { return root.labels[c] || c; });
        if (s.pausedMedia) done.push("media paused");
        return "Meeting mode on · " + why + " · " + root.duration()
            + (done.length ? "\n" + done.join(", ") : "")
            + "\nClick to turn off · Middle-click: back to automatic";
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function run(cmd) { if (root.bar) root.bar.run(cmd); }

    FileView {
        id: stateIn
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/meeting-mode.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.state = JSON.parse(text()); } catch (e) {}
        }
    }

    // Atomic replaces can slip past the watcher; a slow poll keeps it honest,
    // and the same tick moves the call timer in the tooltip.
    Timer {
        interval: 5000; repeat: true; running: true
        onTriggered: { stateIn.reload(); root.now = Date.now(); }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.active ? "\u{F0567}" : "\u{F0568}"   // nf-md-video / nf-md-video_off
        active: root.active
        dimmed: !root.active
        tooltipText: root.tip
        onPressed: function(b) {
            if (b === Qt.RightButton) root.run("omarchy-shell meeting-mode settings");
            else if (b === Qt.MiddleButton) root.run("omarchy-shell meeting-mode auto");
            else root.run("omarchy-shell meeting-mode toggle");
        }
    }
}
