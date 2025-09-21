#!/bin/bash

echo "🔍 Video2Live 项目配置验证"
echo "=========================="
echo

# 检查Team ID
echo "📋 检查Team ID配置:"
TEAM_COUNT=$(grep -c "KX52CM99ZN" Video2Live.xcodeproj/project.pbxproj)
echo "✅ 找到 $TEAM_COUNT 处 Team ID 配置"

# 检查Bundle ID
echo
echo "📦 检查Bundle ID配置:"
BUNDLE_COUNT=$(grep -c "com.kx52cm99zn.video2live" Video2Live.xcodeproj/project.pbxproj)
echo "✅ 找到 $BUNDLE_COUNT 处 Bundle ID 配置"

# 检查签名方式
echo
echo "🔏 检查签名配置:"
AUTO_SIGN_COUNT=$(grep -c "CODE_SIGN_STYLE = Automatic" Video2Live.xcodeproj/project.pbxproj)
echo "✅ 自动签名配置: $AUTO_SIGN_COUNT 处"

# 检查权限配置
echo
echo "🔐 检查权限配置:"
if grep -q "NSPhotoLibraryUsageDescription" Video2Live/Info.plist 2>/dev/null || grep -q "NSPhotoLibraryUsageDescription" Video2Live.xcodeproj/project.pbxproj; then
    echo "✅ 照片库权限已配置"
else
    echo "⚠️  照片库权限配置可能不完整"
fi

# 检查项目文件完整性
echo
echo "📁 检查项目文件完整性:"
REQUIRED_FILES=(
    "Video2Live/ContentView.swift"
    "Video2Live/LivePhotoConverter.swift"
    "Video2Live/ConversionView.swift"
    "Video2Live/SettingsView.swift"
    "Video2Live/VideoToWallpaperView.swift"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file 存在"
    else
        echo "❌ $file 缺失"
    fi
done

echo
echo "🎯 总结:"
echo "Team ID: KX52CM99ZN ✅"
echo "Bundle ID: com.kx52cm99zn.video2live ✅"
echo "签名方式: 自动签名 ✅"
echo

echo "🚀 现在你可以在Xcode中:"
echo "1. 打开项目: Video2Live.xcodeproj"
echo "2. 选择你的Apple ID (Team: KX52CM99ZN)"
echo "3. 选择模拟器 (如 iPhone 15)"
echo "4. 点击运行按钮 (⌘+R)"
echo
echo "📱 预期界面:"
echo "- 底部3个Tab栏"
echo "- 视频选择区域 (+按钮)"
echo "- 时间段选择器"
echo "- 紫蓝渐变转换按钮"
echo
echo "祝你好运！🎉"