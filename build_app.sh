#!/bin/bash
#
# build_app.sh — 本地一键打包 BLEUnlock.app
#
# 工程默认用的是原作者的签名团队(42LGPQYC7M)，你没有对应证书，
# 所以本脚本默认使用 ad-hoc 签名(CODE_SIGN_IDENTITY="-")，无需 Apple 开发者账号，
# 产出的 .app 可以在本机直接运行(菜单栏 App)。
#
# 用法:
#   ./build_app.sh                              # 默认: Release 配置 + ad-hoc 签名
#   CONFIG=Debug ./build_app.sh                 # 改用 Debug 配置(编译更快)
#   DEVELOPMENT_TEAM=XXXXXXXXXX ./build_app.sh  # 用你自己的团队做正式自动签名
#   NO_ZIP=1 ./build_app.sh                     # 只产出 .app，不额外打 zip
#
set -euo pipefail

APPNAME="BLEUnlock"
SCHEME="BLEUnlock"

# 脚本所在目录即工程根目录
BASEDIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$BASEDIR/$APPNAME.xcodeproj"
BUILDDIR="$BASEDIR/build"
DERIVED="$BUILDDIR/DerivedData"
DISTDIR="$BASEDIR/dist"
CONFIG="${CONFIG:-Release}"

if [ ! -d "$PROJECT" ]; then
    echo "❌ 找不到工程: $PROJECT"
    exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
    echo "❌ 未检测到 Xcode 命令行工具。请先安装 Xcode，并执行:"
    echo "     sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

echo "==> 清理旧的编译产物"
rm -rf "$DERIVED"
mkdir -p "$DISTDIR"

# 根据是否提供团队 ID 选择签名方式
if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
    echo "==> 使用自动签名, Team = $DEVELOPMENT_TEAM"
    echo "    (若提示 Bundle ID 'jp.sone.BLEUnlock' 被占用, 需先在工程里改成你自己的 ID)"
    SIGN_ARGS=(
        CODE_SIGN_STYLE=Automatic
        DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
        -allowProvisioningUpdates
    )
else
    echo "==> 未设置 DEVELOPMENT_TEAM, 使用 ad-hoc 签名(仅供本机运行)"
    SIGN_ARGS=(
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY="-"
        DEVELOPMENT_TEAM=""
        PROVISIONING_PROFILE_SPECIFIER=""
    )
fi

echo "==> 编译 $APPNAME ($CONFIG)"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    "${SIGN_ARGS[@]}" \
    clean build

APP_SRC="$DERIVED/Build/Products/$CONFIG/$APPNAME.app"
if [ ! -d "$APP_SRC" ]; then
    echo "❌ 编译结束但未找到产物: $APP_SRC"
    exit 1
fi

APP_DST="$DISTDIR/$APPNAME.app"
echo "==> 拷贝到 $APP_DST"
rm -rf "$APP_DST"
ditto "$APP_SRC" "$APP_DST"

# 读取版本号用于命名 zip
PLIST="$APP_DST/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || echo 0)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST" 2>/dev/null || echo 0)"

ZIP=""
if [ -z "${NO_ZIP:-}" ]; then
    ZIP="$DISTDIR/$APPNAME-$VERSION-$BUILD.zip"
    echo "==> 打包 $ZIP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP_DST" "$ZIP"
fi

echo ""
echo "✅ 打包完成 (版本 $VERSION build $BUILD)"
echo "   App : $APP_DST"
[ -n "$ZIP" ] && echo "   Zip : $ZIP"
echo ""
echo "提示:"
echo "  • ad-hoc 签名的 App 每次重新编译签名都会变，重装后需到"
echo "    系统设置 → 隐私与安全性 → 辅助功能 里重新勾选 BLEUnlock。"
echo "  • 若首次打开被 Gatekeeper 拦截, 右键点 App → 打开, 或执行:"
echo "      xattr -dr com.apple.quarantine \"$APP_DST\""
