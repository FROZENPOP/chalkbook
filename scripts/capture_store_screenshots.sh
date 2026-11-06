#!/bin/bash
# Builds Debug, installs on the iPhone 17 simulator and captures the six App Store screenshots
# into marketing/screenshots/6.3/ from the DEBUG screenshot demo. Exits non-zero on any failure.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${DEVICE:-11BD8F39-45DC-4F0B-9360-F7A6ADBD71EA}" # iPhone 17, native 1206x2622
BUNDLE="com.frozenpop.ClimbingApp"
# Outside Documents: code signing fails for derived data there.
DERIVED="${DERIVED_DATA:-${TMPDIR:-/tmp}/chalkbook-store-screenshots}"
OUT="$ROOT/marketing/screenshots/6.3"
MEDIA="$ROOT/marketing/demo-media"
WIDTH=1206 HEIGHT=2622

for file in avatar.jpg wall-{pink,blue,green,yellow,purple}{,-highlighted}.jpg; do
    [[ -f "$MEDIA/$file" ]] || { echo "Missing $MEDIA/$file (run: swift marketing/demo-media/render_demo_media.swift)" >&2; exit 1; }
done

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null

echo "Building Debug…"
xcodebuild -project "$ROOT/ClimbingApp.xcodeproj" -scheme ClimbingApp -configuration Debug \
    -destination "id=$DEVICE" -derivedDataPath "$DERIVED" build -quiet
APP="$DERIVED/Build/Products/Debug-iphonesimulator/ClimbingApp.app"

# Clean install, so the run starts from an empty demo store.
xcrun simctl uninstall "$DEVICE" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$DEVICE" "$APP"

previous_appearance="$(xcrun simctl ui "$DEVICE" appearance)"
restore() {
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    xcrun simctl status_bar "$DEVICE" clear || true
    xcrun simctl ui "$DEVICE" appearance "$previous_appearance" || true
}
trap restore EXIT
xcrun simctl ui "$DEVICE" appearance dark
xcrun simctl status_bar "$DEVICE" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --operatorName "" --batteryState discharging --batteryLevel 100

mkdir -p "$OUT"
rm -f "$OUT"/*.png

# name, tab, pushed screen
shots=("1-journal 0 -" "2-session 0 session" "3-projects 1 -" "4-progress 2 -" "5-stats 2 stats" "6-friends 3 -")
first=1
for shot in "${shots[@]}"; do
    read -r name tab screen <<<"$shot"
    args=(--ui-testing --screenshot-demo --start-tab "$tab")
    [[ "$screen" != "-" ]] && args+=(--demo-screen "$screen")
    [[ $first == 1 ]] && args+=(--reset-test-data) && first=0
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    SIMCTL_CHILD_CHALKBOOK_DEMO_MEDIA="$MEDIA" xcrun simctl launch "$DEVICE" "$BUNDLE" "${args[@]}" >/dev/null
    sleep 8 # first launch seeds the journal; pushes and photo highlighting settle
    xcrun simctl io "$DEVICE" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
    echo "Captured $name"
done

# App Store rejects alpha: redraw each capture into an opaque sRGB bitmap (lossless).
swift - "$OUT"/*.png <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Can't read \(path)") }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let opaque = context.makeImage(), let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { fatalError("Can't write \(path)") }
    CGImageDestinationAddImage(destination, opaque, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Can't write \(path)") }
}
SWIFT

status=0
count=$(find "$OUT" -name '*.png' | wc -l | tr -d ' ')
[[ "$count" == 6 ]] || { echo "Expected 6 screenshots, found $count" >&2; status=1; }
for shot in "${shots[@]}"; do
    read -r name _ _ <<<"$shot"
    file="$OUT/$name.png"
    [[ -f "$file" ]] || { echo "Missing $file" >&2; status=1; continue; }
    info="$(sips -g pixelWidth -g pixelHeight -g hasAlpha -g format -g space "$file")"
    grep -q "pixelWidth: $WIDTH" <<<"$info" && grep -q "pixelHeight: $HEIGHT" <<<"$info" && grep -q "hasAlpha: no" <<<"$info" \
        && grep -q "format: png" <<<"$info" && grep -q "space: RGB" <<<"$info" \
        || { echo "Wrong format for $file:" >&2; echo "$info" >&2; status=1; }
done
[[ $status == 0 ]] && echo "6 screenshots in $OUT: ${WIDTH}x${HEIGHT}, PNG, RGB, no alpha"
exit $status
