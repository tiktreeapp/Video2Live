import Foundation
import AVFoundation
import Photos
import UIKit
import ImageIO
import UniformTypeIdentifiers

// 基于同行经验的Live Photo处理工具类
class LivePhotoUtil {
    
    // 日志记录
    private static func log(_ message: String) {
        // 统一收集并打印
        LogCollector.shared.append(message, category: "LivePhotoUtil")
    }
    
    // 主要转换函数 - 基于同行方案
    static func convertVideoToLivePhoto(
        videoURL: URL,
        progressHandler: @escaping (Double) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        Task {
            do {
                log("开始视频转Live Photo流程")
                
                // 1. 权限检查
                log("检查相册权限...")
                let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                guard status == .authorized else {
                    throw LivePhotoError.permissionDenied
                }
                log("✅ 相册权限已获取")
                
                // 2. 视频预处理
                log("创建AVAsset...")
                let asset = AVAsset(url: videoURL)
                let duration = try await asset.load(.duration)
                log("视频时长: \(duration.seconds)秒")
                
                // 3. 提取第一帧作为静态图像
                log("提取静态图像...")
                let keyFrame = try await extractKeyFrame(from: asset)
                
                // 4. 为图片添加水印和元数据
                log("处理静态图像...")
                let processedImage = try await processStaticImage(keyFrame)
                
                // 5. 准备临时文件（统一 contentID，确保图片与视频配对）
                let tempDir = FileManager.default.temporaryDirectory
                let contentID = UUID().uuidString
                let photoURL = tempDir.appendingPathComponent("IMG_\(contentID).JPG")
                let videoOutputURL = tempDir.appendingPathComponent("IMG_\(contentID).MOV")
                
                defer {
                    // 清理临时文件
                    try? FileManager.default.removeItem(at: photoURL)
                    try? FileManager.default.removeItem(at: videoOutputURL)
                }
                
                // 6. 保存处理后的图片（写入 MakerApple 元数据，使用统一 contentID）
                log("保存处理后的图片...")
                try saveProcessedImage(processedImage, to: photoURL, contentID: contentID)
                
                // 7. 导出视频（Passthrough + 保留原始方向 + 注入统一 contentID 元数据）
                log("导出视频（保持原始质量）...")
                try await exportVideoWithPassthrough(
                    from: asset,
                    to: videoOutputURL,
                    contentID: contentID,
                    progressHandler: progressHandler
                )
                
                // 8. 使用PHLivePhoto创建Live Photo对象（传入图片与视频）
                log("使用PHLivePhoto创建Live Photo对象...")
                let livePhoto = try await createPHLivePhoto(
                    image: processedImage,
                    photoURL: photoURL,
                    videoURL: videoOutputURL,
                    contentID: contentID
                )
                
                // 9. 保存到相册（使用统一 contentID）
                log("保存Live Photo到相册...")
                let assetID = try await saveLivePhotoToLibrary(
                    photoURL: photoURL,
                    videoURL: videoOutputURL,
                    contentID: contentID
                )
                
                log("✅ Live Photo创建成功: \(assetID)")
                completion(.success(assetID))
                
            } catch {
                log("❌ 转换失败: \(error)")
                
                // Fallback: 如果Live Photo创建失败，分别保存图片和视频
                log("尝试fallback方案：分别保存图片和视频...")
                do {
                    let fallbackID = try await fallbackSave(videoURL: videoURL)
                    completion(.success(fallbackID))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - 核心处理步骤
    
    // 提取关键帧 - 基于同行方案
    private static func extractKeyFrame(from asset: AVAsset) async throws -> UIImage {
        log("提取视频第一帧（避免黑场）...")
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true // 保持原始方向
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        // 避免黑场，向后取一点点时间
        let slightOffset = CMTime(seconds: 0.05, preferredTimescale: 600)
        let cgImage = try await imageGenerator.image(at: slightOffset).image
        let image = UIImage(cgImage: cgImage)
        
        log("✅ 关键帧提取成功，尺寸: \(image.size)")
        return image
    }
    
    // 处理静态图像 - 添加水印和元数据
    private static func processStaticImage(_ image: UIImage) async throws -> UIImage {
        log("处理静态图像...")
        
        // 添加水印"一键实况Live"
        let watermarkedImage = addWatermark(to: image, text: "一键实况Live")
        
        log("✅ 静态图像处理完成")
        return watermarkedImage
    }
    
    // 添加水印
    private static func addWatermark(to image: UIImage, text: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        
        return renderer.image { context in
            // 绘制原始图像
            image.draw(at: .zero)
            
            // 设置水印样式
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8),
                .strokeColor: UIColor.black.withAlphaComponent(0.5),
                .strokeWidth: -1
            ]
            
            // 计算水印位置（右下角）
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: image.size.width - textSize.width - 20,
                y: image.size.height - textSize.height - 20,
                width: textSize.width,
                height: textSize.height
            )
            
            // 绘制水印
            text.draw(in: textRect, withAttributes: attributes)
        }
    }
    
    // 保存处理后的图片 - 包含Apple专用元数据
    private static func saveProcessedImage(_ image: UIImage, to url: URL, contentID: String) throws {
        log("保存图片并添加Apple专用元数据（MakerApple 17/21）...")
        
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw LivePhotoError.imageProcessingFailed
        }
        
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw LivePhotoError.imageProcessingFailed
        }
        
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw LivePhotoError.imageProcessingFailed
        }
        
        // Apple 要求的 MakerApple 字典：
        // "17" = content identifier，"21" = still image time（字符串或数字均可，这里用 0）
        let metadata: [String: Any] = [
            kCGImagePropertyMakerAppleDictionary as String: [
                "17": contentID,
                "21": 0
            ]
        ]
        
        CGImageDestinationAddImageFromSource(destination, imageSource, 0, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw LivePhotoError.imageProcessingFailed
        }
        log("✅ 图片保存成功，包含 MakerApple 元数据 17/21")
    }
    
    // 导出视频 - 使用passthrough保持原始质量（同行关键方案）
    private static func exportVideoWithPassthrough(
        from asset: AVAsset,
        to outputURL: URL,
        contentID: String,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        log("开始视频导出（passthrough模式）...")
        
        // 读取原视频轨道并保留方向
        let composition = AVMutableComposition()
        if let srcVideoTrack = try? await asset.loadTracks(withMediaType: .video).first,
           let dstVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
            try? dstVideoTrack.insertTimeRange(timeRange, of: srcVideoTrack, at: .zero)
            if let t = try? await srcVideoTrack.load(.preferredTransform) {
                dstVideoTrack.preferredTransform = t
            }
        }
        if let srcAudioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let dstAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
            try? dstAudioTrack.insertTimeRange(timeRange, of: srcAudioTrack, at: .zero)
        }
        
        // 使用 Passthrough 保留原质量
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw LivePhotoError.exportFailed("无法创建导出会话")
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        
        // 添加与图片一致的 contentID
        let metadata = [
            createMetadataItem(key: "com.apple.quicktime.live-photo", value: "1"),
            createMetadataItem(key: "com.apple.quicktime.content.identifier", value: contentID),
            createMetadataItem(key: "com.apple.quicktime.still-image-time", value: "0")
        ]
        exportSession.metadata = metadata
        
        // 监控导出进度
        let progressTimer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                progressHandler(Double(exportSession.progress))
            }
        
        defer {
            progressTimer.cancel()
        }
        
        // 执行导出
        await exportSession.export()
        
        // 检查结果
        guard exportSession.status == .completed else {
            let error = exportSession.error ?? LivePhotoError.exportFailed("导出未完成")
            throw error
        }
        
        // 检查输出文件大小
        let outputSize = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int ?? 0
        log("✅ 视频导出成功，输出大小: \(Double(outputSize) / 1024.0 / 1024.0) MB")
    }
    
    // 保存到相册
    private static func saveLivePhotoToLibrary(
        photoURL: URL,
        videoURL: URL,
        contentID: String
    ) async throws -> String {
        log("保存Live Photo到相册...")
        
        var assetID: String?
        
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            
            // 添加图片资源
            let photoOptions = PHAssetResourceCreationOptions()
            photoOptions.uniformTypeIdentifier = UTType.jpeg.identifier
            request.addResource(with: .photo, fileURL: photoURL, options: photoOptions)
            
            // 添加配对视频资源
            let videoOptions = PHAssetResourceCreationOptions()
            videoOptions.uniformTypeIdentifier = UTType.quickTimeMovie.identifier
            request.addResource(with: .pairedVideo, fileURL: videoURL, options: videoOptions)
            
            // 获取asset ID
            assetID = request.placeholderForCreatedAsset?.localIdentifier
        }
        
        guard let finalAssetID = assetID else {
            throw LivePhotoError.saveFailed("无法获取Asset ID")
        }
        
        log("✅ Live Photo保存成功: \(finalAssetID)")
        return finalAssetID
    }
    
    // MARK: - iOS官方PHLivePhoto技术
    
    /// 使用PHLivePhoto创建Live Photo对象 - iOS官方技术
    private static func createPHLivePhoto(image: UIImage, photoURL: URL, videoURL: URL, contentID: String) async throws -> PHLivePhoto {
        log("使用PHLivePhoto创建Live Photo对象（传入图片与视频资源）...")
        
        return try await withCheckedThrowingContinuation { continuation in
            PHLivePhoto.request(
                withResourceFileURLs: [photoURL, videoURL],
                placeholderImage: image,
                targetSize: image.size,
                contentMode: .aspectFit
            ) { livePhoto, info in
                if let livePhoto = livePhoto {
                    self.log("✅ PHLivePhoto创建成功")
                    continuation.resume(returning: livePhoto)
                } else {
                    let error = info?[PHLivePhotoInfoErrorKey] as? Error ?? LivePhotoError.creationFailed
                    self.log("❌ PHLivePhoto创建失败: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Fallback机制
    
    // Fallback方案：分别保存图片和视频
    private static func fallbackSave(videoURL: URL) async throws -> String {
        log("执行fallback方案：分别保存图片和视频...")
        
        let asset = AVAsset(url: videoURL)
        let keyFrame = try await extractKeyFrame(from: asset)
        
        let tempDir = FileManager.default.temporaryDirectory
        let photoURL = tempDir.appendingPathComponent("fallback_\(UUID().uuidString).jpg")
        let videoOutputURL = tempDir.appendingPathComponent("fallback_\(UUID().uuidString).mov")
        
        defer {
            try? FileManager.default.removeItem(at: photoURL)
            try? FileManager.default.removeItem(at: videoOutputURL)
        }
        
        // 保存图片
        guard let imageData = keyFrame.jpegData(compressionQuality: 0.9) else {
            throw LivePhotoError.imageProcessingFailed
        }
        try imageData.write(to: photoURL)
        
        // 复制视频
        try FileManager.default.copyItem(at: videoURL, to: videoOutputURL)
        
        // 分别保存到相册
        var savedAssetID: String?
        
        try await PHPhotoLibrary.shared().performChanges {
            // 保存图片
            let photoRequest = PHAssetCreationRequest.forAsset()
            photoRequest.addResource(with: .photo, fileURL: photoURL, options: nil)
            
            // 保存视频
            let videoRequest = PHAssetCreationRequest.forAsset()
            videoRequest.addResource(with: .video, fileURL: videoOutputURL, options: nil)
            
            // 返回图片的asset ID
            savedAssetID = photoRequest.placeholderForCreatedAsset?.localIdentifier
        }
        
        guard let assetID = savedAssetID else {
            throw LivePhotoError.saveFailed("Fallback保存失败")
        }
        
        log("✅ Fallback保存成功: \(assetID)")
        return assetID
    }
    
    // MARK: - 辅助函数
    
    // 创建元数据项
    private static func createMetadataItem(key: String, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.key = key as NSString
        item.keySpace = AVMetadataKeySpace.quickTimeMetadata
        item.value = value as NSString
        return item
    }
}

// MARK: - 错误类型

enum LivePhotoError: LocalizedError {
    case permissionDenied
    case invalidVideoFormat
    case imageProcessingFailed
    case exportFailed(String)
    case saveFailed(String)
    case creationFailed
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "相册权限被拒绝，请在设置中开启权限"
        case .invalidVideoFormat:
            return "视频格式不支持，请选择标准格式的视频"
        case .imageProcessingFailed:
            return "图像处理失败"
        case .exportFailed(let reason):
            return "视频导出失败：\(reason)"
        case .saveFailed(let reason):
            return "保存失败：\(reason)"
        case .creationFailed:
            return "Live Photo创建失败"
        }
    }
}