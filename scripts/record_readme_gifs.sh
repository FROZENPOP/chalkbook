#!/bin/bash
# Records the README demo GIFs into docs/media/ from the DEBUG screenshot demo (fake people, fake climbs).
# Builds Debug, runs each ReadmeDemoUITests flow on the iPhone 17 simulator while `simctl io recordVideo` records it,
# then converts each video with scripts/video_to_gif.swift. Exits non-zero on any failure.
# Usage: scripts/record_readme_gifs.sh [journal|projects|progress|friends ...]   (default: all four)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${DEVICE:-11BD8F39-45DC-4F0B-9360-F7A6ADBD71EA}" # iPhone 17
BUNDLE="com.frozenpop.ClimbingApp"
# Outside Documents: code signing fails for derived data there.
DERIVED="${DERIVED_DATA:-${TMPDIR:-/tmp}/chalkbook-readme-media}"
OUT="$ROOT/docs/media"
MEDIA="$ROOT/marketing/demo-media"
FPS="${FPS:-12}" WIDTH="${WIDTH:-360}"
MAX_BYTES=$((4 * 1024 * 1024))
WORK="$(mktemp -d "${TMPDIR:-/tmp}/chalkbook-readme.XXXXXX")"

test_for() {
    case "$1" in
        journal) echo testJournalSession ;; projects) echo testProjects ;; progress) echo testProgress ;; friends) echo testFriends ;;
        *) echo "Unknown flow: $1" >&2; return 1 ;;
    esac
}
flows=("$@"); [[ $# -gt 0 ]] || flows=(journal projects progress friends)
for flow in "${flows[@]}"; do test_for "$flow" >/dev/null; done

for file in avatar.jpg wall-{pink,blue,green,yellow,purple}{,-highlighted}.jpg; do
    [[ -f "$MEDIA/$file" ]] || { echo "Missing $MEDIA/$file (run: swift marketing/demo-media/render_demo_media.swift)" >&2; exit 1; }
done

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null

previous_appearance="$(xcrun simctl ui "$DEVICE" appearance)"
recorder="" runner=""
restore() {
    status=$?
    [[ -n "$recorder" ]] && kill -INT "$recorder" 2>/dev/null && wait "$recorder" 2>/dev/null || true
    [[ -n "$runner" ]] && kill "$runner" 2>/dev/null || true
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    xcrun simctl status_bar "$DEVICE" clear || true
    xcrun simctl ui "$DEVICE" appearance "$previous_appearance" || true
    if [[ $status == 0 ]]; then rm -rf "$WORK"; else echo "Failed; videos and logs kept in $WORK" >&2; fi
}
trap restore EXIT
xcrun simctl ui "$DEVICE" appearance dark
xcrun simctl status_bar "$DEVICE" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --operatorName "" --batteryState discharging --batteryLevel 100

echo "Building Debug…"
xcodebuild -project "$ROOT/ClimbingApp.xcodeproj" -scheme ClimbingApp -configuration Debug \
    -destination "id=$DEVICE" -derivedDataPath "$DERIVED" build-for-testing -quiet

# Waits for a marker file while the test run is still alive.
await_marker() {
    local file="$1" seconds="$2"
    for ((i = 0; i < seconds * 10; i++)); do
        [[ -e "$file" ]] && return 0
        kill -0 "$runner" 2>/dev/null || { echo "UI test exited before $(basename "$file")" >&2; return 1; }
        sleep 0.1
    done
    echo "Timed out waiting for $(basename "$file")" >&2; return 1
}

mkdir -p "$OUT"
for flow in "${flows[@]}"; do
    test="$(test_for "$flow")" video="$WORK/$flow.mov" log="$WORK/$flow.xcodebuild.log"
    echo "Recording $flow ($test)…"
    TEST_RUNNER_README_DEMO_MARKERS="$WORK" TEST_RUNNER_CHALKBOOK_DEMO_MEDIA="$MEDIA" \
        xcodebuild -project "$ROOT/ClimbingApp.xcodeproj" -scheme ClimbingApp -configuration Debug -destination "id=$DEVICE" \
        -derivedDataPath "$DERIVED" -parallel-testing-enabled NO -only-testing:"ClimbingAppUITests/ReadmeDemoUITests/$test" \
        test-without-building >"$log" 2>&1 &
    runner=$!
    await_marker "$WORK/$flow.ready" 180

    xcrun simctl io "$DEVICE" recordVideo --codec=h264 --force "$video" >"$WORK/$flow.recorder.log" 2>&1 &
    recorder=$!
    for ((i = 0; i < 100; i++)); do grep -q "Recording started" "$WORK/$flow.recorder.log" && break; sleep 0.1; done
    grep -q "Recording started" "$WORK/$flow.recorder.log" || { echo "recordVideo didn't start:" >&2; cat "$WORK/$flow.recorder.log" >&2; exit 1; }
    touch "$WORK/$flow.go"

    await_marker "$WORK/$flow.done" 60
    kill -INT "$recorder"; wait "$recorder"; recorder=""
    wait "$runner" || { echo "$test failed; see $log" >&2; tail -30 "$log" >&2; runner=""; exit 1; }
    runner=""

    gif="$OUT/demo-$flow.gif"
    swift "$ROOT/scripts/video_to_gif.swift" "$video" "$gif" "$FPS" "$WIDTH"
    bytes=$(stat -f %z "$gif")
    [[ $bytes -lt $MAX_BYTES ]] || { echo "$gif is $bytes bytes, over 4 MB; lower FPS or WIDTH" >&2; exit 1; }
done
echo "GIFs in $OUT"
