#!/bin/zsh
# Builds the FluidUse harvester (BookmarkSortCheck) and topic sorter (TopicSortDemo) in release mode.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[[ -d "$ROOT/vendor/FluidUse" ]] || git clone --depth 1 https://github.com/FluidInference/FluidUse "$ROOT/vendor/FluidUse"
# Workaround for a Command Line Tools install with files left over from older versions, which break every Swift build:
#  - PackageDescription *.private.swiftinterface (Feb 2024): Package.swift fails to link (Package.__allocating_init)
#  - usr/include/swift/module.modulemap (Aug 2023): "redefinition of module 'SwiftBridging'", so Foundation won't import
# We build against a copy of SwiftPM's libs without the first and hide the second with a VFS overlay.
# The real fix is reinstalling the Command Line Tools (or deleting those files with sudo), then this block is a no-op.
CLT=/Library/Developer/CommandLineTools/usr
FLAGS=()
SWIFTC_FLAGS=()
if [[ -n $(find "$CLT/lib/swift/pm" -name "*.private.swiftinterface" 2>/dev/null) || -f "$CLT/include/swift/module.modulemap" ]]; then
  V="$ROOT/vendor/swiftpm-libs"
  if [[ ! -f "$V/overlay.yaml" ]]; then
    rm -rf "$V"; cp -R "$CLT/lib/swift/pm" "$V"
    find "$V" -name "*.private.swiftinterface" -delete
    : > "$V/empty.modulemap"
    cat > "$V/overlay.yaml" <<YAML
{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "directory", "name": "$CLT/include/swift",
  "contents": [ { "type": "file", "name": "module.modulemap", "external-contents": "$V/empty.modulemap" } ] } ] }
YAML
  fi
  export SWIFTPM_CUSTOM_LIBS_DIR="$V"
  FLAGS=(-Xbuild-tools-swiftc -vfsoverlay -Xbuild-tools-swiftc "$V/overlay.yaml"
         -Xswiftc -vfsoverlay -Xswiftc "$V/overlay.yaml" -Xcc -ivfsoverlay -Xcc "$V/overlay.yaml")
  SWIFTC_FLAGS=(-vfsoverlay "$V/overlay.yaml" -Xcc -ivfsoverlay -Xcc "$V/overlay.yaml")
fi
cd "$ROOT/vendor/FluidUse"
swift build -c release --product BookmarkSortCheck "${FLAGS[@]}"
swift build -c release --product TopicSortDemo "${FLAGS[@]}"
mkdir -p "$ROOT/vendor/bin"
swiftc -O "${SWIFTC_FLAGS[@]}" "$ROOT/scripts/xharvest.swift" -o "$ROOT/vendor/bin/xharvest"
echo "built → $ROOT/vendor/FluidUse/.build/release/ and $ROOT/vendor/bin/xharvest"
