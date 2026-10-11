#!/bin/bash
# NTFS 拷贝助手 - 构建脚本
set -e

APP_NAME="NTFSCopier"
APP_DISPLAY_NAME="NTFS 拷贝助手"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_DISPLAY_NAME.app"

echo "🔨 开始构建 $APP_DISPLAY_NAME..."

# 清理旧的构建产物
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 收集所有 Swift 源文件
SWIFT_FILES=$(find Sources -name "*.swift" | sort)

echo "📁 编译源文件..."
swiftc \
  -o "$BUILD_DIR/$APP_NAME" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  -framework UniformTypeIdentifiers \
  -target x86_64-apple-macosx13.0 \
  -O \
  $SWIFT_FILES

echo "📦 创建 App Bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 复制可执行文件
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# 复制 Info.plist
cp Resources/Info.plist "$APP_BUNDLE/Contents/"

# 复制内置 NTFS 组件（ntfs-3g + fuse-t 兼容层 + go-nfsv4）
if [ -d "Resources/ntfs" ]; then
  echo "📦 打包内置 NTFS 组件..."
  mkdir -p "$APP_BUNDLE/Contents/Resources/ntfs"
  cp Resources/ntfs/* "$APP_BUNDLE/Contents/Resources/ntfs/"
  chmod 755 "$APP_BUNDLE/Contents/Resources/ntfs/"*
fi

# Ad-hoc 代码签名（保证修改过的二进制可正常加载）
codesign --force -s - "$APP_BUNDLE" 2>/dev/null || true

# 设置可执行权限
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo ""
echo "✅ 构建完成！"
echo "📱 App 位置: $APP_BUNDLE"
echo ""
echo "运行方式："
echo "  方式1: 双击 $APP_DISPLAY_NAME.app"
echo "  方式2: 运行 ./build.sh run"
echo ""

# 如果传入 run 参数则运行
if [ "$1" = "run" ]; then
  echo "🚀 启动 $APP_DISPLAY_NAME..."
  open "$APP_BUNDLE"
fi
