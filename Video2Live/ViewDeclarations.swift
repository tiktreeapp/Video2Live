import SwiftUI
import UIKit
import Photos
import AVFoundation

// 导入错误处理器
struct LivePhotoErrorHandler {
    struct ErrorInfo {
        let title: String
        let message: String
        let suggestions: [String]
    }

    static func analyzeError(_ error: NSError) -> ErrorInfo {
        let title = "发生错误 (\(error.domain) - \(error.code))"
        let message = error.localizedDescription.isEmpty ? "\(error)" : error.localizedDescription
        var suggestions: [String] = []

        switch error.domain {
        case "PermissionError", "PHPhotosErrorDomain":
            suggestions.append(contentsOf: [
                "前往 设置 > 隐私 > 照片，授予本应用\"所有照片\"权限",
                "若已授权但仍失败，重启应用后重试"
            ])
        case "ExportError":
            suggestions.append(contentsOf: [
                "检查可用存储空间是否充足",
                "避免选择损坏或过短（<1秒）的视频",
                "尝试转换其他视频以排除源文件问题"
            ])
        case "FileNotFound":
            suggestions.append("视频源文件不存在或已被系统清理，请重新选择视频")
        case "InvalidVideo":
            suggestions.append("视频文件没有有效视频轨道，请更换为标准格式（.mov/.mp4）")
        default:
            break
        }

        // 通用建议兜底
        suggestions.append(contentsOf: [
            "避免选择极短或极小体积的视频",
            "切换\"转换质量\"为 平衡/快速 再试",
            "重启应用或重启设备后再次尝试"
        ])

        return ErrorInfo(title: title, message: message, suggestions: suggestions)
    }
}

// 视图声明文件 - 解决scope识别问题
// 使用类型别名来确保跨文件识别

// 基本视图协议，所有自定义视图都遵循
protocol AppView: View {
    associatedtype Content: View
    var content: Content { get }
}

// 为视图提供统一的标识
extension View {
    var viewIdentifier: String {
        return String(describing: type(of: self))
    }
}

// 全局共享：视频缩略图模型，供多个视图复用
struct VideoThumbnail: Identifiable, Hashable {
    let id = UUID()
    let image: UIImage
    let duration: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// Global time segment enum for conversion logic (UI may not expose it)
enum TimeSegment: String {
    case first = "First 3s"
    case middle = "Middle 3s"
    case last = "Last 3s"
}

// 转换状态枚举
enum ProgressState {
    case converting
    case completed
    case failed
}

// 转换进度弹窗 - iOS默认风格
struct ConversionProgressView: View {
    @Binding var isPresented: Bool
    var onClose: (() -> Void)? = nil
    @State private var overallProgress: Double = 0.0
    @State private var currentVideoIndex: Int = 0
    @State private var totalVideos: Int = 0
    @State private var videoProgresses: [Double] = []
    @State private var conversionState: ProgressState = .converting
    @State private var convertedAssetIDs: [String] = []
    
    let previewImages: [UIImage]
    let onConversionStart: (@escaping (Double, Int) -> Void, @escaping (Result<[String], Error>) -> Void) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("Converting to Live Photo")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if conversionState == .converting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 24)
            .background(Color(.systemGray6))
            
            // 内容区域
            ScrollView {
                VStack(spacing: 16) {
                    // 总体进度
                    if conversionState == .converting {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Overall Progress")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("\(Int(overallProgress * 100))%")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                            
                            ProgressView(value: overallProgress)
                                .progressViewStyle(.linear)
                                .tint(.blue)
                        }
                        .padding(.horizontal)
                    }
                    
                    // 视频列表进度
                    if !previewImages.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(0..<min(previewImages.count, videoProgresses.count), id: \.self) { index in
                                VideoProgressRow(
                                    previewImage: previewImages[index],
                                    progress: videoProgresses[index],
                                    isCompleted: index < currentVideoIndex || conversionState == .completed,
                                    videoNumber: index + 1
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // 状态信息
                    switch conversionState {
                    case .converting:
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.blue)
                            Text("Converting video \(currentVideoIndex + 1) of \(totalVideos)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                    case .completed:
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("All videos converted successfully!")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal)
                        
                    case .failed:
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Conversion failed")
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            
            // 按钮区域
            if conversionState != .converting {
                Divider()
                    .background(Color(.systemGray4))
                
                HStack(spacing: 8) {
                    Button("Close") {
                        onClose?()
                        isPresented = false
                    }
                    .font(.body)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    
                    if conversionState == .completed && !convertedAssetIDs.isEmpty {
                        Button("View in Photos") {
                            openInPhotos()
                        }
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            startConversion()
        }
    }
    
    private func startConversion() {
        totalVideos = previewImages.count
        videoProgresses = Array(repeating: 0.0, count: totalVideos)
        convertedAssetIDs = []
        currentVideoIndex = 0
        
        onConversionStart(
            { overallProgress, videoIndex in
                withAnimation {
                    self.overallProgress = overallProgress
                    if videoIndex < self.videoProgresses.count {
                        self.currentVideoIndex = videoIndex
                    }
                }
            },
            { result in
                withAnimation {
                    switch result {
                    case .success(let assetIDs):
                        self.convertedAssetIDs = assetIDs
                        self.conversionState = .completed
                        self.overallProgress = 1.0
                        for i in 0..<self.videoProgresses.count {
                            self.videoProgresses[i] = 1.0
                        }
                    case .failure(let error):
                        self.conversionState = .failed
                        print("❌ Conversion failed: \(error)")
                        
                        // 使用新的错误处理器提供用户友好的错误信息
                        let errorInfo = LivePhotoErrorHandler.analyzeError(error as NSError)
                        print("🚨 错误分析结果:")
                        print("标题: \(errorInfo.title)")
                        print("消息: \(errorInfo.message)")
                        print("建议解决方案:")
                        for (index, suggestion) in errorInfo.suggestions.enumerated() {
                            print("\(index + 1). \(suggestion)")
                        }
                        
                        // 显示更友好的错误信息
                        if let nsError = error as NSError? {
                            if let userFriendlyMessage = nsError.userInfo["userFriendlyMessage"] as? String {
                                print("用户友好信息: \(userFriendlyMessage)")
                            }
                        }
                    }
                }
            }
        )
    }
    
    private func openInPhotos() {
        guard !convertedAssetIDs.isEmpty else { return }
        
        // 打开照片应用
        if let photosURL = URL(string: "photos-redirect://") {
            UIApplication.shared.open(photosURL)
        }
    }
}

// 单个视频进度行
struct VideoProgressRow: View {
    let previewImage: UIImage
    let progress: Double
    let isCompleted: Bool
    let videoNumber: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // 缩略图
            Image(uiImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .cornerRadius(8)
                .clipped()
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Video \(videoNumber)")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                    } else {
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(isCompleted ? .green : .blue)
                    .scaleEffect(x: 1, y: 0.8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray6))
                .opacity(isCompleted ? 0.8 : 1.0)
        )
    }
}