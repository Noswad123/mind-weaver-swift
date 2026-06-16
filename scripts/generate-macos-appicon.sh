#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/generate-macos-appicon.sh <source-1024-png> [appiconset-path]

Generates the macOS AppIcon.appiconset images and Contents.json from a square
source PNG. The source should be at least 1024x1024.

Default appiconset path:
  MindWeaver/MindWeaver/Assets.xcassets/AppIcon.appiconset

Example:
  scripts/generate-macos-appicon.sh artwork/brain-mage-hat-1024.png
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 2
fi

SOURCE="$1"
APPICONSET="${2:-MindWeaver/MindWeaver/Assets.xcassets/AppIcon.appiconset}"

if [[ ! -f "$SOURCE" ]]; then
  echo "Source image not found: $SOURCE" >&2
  exit 1
fi

if ! command -v sips >/dev/null 2>&1; then
  echo "sips is required and should be available on macOS." >&2
  exit 1
fi

mkdir -p "$APPICONSET"

make_icon() {
  local pixels="$1"
  local filename="$2"
  sips -z "$pixels" "$pixels" "$SOURCE" --out "$APPICONSET/$filename" >/dev/null
}

make_icon 16   "appicon-16.png"
make_icon 32   "appicon-16@2x.png"
make_icon 32   "appicon-32.png"
make_icon 64   "appicon-32@2x.png"
make_icon 128  "appicon-128.png"
make_icon 256  "appicon-128@2x.png"
make_icon 256  "appicon-256.png"
make_icon 512  "appicon-256@2x.png"
make_icon 512  "appicon-512.png"
make_icon 1024 "appicon-512@2x.png"

cat > "$APPICONSET/Contents.json" <<'EOF'
{
  "images" : [
    {
      "filename" : "appicon-16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "appicon-16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "appicon-32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "appicon-32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "appicon-128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "appicon-128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "appicon-256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "appicon-256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "appicon-512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "appicon-512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "Generated macOS app icons in: $APPICONSET"
