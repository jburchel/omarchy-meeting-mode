#!/usr/bin/env bash
# Run: bash tests/actions.test.sh
# Drives bin/meeting-mode-actions against stand-in omarchy, omarchy-shell,
# hyprctl and jarvis commands in a temporary HOME, so nothing on the real
# desktop changes. Checks that "off" undoes exactly what "on" changed.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" FAKE="$tmp/fake"
mkdir -p "$HOME/.config/jarvis" "$HOME/.local/state/omarchy/indicators" "$FAKE" "$tmp/bin"
pass=0 fail=0
check() { if [[ "$2" == "$3" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: expected '$3', got '$2'"; fi; }

# Stand-ins keep their state as files in $FAKE.
cat >"$tmp/bin/omarchy-shell" <<'S'
#!/usr/bin/env bash
[[ "$1 $2" == "notifications dndState" ]] && { cat "$FAKE/dnd" 2>/dev/null || echo off; }
exit 0
S
cat >"$tmp/bin/omarchy" <<'S'
#!/usr/bin/env bash
case "$*" in
  "toggle notification silencing") [[ "$(cat "$FAKE/dnd" 2>/dev/null)" == on ]] && echo off >"$FAKE/dnd" || echo on >"$FAKE/dnd" ;;
  "toggle idle stay-awake") touch "$HOME/.local/state/omarchy/indicators/stay-awake" ;;
  "toggle idle allow-idle") rm -f "$HOME/.local/state/omarchy/indicators/stay-awake" ;;
  "toggle nightlight --status") t=$(cat "$FAKE/temp" 2>/dev/null || echo 6500)
     [[ $t -lt 6000 ]] && e=true || e=false; echo "{\"enabled\":$e,\"temperature\":$t}" ;;
esac
S
cat >"$tmp/bin/hyprctl" <<'S'
#!/usr/bin/env bash
[[ "$1 $2" == "hyprsunset temperature" && -n "${3:-}" ]] && echo "$3" >"$FAKE/temp"
exit 0
S
cat >"$tmp/bin/jarvis" <<'S'
#!/usr/bin/env bash
case "$*" in
  mute) touch "$HOME/.config/jarvis/muted" ;; unmute) rm -f "$HOME/.config/jarvis/muted" ;;
  "listen status") cat "$FAKE/listen" 2>/dev/null || echo active ;;
  "listen stop") echo inactive >"$FAKE/listen" ;; "listen start") echo active >"$FAKE/listen" ;;
esac
S
chmod +x "$tmp/bin/"*
# Only the stand-ins and system folders: never a real jarvis/omarchy from the
# developer's ~/.local/bin, which would change the real desktop.
export PATH="$tmp/bin:/usr/bin:/bin"
for c in jarvis omarchy omarchy-shell hyprctl; do [[ "$(command -v $c)" == "$tmp/bin/$c" ]] || { echo "refusing to run: $c is not the stand-in"; exit 1; }; done
A="$here/bin/meeting-mode-actions"
state() { echo "dnd=$(cat "$FAKE/dnd" 2>/dev/null || echo off) awake=$([[ -f $HOME/.local/state/omarchy/indicators/stay-awake ]] && echo y || echo n) temp=$(cat "$FAKE/temp" 2>/dev/null || echo 6500) muted=$([[ -f $HOME/.config/jarvis/muted ]] && echo y || echo n) listen=$(cat "$FAKE/listen" 2>/dev/null || echo active)"; }

# 1. Everything off before the call: all of it changes, all of it comes back.
echo 4000 >"$FAKE/temp"
before=$(state)
out=$("$A" on dnd,awake,nightlight,jarvis)
check "on: status" "$out" '{"active":true,"changed":["dnd","awake","nightlight","jarvis-mute","jarvis-listen"]}'
check "on: desktop" "$(state)" "dnd=on awake=y temp=6500 muted=y listen=inactive"
check "on twice is a no-op" "$("$A" on dnd,awake,nightlight,jarvis)" "$out"
check "off: status" "$("$A" off)" '{"active":false,"changed":[]}'
check "off: restored" "$(state)" "$before"

# 2. Already the way a meeting wants it: nothing recorded, nothing undone.
echo on >"$FAKE/dnd"; touch "$HOME/.local/state/omarchy/indicators/stay-awake"; echo 6500 >"$FAKE/temp"; touch "$HOME/.config/jarvis/muted"
before=$(state)
check "pre-set: nothing changed" "$("$A" on dnd,awake,nightlight,jarvis)" '{"active":true,"changed":["jarvis-listen"]}'
"$A" off >/dev/null
check "pre-set: left as the user had it" "$(state)" "$before"

# 3. Only the switched-on actions run.
rm -f "$FAKE/dnd" "$HOME/.local/state/omarchy/indicators/stay-awake" "$HOME/.config/jarvis/muted"
check "subset" "$("$A" on dnd)" '{"active":true,"changed":["dnd"]}'
check "subset: awake untouched" "$(state)" "dnd=on awake=n temp=6500 muted=n listen=active"
"$A" off >/dev/null

# 4. The record survives a restart: a new process can still undo it.
"$A" on dnd,awake >/dev/null
check "status after restart" "$("$A" status)" '{"active":true,"changed":["dnd","awake"]}'
"$A" off >/dev/null
check "undone after restart" "$(state)" "dnd=off awake=n temp=6500 muted=n listen=active"

# 5. Without Jarvis installed, the jarvis action is skipped cleanly.
rm "$tmp/bin/jarvis"
check "no jarvis" "$("$A" on jarvis,dnd)" '{"active":true,"changed":["dnd"]}'
"$A" off >/dev/null

echo "actions: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
