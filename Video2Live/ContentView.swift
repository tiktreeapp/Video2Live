//
//  ContentView.swift
//  Video2Live
//
//  Created by Sun on 2025/3/17.
//

import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import Photos
import MobileCoreServices
import CoreGraphics
import UIKit

// 内联轻量版本：错误分析工具
struct LivePhotoErrorHandler {
    struct ErrorInfo {
        let title: String
        let message: String
        let suggestions: [String]
    }

    static func analyzeError(_ error: Error) -> ErrorInfo {
        let nsError = error as NSError
        let title = "发生错误 (\(nsError.domain) - \(nsError.code))"
        let message = nsError.localizedDescription.isEmpty ? "\(error)" : nsError.localizedDescription
        var suggestions: [String] = [
            "确认已允许“照片”读写权限",
            "确保视频文件有效且未损坏",
            "尝试更短时长或较低质量进行转换",
            "重启应用后重试"
        ]
        if nsError.domain == "ExportError" {
            suggestions.insert("检查存储空间是否充足", at: 0)
        }
        return ErrorInfo(title: title, message: message, suggestions: suggestions)
    }

    static func formatErrorForDisplay(_ error: Error) -> String {
        let info = analyzeError(error)
        let sug = info.suggestions.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n")
        return "\(info.title)\n\n\(info.message)\n\n建议：\n\(sug)"
    }
}

// 内联轻量版本：视频预处理器（当前直接透传）
// 注意：若要启用真正的预处理逻辑，请将 VideoPreprocessor.swift 加入 Xcode Target，并移除此内联实现
class VideoPreprocessor {
    func preprocessVideoForLivePhoto(
        inputURL: URL,
        quality: ConversionQuality = .balanced,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        completion(.success(inputURL))
    }
}

/// 转换质量选项
enum ConversionQuality: String, CaseIterable {
    case high = "高质量"
    case balanced = "平衡"
    case fast = "快速"
    case custom = "自定义"
    
    var description: String {
        switch self {
        case .high:
            return "最高质量，文件较大，处理时间较长"
        case .balanced:
            return "平衡质量和速度，推荐使用"
        case .fast:
            return "最快处理速度，质量适中"
        case .custom:
            return "自定义设置"
        }
    }
    
    var presetName: String {
        switch self {
        case .high:
            return AVAssetExportPresetHighestQuality
        case .balanced:
            return AVAssetExportPresetMediumQuality
        case .fast:
            return AVAssetExportPresetLowQuality
        case .custom:
            return AVAssetExportPresetPassthrough
        }
    }
    
    var maxDuration: Double {
        switch self {
        case .high:
            return 5.0
        case .balanced:
            return 3.0
        case .fast:
            return 2.0
        case .custom:
            return 5.0
        }
    }
    
    var targetResolution: CGSize? {
        switch self {
        case .high:
            return CGSize(width: 1920, height: 1080) // 1080p
        case .balanced:
            return CGSize(width: 1280, height: 720)  // 720p
        case .fast:
            return CGSize(width: 640, height: 480)   // 480p
        case .custom:
            return nil // 保持原始分辨率
        }
    }
}

struct VideoThumbnail: Identifiable, Hashable {
    let id = UUID()
    let image: UIImage
    let duration: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ContentView: View {
    @State private var selectedVideos: [PhotosPickerItem] = []
    @State private var videoThumbnails: [VideoThumbnail] = []
    @State private var selectedTab: Int = 0
    @State private var showingConversion = false
    @State private var selectedPreviewImage: UIImage?
    @State private var isConverting = false
    @State private var conversionProgress: Double = 0.0
    @State private var conversionState: ProcessingStatus = .idle
    @State private var convertedAssetID: String? = nil
    @State private var customMessage: String? = nil
    @State private var showingProgressView = false
    @State private var videoProgresses: [Double] = []
    @State private var currentVideoIndex = 0
    @State private var selectedQuality: ConversionQuality = .balanced
    @State private var showingErrorAlert = false
    @State private var errorMessage: String = ""
    
    enum ProcessingStatus {
        case idle, converting, completed, failed
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                VStack(spacing: 0) {
                    // 视频选择区域
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color(.systemGray6), .white]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 400)
                        
                        VStack {
                            if !videoThumbnails.isEmpty {
                                ScrollView {
                                    LazyVGrid(columns: [
                                        GridItem(.flexible()),
                                        GridItem(.flexible()),
                                        GridItem(.flexible())
                                    ], spacing: 15) {
                                        ForEach(videoThumbnails) { thumbnail in
                                            ZStack(alignment: .bottomLeading) {
                                                Image(uiImage: thumbnail.image)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill) // 保持原始比例
                                                    .frame(width: 100, height: 100)
                                                    .clipped() // 裁剪超出部分
                                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                                    .overlay(
                                                        GeometryReader { geometry in
                                                            Color.clear.onAppear {
                                                                // 确保图片居中显示
                                                                let size = geometry.size
                                                                let imageSize = thumbnail.image.size
                                                                let scale = max(size.width / imageSize.width, size.height / imageSize.height)
                                                                let width = imageSize.width * scale
                                                                let height = imageSize.height * scale
                                                                let x = (width - size.width) / 2
                                                                let y = (height - size.height) / 2
                                                                // 可以根据需要调整offset
                                                            }
                                                        }
                                                    )
                                                
                                                // 视频时长和图标的半透明背景
                                                HStack {
                                                    Image(systemName: "video.fill")
                                                        .foregroundColor(.white)
                                                        .font(.system(size: 12))
                                                    Text(thumbnail.duration)
                                                        .foregroundColor(.white)
                                                        .font(.system(size: 12))
                                                }
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 4)
                                                .background(Color.black.opacity(0.6))
                                                .cornerRadius(6)
                                                .padding([.bottom, .leading], 6)
                                            }
                                        }
                                    }
                                    .padding()
                                }
                                .frame(maxHeight: 380)
                            }
                        }
                        
                        // + 按钮使用ZStack独立定位
                        if videoThumbnails.count < 6 {
                            PhotosPicker(selection: $selectedVideos,
                                        matching: .videos,
                                        photoLibrary: .shared()) {
                                Image(systemName: "plus.circle.fill")
                                    .resizable()
                                    .frame(width: 45, height: 45)
                                    .foregroundColor(.blue)
                            }
                            .offset(y: 90) // 使用offset来调整位置，不会影响其他元素
                            .onChange(of: selectedVideos) { _, videos in
                                if videos.count > 6 {
                                    selectedVideos = Array(videos.prefix(6))
                                }
                                Task {
                                    await loadVideoThumbnails()
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    
                    Spacer()
                        .frame(height: 20)
                    
#if false
                    // 质量选择器
                    VStack(alignment: .leading, spacing: 10) {
                        Text("转换质量")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal)
                        
                        Picker("转换质量", selection: $selectedQuality) {
                            ForEach(ConversionQuality.allCases, id: \.self) { quality in
                                VStack(alignment: .leading) {
                                    Text(quality.rawValue)
                                        .font(.subheadline)
                                    Text(quality.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .tag(quality)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                    }
#endif
                    
                    Spacer()
                        .frame(height: 20)
                    
                    // 转换按钮
                    Button(action: {
                        print("🔄 开始转换流程")
                        print("选中的视频数量: \(selectedVideos.count)")
                        
                        if let firstVideo = selectedVideos.first {
                            print("✅ 找到第一个视频，开始处理")
                            // 加载视频数据并转换
                            Task {
                                do {
                                    print("📹 加载视频数据...")
                                    let videoData = try await firstVideo.loadTransferable(type: Data.self)
                                    print("✅ 视频数据加载成功")
                                    
                                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                                    guard let videoData = videoData else {
                                        print("❌ 视频数据为空")
                                        return
                                    }
                                    
                                    print("💾 保存临时文件...")
                                    try videoData.write(to: tempURL)
                                    print("✅ 临时文件保存成功: \(tempURL.path)")

                                    // 获取视频时长
                                    let asset = AVAsset(url: tempURL)
                                    let duration = try await asset.load(.duration).seconds
                                    print("⏱️ 视频时长: \(duration)秒")

                                    // 使用视频中间点作为预览图
                                    let time = duration / 2
                                    print("🖼️ 提取预览图，时间点: \(time)秒")

                                    // 提取关键帧
                                    let imageGenerator = AVAssetImageGenerator(asset: asset)
                                    let cgImage = try await imageGenerator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
                                    selectedPreviewImage = UIImage(cgImage: cgImage)
                                    print("✅ 预览图提取成功")
                                    
                                    // 显示新的iOS默认风格弹窗
                                    print("🎯 显示转换进度弹窗")
                                    showingProgressView = true

                                    // 清理临时文件
                                    try FileManager.default.removeItem(at: tempURL)
                                    print("🧹 临时文件清理完成")
                                } catch {
                                    print("❌ 转换失败: \(error)")
                                    print("错误详情: \(String(describing: error))")
                                    
                                    // 使用新的错误处理器提供用户友好的错误信息
                                    let errorInfo = LivePhotoErrorHandler.analyzeError(error)
                                    print("🚨 错误分析结果:")
                                    print("标题: \(errorInfo.title)")
                                    print("消息: \(errorInfo.message)")
                                    print("建议解决方案:")
                                    for (index, suggestion) in errorInfo.suggestions.enumerated() {
                                        print("\(index + 1). \(suggestion)")
                                    }
                                    
                                    // 显示用户友好的错误信息
                                    errorMessage = LivePhotoErrorHandler.formatErrorForDisplay(error)
                                    showingErrorAlert = true
                                }
                            }
                        } else {
                            print("⚠️ 没有选中的视频")
                        }
                    }) {
                        Text("Convert")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.6)
                            .padding()
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [.purple, .blue]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(25)
                    }
                    
                    Spacer()
                }
                .navigationTitle("Video2Live")
            }
            .tabItem {
                Image(systemName: "play.circle.fill")
                Text("Video2Live")
            }
            .tag(0)
            
            // 临时解决方案 - 使用条件编译避免scope问题
            #if canImport(UIKit)
            Text("Video2Wallpaper")
                .tabItem {
                    Image(systemName: "square.grid.2x2.fill")
                    Text("Video2Wallpaper")
                }
                .tag(1)
            
            Text("Settings")
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Setting")
                }
                .tag(2)
            #endif
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 0) // 移除底部额外空间
                Color(.systemGray5)
                    .frame(height: 0.5)
                    .offset(y: -48) // 上移48像素
            }
            .background(.white)
        }
        .tint(.blue)
        .sheet(isPresented: $showingProgressView, onDismiss: {
            resetHomeState()
        }) {
            ConversionProgressView(
                isPresented: $showingProgressView,
                previewImages: videoThumbnails.map { $0.image },
                onConversionStart: { overallProgressHandler, completionHandler in
                    // 实际的转换逻辑
                    performConversion(
                        overallProgressHandler: overallProgressHandler,
                        completionHandler: completionHandler
                    )
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        
        // 新的iOS默认风格弹窗 - 使用全屏遮罩隐藏底部栏和顶部标题
        .overlay(
            Group {
                if false && showingProgressView {
                    // 全屏遮罩层
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture {
                            // 防止点击背景关闭
                        }
                        .zIndex(1000) // 确保在最上层
                        .transition(.opacity)
                    
                    // 弹窗内容
                    VStack {
                        Spacer()
                        
                        ConversionProgressView(
                            isPresented: $showingProgressView,
                            previewImages: videoThumbnails.map { $0.image },
                            onConversionStart: { overallProgressHandler, completionHandler in
                                // 实际的转换逻辑
                                performConversion(
                                    overallProgressHandler: overallProgressHandler,
                                    completionHandler: completionHandler
                                )
                            }
                        )
                        .padding(.horizontal, 20)
                        .zIndex(1001) // 确保在遮罩层之上
                        
                        Spacer()
                    }
                    .transition(.scale)
                }
                
                // 错误提示弹窗
                if showingErrorAlert {
                    // 全屏遮罩层
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showingErrorAlert = false
                        }
                        .zIndex(2000)
                        .transition(.opacity)
                    
                    // 错误提示内容
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        
                        Text("转换失败")
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        ScrollView {
                            Text(errorMessage)
                                .font(.body)
                                .multilineTextAlignment(.leading)
                                .padding()
                        }
                        .frame(maxHeight: 300)
                        
                        HStack(spacing: 12) {
                            Button("复制诊断信息") {
                                let report = LogCollector.shared.report(extra: [
                                    "SelectedVideos": "\(selectedVideos.count)"
                                ])
                                UIPasteboard.general.string = report
                            }
                            .font(.headline)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)

                            Button("知道了") {
                                showingErrorAlert = false
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(25)
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(20)
                    .padding(.horizontal, 30)
                    .zIndex(2001)
                    .transition(.scale)
                }
            }
        )
    }
    
    // 执行转换的简化逻辑 - 主要逻辑在ConversionProgressView中
    private func performConversion(
        overallProgressHandler: @escaping (Double, Int) -> Void,
        completionHandler: @escaping (Result<[String], Error>) -> Void
    ) {
        // 重置状态
        videoProgresses = Array(repeating: 0.0, count: selectedVideos.count)
        currentVideoIndex = 0
        conversionProgress = 0.0
        convertedAssetID = nil
        
        // 使用原有的转换逻辑，但适配新的进度显示
        Task {
            do {
                // 检查相册权限
                let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                guard status == .authorized else {
                    completionHandler(.failure(NSError(domain: "PermissionError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"])))
                    return
                }
                
                var convertedAssetIDs: [String] = []
                
                // 处理多个视频 - 使用基于同行经验的优化方案
                for (index, video) in selectedVideos.enumerated() {
                    guard let pickerItem = video as? PhotosPickerItem else { continue }
                    
                    // 更新总体进度和当前视频索引
                    let overallProgress = Double(index) / Double(selectedVideos.count)
                    await MainActor.run {
                        overallProgressHandler(overallProgress, index)
                        currentVideoIndex = index
                        conversionProgress = overallProgress
                    }
                    
                    // 更新单个视频进度
                    await MainActor.run {
                        if index < videoProgresses.count {
                            videoProgresses[index] = 0.3 // 开始处理
                        }
                    }
                    
                    // 加载视频数据
                    guard let videoData = try? await pickerItem.loadTransferable(type: Data.self) else {
                        continue
                    }
                    
                    // 创建临时文件
                    let tempDir = FileManager.default.temporaryDirectory
                    let sourceURL = tempDir.appendingPathComponent("source_\(UUID().uuidString).mov")
                    
                    defer {
                        try? FileManager.default.removeItem(at: sourceURL)
                    }
                    
                    // 保存视频数据
                    try videoData.write(to: sourceURL)
                    print("📹 视频文件已保存: \(sourceURL.path)")
                    
                    // 使用新的LivePhotoUtil进行转换（基于同行经验）
                    let assetID = try await self.convertVideoToLivePhotoWithFallback(
                        videoURL: sourceURL,
                        index: index,
                        quality: selectedQuality,
                        overallProgressHandler: overallProgressHandler
                    )
                    
                    convertedAssetIDs.append(assetID)
                    
                    // 完成单个视频
                    await MainActor.run {
                        if index < videoProgresses.count {
                            videoProgresses[index] = 1.0 // 完成
                        }
                    }
                }
                
                // 完成所有视频
                let finalAssetID = convertedAssetIDs.last
                await MainActor.run {
                    conversionProgress = 1.0
                    convertedAssetID = finalAssetID
                }
                
                completionHandler(.success(convertedAssetIDs))
                
            } catch {
                print("❌ 转换失败: \(error)")
                print("错误详情: \(String(describing: error))")
                
                // 使用新的错误处理器提供用户友好的错误信息
                let errorInfo = LivePhotoErrorHandler.analyzeError(error)
                print("🚨 错误分析结果:")
                print("标题: \(errorInfo.title)")
                print("消息: \(errorInfo.message)")
                print("建议: \(errorInfo.suggestions.joined(separator: ", "))")
                
                // 创建包含详细错误信息的NSError
                let detailedError = NSError(
                    domain: "ConversionError",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: errorInfo.message,
                        "errorTitle": errorInfo.title,
                        "errorSuggestions": errorInfo.suggestions,
                        "originalError": error,
                        "userFriendlyMessage": LivePhotoErrorHandler.formatErrorForDisplay(error)
                    ]
                )
                
                completionHandler(.failure(detailedError))
            }
        }
    }
    
    // 导出视频片段
    private func exportVideoClip(from asset: AVAsset, timeRange: CMTimeRange, to outputURL: URL) async throws -> String {
        let composition = AVMutableComposition()
        
        // 添加视频轨道
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let assetVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "ExportError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to add video track"])
        }
        
        let preferredTransform = try await assetVideoTrack.load(.preferredTransform)
        videoTrack.preferredTransform = preferredTransform
        try videoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: .zero)
        
        // 添加音频轨道
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }
        
        // 创建导出会话
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "ExportError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }
        
        let uuid = UUID().uuidString
        let metadata = [
            createMetadataItem(key: "com.apple.quicktime.live-photo", value: "1"),
            createMetadataItem(key: "com.apple.quicktime.content.identifier", value: uuid),
            createMetadataItem(key: "com.apple.quicktime.still-image-time", value: "0")
        ]
        
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov
        exporter.metadata = metadata
        exporter.shouldOptimizeForNetworkUse = true
        
        await exporter.export()
        
        guard exporter.status == .completed else {
            throw NSError(domain: "ExportError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
        }
        
        return uuid
    }
    
    // 保存到相册
    private func saveToPhotoLibrary(image: UIImage, videoURL: URL, contentID: String) async throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let photoURL = tempDir.appendingPathComponent("IMG_\(contentID).JPG")
        let newVideoURL = tempDir.appendingPathComponent("IMG_\(contentID).MOV")
        
        defer {
            try? FileManager.default.removeItem(at: photoURL)
            try? FileManager.default.removeItem(at: newVideoURL)
        }
        
        // 保存图片
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "SaveError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image data"])
        }
        try imageData.write(to: photoURL)
        
        // 复制视频
        try FileManager.default.copyItem(at: videoURL, to: newVideoURL)
        
        // 保存到相册
        var assetID: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: photoURL, options: nil)
            request.addResource(with: .pairedVideo, fileURL: newVideoURL, options: nil)
            assetID = request.placeholderForCreatedAsset?.localIdentifier
        }
        
        return assetID ?? contentID
    }
    
    // 重置转换状态
    private func resetConversionState() {
        isConverting = false
        conversionState = .idle
        conversionProgress = 0.0
        convertedAssetID = nil
    }

    // 关闭弹窗后回到首页初始状态
    private func resetHomeState() {
        selectedVideos.removeAll()
        videoThumbnails.removeAll()
        showingConversion = false
        selectedPreviewImage = nil
        isConverting = false
        conversionProgress = 0.0
        conversionState = .idle
        convertedAssetID = nil
        customMessage = nil
        showingProgressView = false
        videoProgresses.removeAll()
        currentVideoIndex = 0
    }
    
    // 打开照片应用
    private func openInPhotos(assetID: String) {
        // 尝试打开照片应用并定位到指定资源
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        if result.firstObject != nil {
            // 打开照片应用
            if let photosURL = URL(string: "photos-redirect://") {
                UIApplication.shared.open(photosURL)
            }
        }
    }
    
    // 创建元数据项的辅助函数
    private func createMetadataItem(key: String, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.key = key as NSString
        item.keySpace = AVMetadataKeySpace.quickTimeMetadata
        item.value = value as NSString
        return item
    }
    
    // 加载视频缩略图
    private func loadVideoThumbnails() async {
        videoThumbnails.removeAll()
        
        for video in selectedVideos {
            do {
                if let videoData = try await video.loadTransferable(type: Data.self) {
                    let tempDir = FileManager.default.temporaryDirectory
                    let tempURL = tempDir.appendingPathComponent(UUID().uuidString + ".mov")
                    
                    do {
                        try videoData.write(to: tempURL)
                        print("✅ 视频数据已写入临时文件: \(tempURL.path)")
                        
                        let asset = AVAsset(url: tempURL)
                        if let thumbnail = try await asset.generateThumbnail() {
                            let duration = try await asset.load(.duration).seconds
                            let formattedDuration = formatDuration(duration)
                            let videoThumbnail = VideoThumbnail(
                                image: thumbnail,
                                duration: formattedDuration
                            )
                            DispatchQueue.main.async {
                                videoThumbnails.append(videoThumbnail)
                            }
                        }
                        
                        try? FileManager.default.removeItem(at: tempURL)
                    } catch {
                        print("❌ 写入临时文件失败: \(error)")
                    }
                }
            } catch {
                print("❌ 加载视频失败: \(error)")
            }
        }
    }
    
    // 辅助函数：格式化视频时长
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
    
    // MARK: - 视频转换辅助方法
    
    private func convertVideoToLivePhotoWithFallback(
        videoURL: URL,
        index: Int,
        quality: ConversionQuality,
        overallProgressHandler: @escaping (Double, Int) -> Void
    ) async throws -> String {
        print("🔄 [ContentView] 开始转换视频: \(videoURL.path)")
        print("🔄 [ContentView] 视频文件存在: \(FileManager.default.fileExists(atPath: videoURL.path))")
        
        // 检查文件大小
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
            if let fileSize = attributes[.size] as? Int64 {
                let sizeInMB = Double(fileSize) / 1024.0 / 1024.0
                print("🔄 [ContentView] 视频文件大小: \(String(format: "%.2f", sizeInMB)) MB")
            }
        } catch {
            print("⚠️ [ContentView] 无法获取文件大小: \(error)")
        }
        
        // 步骤1: 视频预处理
        print("🔄 [ContentView] 开始视频预处理...")
        print("🔄 [ContentView] 选择的质量: \(quality.rawValue)")
        let preprocessor = VideoPreprocessor()
        let processedVideoURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            preprocessor.preprocessVideoForLivePhoto(inputURL: videoURL, quality: quality) { result in
                switch result {
                case .success(let processedURL):
                    print("✅ [ContentView] 视频预处理成功: \(processedURL.path)")
                    continuation.resume(returning: processedURL)
                case .failure(let error):
                    print("⚠️ [ContentView] 视频预处理失败，使用原始文件: \(error)")
                    // 如果预处理失败，回退到使用原始文件
                    continuation.resume(returning: videoURL)
                }
            }
        }
        
        // 步骤2: 使用预处理后的视频进行Live Photo转换
        print("🔄 [ContentView] 使用预处理后的视频进行Live Photo转换...")
        return try await withCheckedThrowingContinuation { continuation in
            MediaAssetProcessor.shared.createLivePhotoDirectly(
                from: processedVideoURL
            ) { result in
                switch result {
                case .success(let assetID):
                    print("✅ [ContentView] 转换成功! Asset ID: \(assetID)")
                    continuation.resume(returning: assetID)
                case .failure(let error):
                    print("❌ [ContentView] 转换失败: \(error)")
                    print("❌ [ContentView] 错误详情: \(String(describing: error))")
                    
                    if let nsError = error as NSError? {
                        print("❌ [ContentView] 错误域: \(nsError.domain), 错误码: \(nsError.code)")
                        print("❌ [ContentView] 错误描述: \(nsError.localizedDescription)")
                        print("❌ [ContentView] 用户信息: \(nsError.userInfo)")
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // 添加新的转换功能
    func convertToLivePhoto(videoURL: URL, timeRange: CMTimeRange) async throws -> PHLivePhoto {
        // 1. 提取关键帧
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        let cgImage = try await imageGenerator.image(at: timeRange.start).image
        let image = UIImage(cgImage: cgImage)
        
        // 2. 分割视频片段
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                   preferredTrackID: kCMPersistentTrackID_Invalid)
        try videoTrack?.insertTimeRange(timeRange,
                                      of: try await asset.loadTracks(withMediaType: .video)[0],
                                      at: .zero)
        
        // 3. 导出配对文件
        let documentsPath = FileManager.default.temporaryDirectory
        let photoURL = documentsPath.appendingPathComponent("photo.jpg")
        let videoURL = documentsPath.appendingPathComponent("video.mov")
        
        // 4. 创建Live Photo
        return try await withCheckedThrowingContinuation { continuation in
            PHLivePhoto.request(withResourceFileURLs: [photoURL, videoURL],
                              placeholderImage: image,
                              targetSize: .zero,
                              contentMode: .aspectFit) { livePhoto, info in
                if let livePhoto = livePhoto {
                    continuation.resume(returning: livePhoto)
                } else {
                    continuation.resume(throwing: NSError(domain: "LivePhotoError", code: -1))
                }
            }
        }
    }
}

// AVAsset 扩展
extension AVAsset {
    func generateThumbnail() async throws -> UIImage? {
        let imageGenerator = AVAssetImageGenerator(asset: self)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 300, height: 300)
        
        let cgImage = try await imageGenerator.image(at: .zero).image
        return UIImage(cgImage: cgImage)
    }
}

// 在处理完成后添加分享选项
struct ShareLivePhotoView: View {
    let image: UIImage
    let videoURL: URL
    
    var body: some View {
        VStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
            
            // 使用标准 Button 替代 ShareLink
            Button(action: {
                // 创建活动视图控制器
                let items: [Any] = [image]
                let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
                
                // 获取当前的 UIWindow 场景
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    rootVC.present(activityVC, animated: true)
                }
            }) {
                Label("分享图片", systemImage: "square.and.arrow.up")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

