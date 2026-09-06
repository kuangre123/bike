#!/bin/bash
# 无模拟器环境下的 Swift 6 严格并发类型检查。
#   scripts/typecheck.sh            # 主 app
#   scripts/typecheck.sh watch      # watchOS app
#   scripts/typecheck.sh tests      # 主 app + Bike/Tests（本机跑不了 xcodebuild test，
#                                   #   至少保证测试代码能编过；断言仍要在 Xcode ⌘U 里跑）
# 先把 CyclingDomain 编成对应模拟器的 .swiftmodule，再 -typecheck 全部源码。
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
XC="$(xcode-select -p)"
OUT="${TMPDIR:-/tmp}/bike-typecheck"
mkdir -p "$OUT"

TARGET_KIND="${1:-app}"
case "$TARGET_KIND" in
    watch)
        SDK_NAME=watchsimulator
        TRIPLE_SUFFIX="-apple-watchos11.0-simulator"
        SOURCES=(BikeWatch/Sources)
        ;;
    app|tests)
        SDK_NAME=iphonesimulator
        TRIPLE_SUFFIX="-apple-ios18.0-simulator"
        SOURCES=(Bike/Sources)
        ;;
    *)
        echo "用法: $0 [app|watch|tests]" >&2
        exit 2
        ;;
esac
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

FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "${SOURCES[@]}" -name '*.swift' | sort)

if [ "$TARGET_KIND" = "tests" ]; then
    # 测试用 @testable import Bike，得先有个带 -enable-testing 的 Bike 模块。
    # emit-module 本身就会完整类型检查 app 源码，所以这条路顺带覆盖了 app 模式。
    echo "▸ 编译 Bike 模块 (-enable-testing)"
    xcrun swiftc -emit-module -emit-module-path "$MOD/Bike.swiftmodule" \
        -module-name Bike -enable-testing \
        -swift-version 6 -strict-concurrency=complete \
        -sdk "$SDK" -target "$TRIPLE" \
        -I "$MOD" \
        "${PLUGIN_ARGS[@]}" \
        "${FILES[@]}"

    # XCTest 不在 SDK 里，在 platform 的 Developer 目录下。
    PLAT="$XC/Platforms/iPhoneSimulator.platform/Developer"
    echo "▸ 类型检查 Bike/Tests"
    TEST_FILES=()
    while IFS= read -r f; do TEST_FILES+=("$f"); done < <(find Bike/Tests -name '*.swift' | sort)
    xcrun swiftc -typecheck \
        -swift-version 6 -strict-concurrency=complete \
        -sdk "$SDK" -target "$TRIPLE" \
        -I "$MOD" -F "$PLAT/Library/Frameworks" -I "$PLAT/usr/lib" \
        "${PLUGIN_ARGS[@]}" \
        "${TEST_FILES[@]}"
else
    echo "▸ 类型检查 ${SOURCES[*]}"
    xcrun swiftc -typecheck \
        -swift-version 6 -strict-concurrency=complete \
        -sdk "$SDK" -target "$TRIPLE" \
        -I "$MOD" \
        "${PLUGIN_ARGS[@]}" \
        "${FILES[@]}"
fi

echo "✓ 通过"
