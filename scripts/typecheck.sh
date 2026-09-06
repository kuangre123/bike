#!/bin/bash
# 无模拟器环境下的 Swift 6 严格并发类型检查。
#   scripts/typecheck.sh            # 主 app
#   scripts/typecheck.sh watch      # watchOS app
# 先把 CyclingDomain 编成 iOS Simulator 的 .swiftmodule，再 -typecheck 全部 app 源码。
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
XC="$(xcode-select -p)"
OUT="${TMPDIR:-/tmp}/bike-typecheck"
mkdir -p "$OUT"

TARGET_KIND="${1:-app}"
if [ "$TARGET_KIND" = "watch" ]; then
    SDK_NAME=watchsimulator
    TRIPLE_SUFFIX="-apple-watchos11.0-simulator"
    SOURCES=(BikeWatch/Sources)
else
    SDK_NAME=iphonesimulator
    TRIPLE_SUFFIX="-apple-ios18.0-simulator"
    SOURCES=(Bike/Sources)
fi
SDK="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
TRIPLE="arm64${TRIPLE_SUFFIX}"
MOD="$OUT/$SDK_NAME"
mkdir -p "$MOD"

PLUGIN_ARGS=(
    -plugin-path "$XC/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins"
    -plugin-path "$XC/Platforms/${SDK_NAME/simulator/OS}.platform/Developer/usr/lib/swift/host/plugins"
    -in-process-plugin-server-path "$XC/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/libSwiftInProcPluginServer.dylib"
)

echo "▸ 编译 CyclingDomain ($SDK_NAME)"
xcrun swiftc -emit-module -emit-module-path "$MOD/CyclingDomain.swiftmodule" \
    -module-name CyclingDomain \
    -swift-version 6 -strict-concurrency=complete \
    -sdk "$SDK" -target "$TRIPLE" \
    "${PLUGIN_ARGS[@]}" \
    Packages/CyclingDomain/Sources/CyclingDomain/*.swift

echo "▸ 类型检查 ${SOURCES[*]}"
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "${SOURCES[@]}" -name '*.swift' | sort)
xcrun swiftc -typecheck \
    -swift-version 6 -strict-concurrency=complete \
    -sdk "$SDK" -target "$TRIPLE" \
    -I "$MOD" \
    "${PLUGIN_ARGS[@]}" \
    "${FILES[@]}"

echo "✓ 通过"
