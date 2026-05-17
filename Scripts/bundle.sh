#!/usr/bin/env bash
#
# Builds Codewake.app — a double-clickable bundle for people who do not have a Swift
# toolchain — and zips it for release.
#
#   ./Scripts/bundle.sh            universal (arm64 + x86_64)
#   ARCHS="arm64" ./Scripts/bundle.sh   this machine only, much faster
#
# The bundle is signed ad-hoc (`codesign -s -`), not with a Developer ID: there is no paid
# Apple account behind this project. That is enough for macOS to run it locally, but a copy
# downloaded from the internet arrives quarantined and Gatekeeper will refuse the first
# launch. See the "Installing" section of the README for the two ways past that.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Codewake"
BUNDLE_ID="com.luisresendez.codewake"
VERSION="${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"
# CFBundleShortVersionString has to look like a version number, and an untagged checkout
# describes itself as a bare commit hash, so fall back rather than write something invalid.
if [ -z "${SHORT_VERSION:-}" ]; then
    if [[ "$VERSION" =~ ^v?([0-9]+(\.[0-9]+)*) ]]; then
        SHORT_VERSION="${BASH_REMATCH[1]}"
    else
        SHORT_VERSION="1.0"
    fi
fi
ARCHS="${ARCHS:-arm64 x86_64}"

DIST="dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"

arch_flags=()
for arch in $ARCHS; do arch_flags+=(--arch "$arch"); done

echo "==> Building $APP_NAME $VERSION for: $ARCHS"
swift build -c release "${arch_flags[@]}"
BINARY="$(swift build -c release "${arch_flags[@]}" --show-bin-path)/codewake"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"

echo "==> Adding the icon"
cp "Resources/$APP_NAME.icns" "$CONTENTS/Resources/$APP_NAME.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>          <string>en</string>
    <key>CFBundleExecutable</key>                 <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>                   <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>                 <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>      <string>6.0</string>
    <key>CFBundleName</key>                       <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>                <string>APPL</string>
    <key>CFBundleShortVersionString</key>         <string>$SHORT_VERSION</string>
    <key>CFBundleVersion</key>                    <string>$VERSION</string>
    <key>LSApplicationCategoryType</key>          <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>             <string>15.0</string>
    <key>NSHighResolutionCapable</key>            <true/>
    <key>NSHumanReadableCopyright</key>           <string>MIT licensed.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> Signing ad-hoc"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

# A disk image rather than a zip, because it carries the install gesture with it: the
# window holds the app beside an alias to /Applications, so the whole instruction is
# "drag left onto right". A zip leaves a folder in Downloads and the moving to whoever
# downloaded it. `ditto` does the copy so the signature survives into the image.
echo "==> Building the disk image"
STAGE="$(mktemp -d)"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DIST/$APP_NAME.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO -quiet \
    "$DIST/$APP_NAME.dmg"
rm -rf "$STAGE"

echo
echo "$APP"
echo "$DIST/$APP_NAME.dmg  ($(du -h "$DIST/$APP_NAME.dmg" | cut -f1))"
echo "Architectures: $(lipo -archs "$CONTENTS/MacOS/$APP_NAME")"
