#!/bin/bash

# Video2Live 签名修复脚本
# 这个脚本会帮你修改Bundle ID以解决签名问题

echo "🔧 Video2Live 签名修复工具"
echo "============================"

# 获取当前用户名
CURRENT_USER=$(whoami)
echo "当前用户: $CURRENT_USER"

# 生成新的Bundle ID
NEW_BUNDLE_ID="com.${CURRENT_USER}.video2live"
echo "建议的新Bundle ID: $NEW_BUNDLE_ID"

# 询问用户是否使用建议的Bundle ID
read -p "使用这个Bundle ID吗? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    BUNDLE_ID=$NEW_BUNDLE_ID
else
    read -p "请输入你想要的Bundle ID (例如: com.yourname.video2live): " BUNDLE_ID
fi

echo "选择的Bundle ID: $BUNDLE_ID"

# 备份项目文件
echo "📋 备份项目文件..."
cp Video2Live.xcodeproj/project.pbxproj Video2Live.xcodeproj/project.pbxproj.backup.$(date +%Y%m%d_%H%M%S)

# 修改项目文件中的Bundle ID
echo "🔨 修改项目配置..."
sed -i '' "s/com\.shuaiba\.Video2Live/$BUNDLE_ID/g" Video2Live.xcodeproj/project.pbxproj

# 检查是否修改成功
if grep -q "$BUNDLE_ID" Video2Live.xcodeproj/project.pbxproj; then
    echo "✅ Bundle ID修改成功!"
else
    echo "❌ Bundle ID修改失败!"
    exit 1
fi

# 清除旧的构建缓存
echo "🧹 清除构建缓存..."
rm -rf DerivedData/
rm -rf build/

echo ""
echo "🎉 修复完成!"
echo ""
echo "下一步操作:"
echo "1. 打开Xcode"
echo "2. 添加你的Apple ID (Xcode → Settings → Accounts)"
echo "3. 选择项目 → Signing & Capabilities"
echo "4. 确保Team选择为你的Apple ID"
echo "5. 清理并重新构建项目"
echo ""
echo "如果遇到问题，请参考 SETUP_SIGNING.md 文件"

# 显示新的Bundle ID
echo "新的Bundle ID: $BUNDLE_ID"
echo "请确保在Xcode中使用相同的Bundle ID"