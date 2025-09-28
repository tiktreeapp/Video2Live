import Foundation
import AVFoundation
import Photos
import UIKit
import PhotosUI

/// 基于iOS官方技术的Video转Live Photo转换器
public class VideoToLivePhotoConverter {
    
    // 单例模式
    static let shared = VideoToLivePhotoConverter()
    private init() {}
    
    // 日志记录
    private func log(_ message: String) {
        print("🔄 [VideoToLivePhotoConverter] \(message)")
    }
    
    /// 主要转换函数 - 使用iOS官方技术
    func convertVideoToLivePhoto(
        videoURL: URL,
        progressHandler: @escaping (Double) -> Void = { _ in },
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        Task {
            do {
                log("开始视频转Live Photo流程")
                
                // 1. 权限检查
                log("检查相册权限...")
                let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                guard status == .authorized else {
                    throw ConversionError.permissionDenied
                }
                log("✅ 相册权限已获取")
                
                // 2. 视频预处理
                log("创建AVAsset...")
                let asset = AVAsset(url: videoURL)
                let duration = try await asset.load(.duration)
                log("视频时长: \(duration.seconds)秒")
                
                // 3. 提取第一帧作为静态图像（使用视频开始位置）
                log("提取静态图像...")
                let keyFrameTime = CMTime(seconds: 0, preferredTimescale: 600) // 使用视频开始位置
                let keyFrame = try await extractKeyFrame(from: asset, at: keyFrameTime)
                
                // 4. 准备临时文件
                let tempDir = FileManager.default.temporaryDirectory
                let uuid = UUID().uuidString
                let photoURL = tempDir.appendingPathComponent("IMG_\(uuid).JPG")
                let videoOutputURL = tempDir.appendingPathComponent("IMG_\(uuid).MOV")
                
                defer {
                    // 清理临时文件
                    try? FileManager.default.removeItem(at: photoURL)
                    try? FileManager.default.removeItem(at: videoOutputURL)
                }
                
                // 5. 保存处理后的图片
                log("保存处理后的图片...")
                try saveProcessedImage(keyFrame, to: photoURL, contentID: uuid)
                
                // 6. 导出视频（使用passthrough保持原始质量）
                log("导出视频（保持原始质量）...")
                try await exportVideoWithPassthrough(
                    from: asset,
                    to: videoOutputURL,
                    contentID: uuid,
                    stillImageTime: 0, // 静态图像时间为0
                    progressHandler: progressHandler
                )
                
                // 7. 使用PHLivePhoto创建Live Photo
                log("创建Live Photo...")
                let livePhoto = try await createPHLivePhoto(
                    image: keyFrame,
                    videoURL: videoOutputURL,
                    contentID: uuid
                )
                
                // 8. 保存到相册
                log("保存Live Photo到相册...")
                let assetID = try await saveLivePhotoToLibrary(
                    photoURL: photoURL,
                    videoURL: videoOutputURL,
                    contentID: uuid
                )
                
                log("✅ Live Photo创建成功: \(assetID)")
                completion(.success(assetID))
                
            } catch {
                log("❌ 转换失败: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - 核心处理步骤
    
    /// 提取关键帧 - 使用指定时间点
    private func extractKeyFrame(from asset: AVAsset, at time: CMTime) async throws -> UIImage {
        log("提取视频关键帧，时间点: \(time.seconds)秒...")
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true // 保持原始方向
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        let cgImage = try await imageGenerator.image(at: time).image
        let image = UIImage(cgImage: cgImage)
        
        log("✅ 关键帧提取成功，尺寸: \(image.size)")
        return image
    }
    
    /// 保存处理后的图片 - 包含Apple专用元数据
    private func saveProcessedImage(_ image: UIImage, to url: URL, contentID: String) throws {
        log("保存图片并添加Apple专用元数据...")
        
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw ConversionError.imageProcessingFailed
        }
        
        // 创建图片源
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw ConversionError.imageProcessingFailed
        }
        
        // 创建目标图片
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ConversionError.imageProcessingFailed
        }
        
        // 准备Apple专用元数据
        let metadata: [String: Any] = [
            kCGImagePropertyMakerAppleDictionary as String: [
                "17": contentID, // Content Identifier
                "21": 0         // Still Image Time (视频开始位置)
            ]
        ]
        
        // 写入图片和元数据
        CGImageDestinationAddImageFromSource(destination, imageSource, 0, metadata as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.imageProcessingFailed
        }
        
        log("✅ 图片保存成功，包含Apple元数据")
    }
    
    /// 导出视频 - 使用passthrough保持原始质量
    private func exportVideoWithPassthrough(
        from asset: AVAsset,
        to outputURL: URL,
        contentID: String,
        stillImageTime: Double,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        log("开始视频导出（passthrough模式）...")
        
        // 创建导出会话 - 关键：使用passthrough保持原始质量
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ConversionError.exportFailed("无法创建导出会话")
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        
        // 添加Live Photo必需的元数据
        let metadata = [
            createMetadataItem(key: "com.apple.quicktime.live-photo", value: "1"),
            createMetadataItem(key: "com.apple.quicktime.content.identifier", value: contentID),
            createMetadataItem(key: "com.apple.quicktime.still-image-time", value: String(stillImageTime))
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
            let error = exportSession.error ?? ConversionError.exportFailed("导出未完成")
            throw error
        }
        
        log("✅ 视频导出成功")
    }
    
    /// 使用PHLivePhoto创建Live Photo对象
    private func createPHLivePhoto(image: UIImage, videoURL: URL, contentID: String) async throws -> PHLivePhoto {
        log("使用PHLivePhoto创建Live Photo对象...")
        
        return try await withCheckedThrowingContinuation { continuation in
            PHLivePhoto.request(
                withResourceFileURLs: [videoURL],
                placeholderImage: image,
                targetSize: image.size,
                contentMode: .aspectFit
            ) { livePhoto, info in
                if let livePhoto = livePhoto {
                    self.log("✅ PHLivePhoto创建成功")
                    continuation.resume(returning: livePhoto)
                } else {
                    let error = info?[PHLivePhotoInfoErrorKey] as? Error ?? ConversionError.creationFailed
                    self.log("❌ PHLivePhoto创建失败: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// 保存到相册
    private func saveLivePhotoToLibrary(
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
            throw ConversionError.saveFailed("无法获取Asset ID")
        }
        
        log("✅ Live Photo保存成功: \(finalAssetID)")
        return finalAssetID
    }
    
    // MARK: - 辅助函数
    
    /// 创建元数据项
    private func createMetadataItem(key: String, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.key = key as NSString
        item.keySpace = AVMetadataKeySpace.quickTimeMetadata
        item.value = value as NSString
        return item
    }
}

// MARK: - 错误类型

enum ConversionError: LocalizedError {
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