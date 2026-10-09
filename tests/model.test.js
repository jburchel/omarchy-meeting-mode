// Run: node tests/model.test.js
const fs = require("fs");
const path = require("path");
const assert = require("assert");

function load(file) {
  const src = fs.readFileSync(path.join(__dirname, "..", file), "utf8").replace(/^\.pragma library\s*/, "");
  const module = { exports: {} };
  new Function("module", src)(module);
  return module.exports;
}

const M = load("SettingsModel.js");
let n = 0;
function test(name, fn) { fn(); n++; }

const D = M.normalize({});
const capture = (app, bin) => ({ "media.class": "Stream/Input/Audio", "application.name": app, "application.process.binary": bin || "" });

test("defaults", () => {
  assert.strictEqual(D.dnd, true);
  assert.strictEqual(D.awake, true);
  assert.strictEqual(D.nightlight, true);
  assert.strictEqual(D.jarvis, true);
  assert.strictEqual(D.pauseMedia, false, "pausing media is opt-in");
  assert.strictEqual(D.endDelay, 15);
  assert.strictEqual(M.actionList(D), "dnd,awake,nightlight,jarvis");
});

test("bad values fall back", () => {
  const v = M.normalize({ endDelay: "soon", callApps: "(unclosed", dnd: "yes" });
  assert.strictEqual(v.endDelay, 15);
  assert.strictEqual(v.callApps, M.DEFAULTS.callApps, "an invalid regex must not break detection");
  assert.strictEqual(v.dnd, true);
  assert.strictEqual(M.normalize({ endDelay: 0 }).endDelay, 3);
  assert.strictEqual(M.normalize({ endDelay: 99999 }).endDelay, 600);
});

test("action list follows switches", () => {
  assert.strictEqual(M.actionList(M.normalize({ awake: false, jarvis: false })), "dnd,nightlight");
  assert.strictEqual(M.actionList(M.normalize({ dnd: false, awake: false, nightlight: false, jarvis: false })), "");
});

test("call apps are detected", () => {
  for (const [app, bin] of [["Google Chrome", "chrome"], ["Chromium", ""], ["Firefox", "firefox"], ["ZOOM VoiceEngine", "zoom"],
                            ["teams-for-linux", ""], ["Slack", "slack"], ["WEBRTC VoiceEngine", "Discord"], ["", "vivaldi-bin"]])
    assert.ok(M.isCallStream(capture(app, bin), D.callApps), `${app}/${bin} should count as a call`);
});

test("non-call capture is ignored", () => {
  for (const [app, bin] of [["pw-record", ""], ["voxtype", "voxtype"], ["OBS", "obs"], ["audacity", ""], ["", ""]])
    assert.ok(!M.isCallStream(capture(app, bin), D.callApps), `${app}/${bin} must not start meeting mode`);
});

test("playback streams never count", () => {
  assert.ok(!M.isCallStream({ "media.class": "Stream/Output/Audio", "application.name": "Google Chrome" }, D.callApps));
  assert.ok(!M.isCallStream(null, D.callApps));
});

test("custom call apps", () => {
  const v = M.normalize({ callApps: "mumble|obs" });
  assert.ok(M.isCallStream(capture("Mumble", ""), v.callApps));
  assert.ok(!M.isCallStream(capture("Google Chrome", ""), v.callApps));
});

test("app name for messages", () => {
  assert.strictEqual(M.callAppName(capture("Google Chrome", "chrome")), "Google Chrome");
  assert.strictEqual(M.callAppName(capture("", "zoom")), "zoom");
  assert.strictEqual(M.callAppName({}), "a call app");
});

console.log(`model: ${n} tests passed`);
