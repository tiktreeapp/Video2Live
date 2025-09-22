import SwiftUI
import Photos

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
                        let errorInfo = LivePhotoErrorHandler.analyzeError(error)
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

#Preview {
    ConversionProgressView(
        isPresented: .constant(true),
        previewImages: [
            UIImage(systemName: "photo")!,
            UIImage(systemName: "video")!
        ],
        onConversionStart: { progressHandler, completionHandler in
            // 模拟转换过程
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                progressHandler(0.5, 0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                completionHandler(.success(["asset1", "asset2"]))
            }
        }
    )
}