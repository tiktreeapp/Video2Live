# Video2Live

从视频一键生成 Live Photo 的 iOS 应用（SwiftUI）。

## 功能
### 核心功能
- **首页 UI 与基本交互** - 现代化的用户界面，支持多视频选择
- **智能视频预处理** - 自动验证视频格式，优化不适合的视频
- **核心 Video2Live 流程** - 从视频生成高质量的 Live Photo
- **转换质量选择** - 提供高质量、平衡、快速、自定义四种模式

### 高级功能
- **智能关键帧选择** - 基于运动分析和图像质量自动选择最佳静态图像
- **视频片段优化** - 自动截取最稳定的1-5秒视频片段
- **用户友好错误处理** - 智能错误分析和详细的解决建议
- **实时进度显示** - 详细的转换进度和状态反馈

## 技术亮点
- **SwiftUI 现代化界面** - 响应式设计，适配各种屏幕尺寸
- **AVFoundation 深度集成** - 专业级视频处理能力
- **智能预处理系统** - VideoPreprocessor 类提供完整的视频优化
- **错误处理机制** - LivePhotoErrorHandler 提供分类错误处理
- **iOS 官方 Live Photo API** - 使用 PHLivePhoto 确保兼容性

## 环境要求
- Xcode 15+
- iOS 16+（支持 iOS 17.2+）
- Swift 5.0+
- macOS 13.7+（开发环境）

## 快速开始
```bash
git clone https://github.com/tiktreeapp/Video2Live.git
cd Video2Live
open Video2Live.xcodeproj
```
选择模拟器或真机运行。

## 主要特性
### 视频预处理
- 自动格式验证和转码
- 分辨率优化（支持最高1080p）
- 帧率调整（24-60fps）
- 时长智能截取（1-5秒最佳片段）

### 质量优化
- **高质量模式** - 1080p分辨率，5秒时长，最高画质
- **平衡模式** - 720p分辨率，3秒时长，推荐设置
- **快速模式** - 480p分辨率，2秒时长，最快处理
- **自定义模式** - 保持原始设置

### 错误处理
- 智能错误分类（AVFoundation、Photos、预处理等）
- 用户友好的错误提示
- 详细的解决建议
- 容错处理机制

## 项目结构
```
Video2Live/
├── ContentView.swift                    # 主界面和转换逻辑
├── VideoPreprocessor.swift              # 视频预处理和优化
├── LivePhotoConverter.swift             # Live Photo转换核心
├── ErrorHandler.swift                   # 错误处理系统
├── ConversionProgressView.swift         # 进度显示组件
├── SettingsView.swift                   # 设置界面
└── Assets.xcassets/                     # 应用资源
```

## 路线图
- [ ] 批量视频处理功能
- [ ] 更多导出格式支持
- [ ] 高级编辑功能（裁剪、滤镜）
- [ ] iCloud 同步支持
- [ ] 更多语言本地化

## 版本历史
- **v0.2.0** - 智能预处理、质量优化、错误处理系统
- **v0.1.0** - 基础功能实现，首页UI和核心转换流程

## 许可证
MIT（可按需调整）