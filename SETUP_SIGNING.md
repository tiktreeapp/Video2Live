# Video2Live 开发者签名设置指南

## 🎯 目标
解决Xcode运行时的签名问题，让应用能够在iOS设备或模拟器上运行。

## 📋 前提条件
1. Apple ID账号（免费即可）
2. Xcode已安装并更新到最新版本
3. 项目文件完整

## 🔧 设置步骤

### 步骤1：在Xcode中添加Apple ID

1. 打开Xcode
2. 菜单栏选择 **Xcode → Settings...**
3. 点击 **Accounts** 标签
4. 点击左下角的 **+** 按钮
5. 选择 **Apple ID**
6. 输入你的Apple ID和密码

### 步骤2：修改Bundle Identifier

由于原Bundle ID `com.shuaiba.Video2Live` 可能已被占用，建议修改为个人专属ID：

```bash
# 推荐的Bundle ID格式：
com.yourname.video2live
com.yourname.Video2Live
video2live.yourname.com
```

### 步骤3：更新项目配置

在Xcode中：

1. 选择项目导航器中的 **Video2Live** 项目
2. 选择 **Video2Live** target
3. 点击 **Signing & Capabilities** 标签
4. 进行以下设置：

#### 自动签名设置：
- ✅ **Automatically manage signing**: 勾选
- **Team**: 选择你的Apple ID团队
- **Bundle Identifier**: 修改为个人专属ID

#### 手动签名设置（如果需要）：
- ❌ **Automatically manage signing**: 取消勾选
- **Provisioning Profile**: 选择"Download Profile"
- **Signing Certificate**: 选择你的开发证书

### 步骤4：验证设置

在Xcode中：

1. 选择模拟器（如iPhone 15）
2. 点击 **Product → Clean Build Folder** (⌘+Shift+K)
3. 点击 **Product → Build** (⌘+B)

## 🚨 常见问题解决

### 问题1：Bundle ID已被使用
**解决方案：**
```bash
# 尝试这些变体：
com.yourname.video2live.app
video2live-com.yourname
com.yourname.apps.video2live
```

### 问题2：没有有效的签名证书
**解决方案：**
1. 确保Apple ID已添加到Xcode
2. 重启Xcode
3. 检查系统日期和时间设置

### 问题3：设备不支持
**解决方案：**
1. 使用模拟器进行测试
2. 确保 deployment target 设置正确（iOS 14.0+）

### 问题4：权限问题
**检查Info.plist权限：**
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>请打开相册完整权限选择视频用来转换为实况Live图</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>请打开相册完整权限选择视频用来转换为实况Live图</string>
```

## ✅ 验证成功

成功设置后，你应该能够：
- ✅ 在Xcode中无错误构建项目
- ✅ 在模拟器上运行应用
- ✅ 查看应用界面预览
- ✅ 测试核心功能

## 🎯 下一步

设置完成后，你可以：
1. 运行应用查看真实界面
2. 测试视频选择功能
3. 验证Live Photo转换
4. 优化用户体验

## 📞 需要帮助？

如果遇到问题，请检查：
1. Apple ID是否正确添加
2. Bundle ID是否唯一
3. 网络连接是否正常
4. Xcode是否为最新版本

---

*设置完成后，你就可以在Xcode中运行项目，预览真实的应用界面了！*