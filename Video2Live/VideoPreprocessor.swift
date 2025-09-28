import Foundation
import AVFoundation
import Photos
import UIKit

/// 视频预处理器 - 专为Live Photo转换优化
class VideoPreprocessor {
    
    // 日志记录
    private func log(_ message: String) {
        print("🎬 [VideoPreprocessor] \(message)")
    }
    
    /// 预处理视频文件，确保符合Live Photo要求
    func preprocessVideoForLivePhoto(
        inputURL: URL,
        quality: ConversionQuality = .balanced,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        Task {
            do {
                log("开始预处理视频: \(inputURL.path), 质量设置: \(quality)")
                
                // 1. 验证输入文件
                try await validateInputFile(inputURL)
                
                // 2. 分析视频属性
                let videoInfo = try await analyzeVideo(inputURL)
                log("视频分析完成: \(videoInfo)")
                
                // 3. 检查是否需要转码
                if needsTranscoding(videoInfo) {
                    log("视频需要转码处理")
                    let processedURL = try await transcodeVideo(inputURL, videoInfo: videoInfo, quality: quality)
                    log("视频转码完成: \(processedURL.path)")
                    completion(.success(processedURL))
                } else {
                    log("视频格式符合要求，无需转码")
                    // 根据质量设置，可能仍需要优化
                    if quality == .high {
                        log("高质量模式：即使格式符合也进行优化")
                        let processedURL = try await transcodeVideo(inputURL, videoInfo: videoInfo, quality: quality)
                        completion(.success(processedURL))
                    } else {
                        completion(.success(inputURL))
                    }
                }
                
            } catch {
                log("❌ 预处理失败: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    /// 验证输入文件
    private func validateInputFile(_ url: URL) async throws {
        log("验证输入文件...")
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PreprocessingError.fileNotFound
        }
        
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? Int64 else {
            throw PreprocessingError.invalidFileAttributes
        }
        
        let sizeInMB = Double(fileSize) / 1024.0 / 1024.0
        log("文件大小: \(String(format: "%.2f", sizeInMB)) MB")
        
        if sizeInMB < 0.1 {
            throw PreprocessingError.fileTooSmall
        }
        
        if sizeInMB > 500 {
            log("⚠️ 文件较大，处理可能需要更长时间")
        }
        
        // 检查文件扩展名
        let allowedExtensions = ["mp4", "mov", "m4v", "3gp", "avi", "mkv"]
        let fileExtension = url.pathExtension.lowercased()
        
        if !allowedExtensions.contains(fileExtension) {
            log("⚠️ 文件扩展名可能不支持: \(fileExtension)")
        }
    }
    
    /// 分析视频属性
    private func analyzeVideo(_ url: URL) async throws -> VideoInfo {
        log("分析视频属性...")
        
        let asset = AVAsset(url: url)
        
        // 获取基本信息
        let duration = try await asset.load(.duration)
        let durationInSeconds = duration.seconds
        
        log("视频时长: \(String(format: "%.2f", durationInSeconds)) 秒")
        
        if durationInSeconds < 1.0 {
            throw PreprocessingError.videoTooShort
        }
        
        if durationInSeconds > 10.0 {
            log("⚠️ 视频较长，将截取前10秒")
        }
        
        // 获取视频轨道信息
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw PreprocessingError.noVideoTrack
        }
        
        // 获取视频属性
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        
        log("视频尺寸: \(naturalSize)")
        log("首选变换: \(preferredTransform)")
        
        // 检查格式描述
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        log("格式描述数量: \(formatDescriptions.count)")
        
        // 获取帧率
        let nominalFrameRate = videoTrack.nominalFrameRate
        log("帧率: \(nominalFrameRate) fps")
        
        // 获取音频轨道信息
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        log("音频轨道数量: \(audioTracks.count)")
        
        return VideoInfo(
            duration: durationInSeconds,
            naturalSize: naturalSize,
            frameRate: nominalFrameRate,
            hasAudio: !audioTracks.isEmpty,
            formatDescriptions: formatDescriptions
        )
    }
    
    /// 检查是否需要转码
    private func needsTranscoding(_ info: VideoInfo) -> Bool {
        log("检查是否需要转码...")
        
        // 检查帧率（Live Photo推荐30fps）
        if info.frameRate > 0 && (info.frameRate < 24 || info.frameRate > 60) {
            log("帧率(\(info.frameRate))不在推荐范围(24-60fps)")
            return true
        }
        
        // 检查分辨率（推荐1080p或更低）
        let maxDimension = max(info.naturalSize.width, info.naturalSize.height)
        if maxDimension > 1920 {
            log("分辨率过高，建议降低")
            return true
        }
        
        // 检查时长（Live Photo通常1-3秒）
        if info.duration > 5.0 {
            log("视频时长超过5秒，需要截取")
            return true
        }
        
        // 检查是否有音频（可选，但有音频的Live Photo体验更好）
        if !info.hasAudio {
            log("视频没有音频轨道")
        }
        
        return false
    }
    
    /// 转码视频（支持质量设置）
    private func transcodeVideo(_ inputURL: URL, videoInfo: VideoInfo, quality: ConversionQuality) async throws -> URL {
        log("开始转码视频...")
        
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("processed_\(UUID().uuidString).mov")
        
        let asset = AVAsset(url: inputURL)
        
        // 创建合成
        let composition = AVMutableComposition()
        
        // 添加视频轨道
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw PreprocessingError.exportSessionCreationFailed
        }
        
        // 获取原始视频轨道
        let assetVideoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let assetVideoTrack = assetVideoTracks.first else {
            throw PreprocessingError.noVideoTrack
        }
        
        // 保存原始变换
        let preferredTransform = try await assetVideoTrack.load(.preferredTransform)
        videoTrack.preferredTransform = preferredTransform
        
        // 根据质量设置调整时间范围
        let maxDuration = min(videoInfo.duration, quality.maxDuration)
        let optimalTimeRange = await findOptimalTimeRange(for: videoInfo, in: asset, maxDuration: maxDuration)
        log("选择的视频片段: \(optimalTimeRange.start.seconds)-\(optimalTimeRange.end.seconds) 秒 (质量: \(quality.rawValue))")
        
        try videoTrack.insertTimeRange(optimalTimeRange, of: assetVideoTrack, at: .zero)
        
        // 添加音频轨道（如果有）
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if !audioTracks.isEmpty,
           let audioTrack = audioTracks.first,
           let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compositionAudioTrack.insertTimeRange(optimalTimeRange, of: audioTrack, at: .zero)
            log("已添加音频轨道")
        }
        
        // 根据质量设置选择导出预设
        let presetName = quality.presetName
        log("使用导出预设: \(presetName) (质量: \(quality.rawValue))")
        
        // 创建导出会话
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: presetName
        ) else {
            throw PreprocessingError.exportSessionCreationFailed
        }
        
        // 配置导出参数
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.timeRange = optimalTimeRange
        
        // 添加Live Photo元数据
        let uuid = UUID().uuidString
        let metadata = [
            createMetadataItem(key: "com.apple.quicktime.live-photo", value: "1"),
            createMetadataItem(key: "com.apple.quicktime.content.identifier", value: uuid),
            createMetadataItem(key: "com.apple.quicktime.still-image-time", value: "0")
        ]
        exportSession.metadata = metadata
        
        // 导出视频
        log("导出视频...")
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            let error = exportSession.error ?? PreprocessingError.exportFailed
            log("❌ 导出失败: \(error)")
            throw error
        }
        
        // 验证输出文件
        try await validateOutputFile(outputURL)
        
        log("✅ 转码完成")
        return outputURL
    }
    
    /// 智能选择最佳时间范围
    private func findOptimalTimeRange(for videoInfo: VideoInfo, in asset: AVAsset, maxDuration: Double) async -> CMTimeRange {
        // 如果视频很短，使用整个视频
        if videoInfo.duration <= maxDuration {
            return CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: videoInfo.duration, preferredTimescale: 600)
            )
        }
        
        // 尝试找到最稳定的片段（运动较少的部分）
        do {
            let optimalStartTime = try await findMostStableSegment(in: asset, maxDuration: maxDuration)
            log("找到最稳定片段开始时间: \(optimalStartTime.seconds) 秒")
            
            return CMTimeRange(
                start: CMTime(seconds: optimalStartTime.seconds, preferredTimescale: 600),
                duration: CMTime(seconds: maxDuration, preferredTimescale: 600)
            )
        } catch {
            log("⚠️ 无法找到最优片段，使用默认开始时间: \(error)")
            // 回退到使用视频开始部分
            return CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: maxDuration, preferredTimescale: 600)
            )
        }
    }
    
    /// 找到最稳定的视频片段
    private func findMostStableSegment(in asset: AVAsset, maxDuration: Double) async throws -> CMTime {
        // 简化实现：分析视频的运动情况
        // 在实际应用中，可以使用更复杂的算法
        
        let totalDuration = try await asset.load(.duration).seconds
        let analysisInterval = 0.5 // 每0.5秒分析一次
        
        var minMotionScore = Double.greatestFiniteMagnitude
        var bestStartTime = 0.0
        
        // 分析前10秒，找到运动最少的片段
        let analysisDuration = min(totalDuration, 10.0)
        
        var currentTime = 0.0
        while currentTime + maxDuration <= analysisDuration {
            let motionScore = try await analyzeMotion(in: asset, at: currentTime, duration: maxDuration)
            
            if motionScore < minMotionScore {
                minMotionScore = motionScore
                bestStartTime = currentTime
            }
            
            currentTime += analysisInterval
        }
        
        return CMTime(seconds: bestStartTime, preferredTimescale: 600)
    }
    
    /// 分析指定时间范围内的运动情况
    private func analyzeMotion(in asset: AVAsset, at startTime: Double, duration: Double) async throws -> Double {
        // 提取多个关键帧进行运动分析
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let frameCount = 5 // 分析5个关键帧
        let timeStep = duration / Double(frameCount - 1)
        var frames: [CGImage] = []
        
        for i in 0..<frameCount {
            let time = startTime + Double(i) * timeStep
            let cgImage = try await imageGenerator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
            frames.append(cgImage)
        }
        
        // 计算相邻帧之间的平均差异
        var totalMotionScore = 0.0
        for i in 0..<(frames.count - 1) {
            let motionScore = calculateImageDifference(frames[i], frames[i + 1])
            totalMotionScore += motionScore
        }
        
        let averageMotionScore = totalMotionScore / Double(frames.count - 1)
        log("片段 \(startTime)-\(startTime + duration) 运动评分: \(String(format: "%.3f", averageMotionScore))")
        
        return averageMotionScore
    }
    
    /// 计算两张图片的差异度（改进版）
    private func calculateImageDifference(_ image1: CGImage, _ image2: CGImage) -> Double {
        // 检查基本属性
        let size1 = CGSize(width: image1.width, height: image1.height)
        let size2 = CGSize(width: image2.width, height: image2.height)
        
        if size1 != size2 {
            return 1.0 // 尺寸不同，差异度最大
        }
        
        // 简化的像素级差异计算
        // 在实际应用中，可以使用更复杂的算法如SSIM、PSNR等
        guard let data1 = image1.dataProvider?.data,
              let data2 = image2.dataProvider?.data else {
            return 0.5 // 无法获取数据，返回中等差异度
        }
        
        let length1 = CFDataGetLength(data1)
        let length2 = CFDataGetLength(data2)
        
        if length1 != length2 {
            return 0.8 // 数据长度不同，差异度较高
        }
        
        let bytes1 = CFDataGetBytePtr(data1)
        let bytes2 = CFDataGetBytePtr(data2)
        
        var totalDifference: Double = 0
        let sampleSize = min(length1, 10000) // 采样比较，提高性能
        let step = max(1, length1 / sampleSize)
        
        for i in stride(from: 0, to: length1, by: step) {
            let diff = abs(Int(bytes1[i]) - Int(bytes2[i]))
            totalDifference += Double(diff)
        }
        
        let averageDifference = totalDifference / Double(sampleSize)
        let normalizedDifference = min(averageDifference / 255.0, 1.0) // 归一化到0-1范围
        
        return normalizedDifference
    }
    
    /// 提取最佳关键帧
    func extractOptimalKeyFrame(from asset: AVAsset, in timeRange: CMTimeRange) async throws -> UIImage {
        log("提取最佳关键帧...")
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        // 在指定时间范围内提取多个候选帧
        let candidateCount = 5
        let timeStep = timeRange.duration.seconds / Double(candidateCount - 1)
        var candidates: [(image: UIImage, score: Double, time: Double)] = []
        
        for i in 0..<candidateCount {
            let time = timeRange.start.seconds + Double(i) * timeStep
            let cgImage = try await imageGenerator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
            let image = UIImage(cgImage: cgImage)
            
            // 评估帧质量
            let qualityScore = evaluateFrameQuality(image, at: time, in: timeRange)
            candidates.append((image: image, score: qualityScore, time: time))
            
            log("候选帧 \(i + 1): 时间\(String(format: "%.2f", time))s, 质量评分\(String(format: "%.3f", qualityScore))")
        }
        
        // 选择评分最高的帧
        guard let bestCandidate = candidates.max(by: { $0.score < $1.score }) else {
            throw PreprocessingError.imageProcessingFailed
        }
        
        log("✅ 选择最佳关键帧: 时间\(String(format: "%.2f", bestCandidate.time))s, 评分\(String(format: "%.3f", bestCandidate.score))")
        return bestCandidate.image
    }
    
    /// 评估帧质量
    private func evaluateFrameQuality(_ image: UIImage, at time: Double, in timeRange: CMTimeRange) -> Double {
        var score = 1.0
        
        // 1. 偏好时间范围内的中间位置
        let timeScore = 1.0 - abs(time - (timeRange.start.seconds + timeRange.duration.seconds / 2)) / (timeRange.duration.seconds / 2)
        score += timeScore * 0.3
        
        // 2. 检查图像清晰度（通过简单的边缘检测）
        let sharpnessScore = estimateImageSharpness(image)
        score += sharpnessScore * 0.4
        
        // 3. 检查亮度（避免过暗或过亮的图像）
        let brightnessScore = evaluateBrightness(image)
        score += brightnessScore * 0.3
        
        return score
    }
    
    /// 估计图像清晰度
    private func estimateImageSharpness(_ image: UIImage) -> Double {
        // 简化的清晰度评估
        // 在实际应用中，可以使用拉普拉斯算子或梯度计算
        
        guard let cgImage = image.cgImage else { return 0.5 }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // 简单的边缘检测（计算相邻像素的差异）
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data else {
            return 0.5
        }
        
        let bytes = CFDataGetBytePtr(data)
        let length = CFDataGetLength(data)
        
        var edgeSum = 0
        let sampleStride = max(1, length / 1000) // 采样以提高性能
        
        for i in stride(from: 4, to: length - 4, by: sampleStride * 4) { // 假设RGBA格式
            let pixelDiff = abs(Int(bytes[i]) - Int(bytes[i - 4]))
            edgeSum += pixelDiff
        }
        
        let averageEdge = Double(edgeSum) / Double(length / sampleStride)
        let normalizedSharpness = min(averageEdge / 50.0, 1.0) // 归一化
        
        return normalizedSharpness
    }
    
    /// 评估图像亮度
    private func evaluateBrightness(_ image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0.5 }
        
        let width = cgImage.width
        let height = cgImage.height
        let totalPixels = width * height
        
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data else {
            return 0.5
        }
        
        let bytes = CFDataGetBytePtr(data)
        let length = CFDataGetLength(data)
        
        var totalBrightness = 0
        let sampleStride = max(1, length / 1000) // 采样以提高性能
        
        for i in stride(from: 0, to: length, by: sampleStride) {
            totalBrightness += Int(bytes[i])
        }
        
        let averageBrightness = Double(totalBrightness) / Double(length / sampleStride)
        let normalizedBrightness = averageBrightness / 255.0
        
        // 偏好中等亮度（0.3-0.7范围）
        let optimalBrightness = 0.5
        let brightnessScore = 1.0 - abs(normalizedBrightness - optimalBrightness) * 2.0
        
        return max(0.0, brightnessScore)
    }
    
    // 移除旧的 selectOptimalPreset 方法，现在使用 ConversionQuality 的设置
    
    /// 验证输出文件
    private func validateOutputFile(_ url: URL) async throws {
        log("验证输出文件...")
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PreprocessingError.exportFailed
        }
        
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? Int64 else {
            throw PreprocessingError.invalidFileAttributes
        }
        
        let sizeInMB = Double(fileSize) / 1024.0 / 1024.0
        log("输出文件大小: \(String(format: "%.2f", sizeInMB)) MB")
        
        if sizeInMB < 0.1 {
            throw PreprocessingError.fileTooSmall
        }
        
        // 验证视频文件完整性
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        
        if duration.seconds < 0.1 {
            throw PreprocessingError.videoTooShort
        }
        
        log("✅ 输出文件验证通过")
    }
    
    /// 创建元数据项
    private func createMetadataItem(key: String, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.key = key as NSString
        item.keySpace = AVMetadataKeySpace.quickTimeMetadata
        item.value = value as NSString
        return item
    }
    
    /// 获取推荐的Live Photo设置
    static func getRecommendedSettings() -> [String: Any] {
        return [
            "duration": "1-3 seconds",
            "resolution": "1080p or lower",
            "frameRate": "24-30 fps",
            "format": "H.264 video with AAC audio",
            "fileSize": "< 100MB"
        ]
    }
    
    /// 快速检查视频是否适合Live Photo转换
    func quickCheckVideoCompatibility(_ url: URL) async -> (isCompatible: Bool, issues: [String]) {
        var issues: [String] = []
        
        do {
            // 基本文件检查
            guard FileManager.default.fileExists(atPath: url.path) else {
                issues.append("文件不存在")
                return (false, issues)
            }
            
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                let sizeInMB = Double(fileSize) / 1024.0 / 1024.0
                if sizeInMB < 0.1 {
                    issues.append("文件太小")
                } else if sizeInMB > 500 {
                    issues.append("文件过大，处理时间可能较长")
                }
            }
            
            // 视频属性检查
            let asset = AVAsset(url: url)
            let duration = try await asset.load(.duration)
            let durationInSeconds = duration.seconds
            
            if durationInSeconds < 1.0 {
                issues.append("视频时长太短")
            } else if durationInSeconds > 10.0 {
                issues.append("视频时长过长，将截取前10秒")
            }
            
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            if videoTracks.isEmpty {
                issues.append("没有视频轨道")
            } else if let videoTrack = videoTracks.first {
                let naturalSize = try await videoTrack.load(.naturalSize)
                let maxDimension = max(naturalSize.width, naturalSize.height)
                
                if maxDimension > 1920 {
                    issues.append("分辨率过高，将自动降低")
                }
                
                let frameRate = videoTrack.nominalFrameRate
                if frameRate > 0 && (frameRate < 24 || frameRate > 60) {
                    issues.append("帧率不在推荐范围(24-60fps)")
                }
            }
            
            return (issues.isEmpty, issues)
            
        } catch {
            issues.append("无法分析视频: \(error.localizedDescription)")
            return (false, issues)
        }
    }
    
    /// 获取视频预览信息
    func getVideoPreviewInfo(_ url: URL) async -> VideoPreviewInfo? {
        do {
            let asset = AVAsset(url: url)
            let duration = try await asset.load(.duration)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            
            guard let videoTrack = videoTracks.first else {
                return nil
            }
            
            let naturalSize = try await videoTrack.load(.naturalSize)
            let frameRate = videoTrack.nominalFrameRate
            let hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
            
            // 提取预览图
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            let cgImage = try await imageGenerator.image(at: CMTime(seconds: duration.seconds / 2, preferredTimescale: 600)).image
            let previewImage = UIImage(cgImage: cgImage)
            
            return VideoPreviewInfo(
                duration: duration.seconds,
                resolution: naturalSize,
                frameRate: frameRate,
                hasAudio: hasAudio,
                previewImage: previewImage
            )
            
        } catch {
            log("获取视频预览信息失败: \(error)")
            return nil
        }
    }
}



/// 视频信息结构体
struct VideoInfo {
    let duration: Double
    let naturalSize: CGSize
    let frameRate: Float
    let hasAudio: Bool
    let formatDescriptions: [CMFormatDescription]
    
    var description: String {
        return """
        视频信息:
        - 时长: \(String(format: "%.2f", duration)) 秒
        - 尺寸: \(naturalSize.width) x \(naturalSize.height)
        - 帧率: \(frameRate) fps
        - 音频: \(hasAudio ? "有" : "无")
        - 格式描述: \(formatDescriptions.count) 个
        """
    }
}

/// 视频预览信息结构体
struct VideoPreviewInfo {
    let duration: Double
    let resolution: CGSize
    let frameRate: Float
    let hasAudio: Bool
    let previewImage: UIImage
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var formattedResolution: String {
        return "\(Int(resolution.width))×\(Int(resolution.height))"
    }
    
    var description: String {
        return """
        时长: \(formattedDuration)
        分辨率: \(formattedResolution)
        帧率: \(String(format: "%.1f", frameRate)) fps
        音频: \(hasAudio ? "有" : "无")
        """
    }
}

/// 预处理错误类型
enum PreprocessingError: LocalizedError {
    case fileNotFound
    case invalidFileAttributes
    case fileTooSmall
    case videoTooShort
    case noVideoTrack
    case exportSessionCreationFailed
    case exportFailed
    case imageProcessingFailed
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "视频文件不存在"
        case .invalidFileAttributes:
            return "无法读取文件属性"
        case .fileTooSmall:
            return "视频文件太小（<0.1MB）"
        case .videoTooShort:
            return "视频时长太短（<1秒）"
        case .noVideoTrack:
            return "视频文件没有视频轨道"
        case .exportSessionCreationFailed:
            return "无法创建视频导出会话"
        case .exportFailed:
            return "视频导出失败"
        case .imageProcessingFailed:
            return "图像处理失败"
        }
    }
}