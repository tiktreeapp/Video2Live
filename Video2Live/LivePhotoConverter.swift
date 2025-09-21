import Foundation
import AVFoundation
import Photos
import UIKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

// 轻量级日志收集器：收集运行时关键日志，生成诊断报告
final class LogCollector {
    static let shared = LogCollector()
    private let lock = NSLock()
    private var items: [String] = []
    private let maxItems = 500

    private init() {}

    func append(_ message: String, category: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] [\(category)] \(message)"
        lock.lock()
        if items.count >= maxItems { items.removeFirst(items.count - maxItems + 1) }
        items.append(line)
        lock.unlock()
        // 同步打印到控制台便于实时观察
        print(line)
    }

    func report(extra: [String: String] = [:]) -> String {
        lock.lock()
        let logs = items.joined(separator: "\n")
        lock.unlock()
        var header = [
            "App": "Video2Live",
            "iOS": UIDevice.current.systemVersion,
            "Device": UIDevice.current.model,
        ]
        extra.forEach { header[$0.key] = $0.value }
        let meta = header.map { "\($0): \($1)" }.sorted().joined(separator: "\n")
        return """
        ===== Video2Live Diagnostics =====
        \(meta)

        ----- Recent Logs -----
        \(logs)
        """
    }

    func clear() {
        lock.lock(); items.removeAll(); lock.unlock()
    }
}

// 媒体处理错误类型
enum MediaProcessingError: Error {
    case videoLoadFailed
    case exportFailed
    case saveFailed
    case invalidTimeRange
    case resourcesUnavailable
}

// 转换进度回调
typealias ProgressHandler = (Double) -> Void
// 完成回调 - 返回保存的asset ID
typealias CompletionHandler = (Result<String, Error>) -> Void

class MediaAssetProcessor {
    // 单例模式
    static let shared = MediaAssetProcessor()
    private init() {}
    
    // 添加日志工具
    private func log(_ message: String) {
        LogCollector.shared.append(message, category: "LivePhotoConverter")
    }
    
    // 支持带级别的日志重载，兼容现有调用
    private func log(_ message: String, level: String) {
        LogCollector.shared.append("[\(level)] \(message)", category: "LivePhotoConverter")
    }
    
    // 添加到类的顶部
    private enum LivePhotoError: Error {
        case creationFailed
        case resourcesUnavailable
    }
    
    // 在类顶部添加
    #if DEBUG
    private let SAVE_DEBUG_FILES = true
    #else
    private let SAVE_DEBUG_FILES = false
    #endif
    
    // 转换视频为Live Photo
    func processMediaAssets(
        videos: [Any],
        progressHandler: @escaping ProgressHandler,
        completion: @escaping CompletionHandler
    ) {
        Task {
            do {
                log("开始转换流程")
                log("视频数量: \(videos.count)")
                log("处理视频: 完整视频")
                
                // 检查权限
                let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                log("照片库权限状态: \(status.rawValue)")
                
                guard status == .authorized else {
                    log("❌ 照片库权限未授权")
                    throw MediaProcessingError.saveFailed
                }
                
                var finalAssetID: String?
                
                for (index, video) in videos.enumerated() {
                    guard let pickerItem = video as? PhotosPickerItem else { continue }
                    
                    // 加载视频
                    guard let videoData = try? await pickerItem.loadTransferable(type: Data.self) else {
                        throw MediaProcessingError.videoLoadFailed
                    }
                    
                    // 创建临时文件
                    let tempDir = FileManager.default.temporaryDirectory
                    let sourceURL = tempDir.appendingPathComponent("source_\(UUID().uuidString).mov")
                    let outputURL = tempDir.appendingPathComponent("clip_\(UUID().uuidString).mov")
                    
                    defer {
                        try? FileManager.default.removeItem(at: sourceURL)
                        try? FileManager.default.removeItem(at: outputURL)
                    }
                    
                    // 保存视频数据
                    try videoData.write(to: sourceURL)
                    
                    // 获取视频时长和时间段
                    let asset = AVAsset(url: sourceURL)
                    let duration = try await asset.load(.duration)
                    // 使用整个视频，不再有时间段选择
                    let timeRange = CMTimeRange(start: .zero, duration: duration)
                    
                    log("视频时长: \(duration.seconds)秒")
                    log("处理整个视频: \(timeRange.start.seconds)-\(timeRange.end.seconds)")
                    
                    // 截取视频片段
                    let useFFmpeg = false // 禁用FFmpeg处理
                    
                    if useFFmpeg {
                        // 使用FFmpeg处理
                        try await tryEnhancedLivePhoto(
                            asset: asset,
                            timeRange: timeRange,
                            outputURL: outputURL
                        )
                    } else {
                        // 使用原始AVFoundation处理
                        let contentID = try await exportVideoClip(
                            from: asset,
                            timeRange: timeRange,
                            to: outputURL
                        )
                        
                        // 提取关键帧
                        let keyFrame = try await extractKeyFrame(
                            from: asset,
                            at: timeRange.start
                        )
                        
                        // 保存为Live Photo - 传递内容标识符，获取asset ID
                        finalAssetID = try await saveToLibrary(
                            image: keyFrame,
                            videoURL: outputURL,
                            livePhotoID: contentID
                        )
                    }
                    
                    // 更新进度
                    let progress = Double(index + 1) / Double(videos.count)
                    await MainActor.run {
                        progressHandler(progress)
                    }
                }
                
                let assetIDToReturn = finalAssetID ?? ""
                await MainActor.run {
                    completion(.success(assetIDToReturn))
                }
            } catch {
                log("❌ 转换失败: \(error)")
                log("错误详情: \(String(describing: error))")
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // 视频片段导出
    private func exportVideoClip(
        from asset: AVAsset,
        timeRange: CMTimeRange,
        to outputURL: URL
    ) async throws -> String {
        // 创建合成
        let composition = AVMutableComposition()
        
        // 添加视频轨道
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw MediaProcessingError.exportFailed
        }
        
        // 添加视频片段
        let assetTracks = try await asset.loadTracks(withMediaType: .video)
        guard let assetVideoTrack = assetTracks.first else {
            throw MediaProcessingError.videoLoadFailed
        }
        
        // 保存原始变换，确保视频方向正确
        let preferredTransform = try await assetVideoTrack.load(.preferredTransform)
        videoTrack.preferredTransform = preferredTransform
        
        try videoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: .zero)
        
        // 添加音频轨道
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }
        
        // 创建导出会话 - 使用特定的预设
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw MediaProcessingError.exportFailed
        }
        
        // 配置导出选项
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov
        exporter.shouldOptimizeForNetworkUse = true
        
        // 添加Live Photo所需的元数据
        let uuid = UUID().uuidString
        let metadata = [
            createMetadataItem(key: "com.apple.quicktime.live-photo", value: "1"),
            createMetadataItem(key: "com.apple.quicktime.content.identifier", value: uuid),
            createMetadataItem(key: "com.apple.quicktime.still-image-time", value: "0")
        ]
        exporter.metadata = metadata
        
        // 执行导出
        await exporter.export()
        
        // 检查结果
        guard exporter.status == .completed else {
            log("导出失败: \(String(describing: exporter.error))")
            throw MediaProcessingError.exportFailed
        }
        
        log("✅ 视频片段导出成功 (优化H.264格式)")
        return uuid
    }
    
    // 提取关键帧
    private func extractKeyFrame(
        from asset: AVAsset,
        at time: CMTime
    ) async throws -> UIImage {
        // 使用AVFoundation提取关键帧，避免FFmpegKit依赖
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        let cgImage = try await imageGenerator.image(at: time).image
        return UIImage(cgImage: cgImage)
    }
    
    // 修改保存方法以尝试创建标准Live Photo格式，返回asset ID
    private func saveToLibrary(
        image: UIImage,
        videoURL: URL,
        livePhotoID: String? = nil
    ) async throws -> String {
        // 检查照片库权限
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status != .authorized {
            log("⚠️ 照片库权限未授权: \(status)")
            // 再次请求权限
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if newStatus != .authorized {
                log("❌ 用户拒绝了照片库权限")
                throw MediaProcessingError.saveFailed
            }
        }
        
        // 创建临时文件 - 使用完全符合Apple标准的命名
        let tempDir = FileManager.default.temporaryDirectory
        let uuid = livePhotoID ?? UUID().uuidString
        
        // 使用标准命名格式 - 必须使用相同的前缀
        let photoFileName = "IMG_\(uuid).JPG"
        let videoFileName = "IMG_\(uuid).MOV"
        
        let photoURL = tempDir.appendingPathComponent(photoFileName)
        let newVideoURL = tempDir.appendingPathComponent(videoFileName)
        
        // 检查视频文件是否存在且可读
        if !FileManager.default.fileExists(atPath: videoURL.path) {
            log("❌ 源视频文件不存在: \(videoURL.path)")
            throw MediaProcessingError.resourcesUnavailable
        }
        
        // 保存图片 - 添加必要的元数据
        if let cgImage = image.cgImage {
            let uiImage = UIImage(cgImage: cgImage)
            guard let imageData = uiImage.jpegData(compressionQuality: 1.0) else {
                throw MediaProcessingError.exportFailed
            }
            
            let source = CGImageSourceCreateWithData(imageData as CFData, nil)!
            
            // 添加Live Photo元数据
            let metadata = NSMutableDictionary()
            metadata["com.apple.quicktime.live-photo"] = "1"
            metadata["com.apple.quicktime.content.identifier"] = uuid
            metadata["com.apple.quicktime.still-image-time"] = "0"
            
            let destination = CGImageDestinationCreateWithURL(photoURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
            CGImageDestinationAddImageFromSource(destination, source, 0, metadata)
            if !CGImageDestinationFinalize(destination) {
                log("⚠️ 添加图片元数据失败")
            }
        } else {
            guard let imageData = image.jpegData(compressionQuality: 1.0) else {
                throw MediaProcessingError.exportFailed
            }
            try imageData.write(to: photoURL)
        }
        
        // 处理视频 - 确保格式正确
        try FileManager.default.copyItem(at: videoURL, to: newVideoURL)
        
        // 添加延迟确保文件写入完成
        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5秒
        
        // 检查文件
        log("📊 图片路径: \(photoURL.path)")
        log("📊 视频路径: \(newVideoURL.path)")
        
        let photoSize = (try? FileManager.default.attributesOfItem(atPath: photoURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let videoSize = (try? FileManager.default.attributesOfItem(atPath: newVideoURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        
        log("📊 图片大小: \(photoSize) bytes, 视频大小: \(videoSize) bytes")
        
        // 使用PHAssetCreationRequest创建Live Photo
        do {
            var assetID: String?
            
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                
                // 添加资源 - 使用正确的选项
                let photoOptions = PHAssetResourceCreationOptions()
                photoOptions.uniformTypeIdentifier = UTType.jpeg.identifier
                
                let videoOptions = PHAssetResourceCreationOptions()
                videoOptions.uniformTypeIdentifier = UTType.quickTimeMovie.identifier
                
                // 添加资源 - 顺序很重要：先照片后视频
                request.addResource(with: .photo, fileURL: photoURL, options: photoOptions)
                request.addResource(with: .pairedVideo, fileURL: newVideoURL, options: videoOptions)
                
                // 保存ID以便后续检查
                assetID = request.placeholderForCreatedAsset?.localIdentifier
            }
            
            log("✅ 资源已成功保存到相册，ID: \(assetID ?? "未知")")
            
            // 验证创建的资产是否为Live Photo
            if let id = assetID {
                let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
                if let asset = result.firstObject {
                    let isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
                    log("🔍 创建的资产是Live Photo: \(isLivePhoto)")
                    
                    if !isLivePhoto {
                        log("⚠️ 资产已创建但不是Live Photo")
                    }
                }
            }
            
            // 返回asset ID
            return assetID ?? uuid
        } catch {
            log("❌ 保存到相册失败: \(error)")
            
            // 尝试备用方法 - 使用更可靠的方法
            log("尝试备用方法 - 使用更可靠的保存方法")
            do {
                let backupAssetID = try await saveWithBackupMethod(photoURL: photoURL, videoURL: newVideoURL)
                return backupAssetID
                log("✅ 使用备用方法保存成功")
            } catch {
                log("❌ 备用方法也失败: \(error)")
                
                // 尝试极简方法
                log("尝试极简方法 - 最基本的保存方式")
                do {
                    let ultraSimpleAssetID = try await saveWithUltraSimpleMethod(videoURL: videoURL)
                    return ultraSimpleAssetID
                    log("✅ 极简方法保存成功")
                } catch {
                    log("❌ 极简方法也失败: \(error)")
                    throw error
                }
            }
        }
    }
    
    // 添加一个更可靠的备用方法，返回asset ID
    private func saveWithBackupMethod(photoURL: URL, videoURL: URL) async throws -> String {
        // 确保文件名正确
        let tempDir = FileManager.default.temporaryDirectory
        let uuid = UUID().uuidString
        
        // 使用标准命名格式
        let finalPhotoURL = tempDir.appendingPathComponent("IMG_\(uuid).JPG")
        let finalVideoURL = tempDir.appendingPathComponent("IMG_\(uuid).MOV")
        
        // 复制文件到新位置
        try FileManager.default.copyItem(at: photoURL, to: finalPhotoURL)
        try FileManager.default.copyItem(at: videoURL, to: finalVideoURL)
        
        // 添加必要的元数据
        // 为图片添加元数据
        if let image = UIImage(contentsOfFile: finalPhotoURL.path),
           let imageData = image.jpegData(compressionQuality: 1.0) {
            let source = CGImageSourceCreateWithData(imageData as CFData, nil)!
            let metadata = NSMutableDictionary()
            metadata["com.apple.quicktime.live-photo"] = "1"
            metadata["com.apple.quicktime.content.identifier"] = uuid
            
            let destination = CGImageDestinationCreateWithURL(finalPhotoURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
            CGImageDestinationAddImageFromSource(destination, source, 0, metadata)
            CGImageDestinationFinalize(destination)
        }
        
        // 为视频添加元数据
        let asset = AVAsset(url: videoURL)
        let composition = AVMutableComposition()
        
        // 添加视频轨道
        if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
           let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid) {
            
            try? compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: asset.duration),
                of: videoTrack,
                at: .zero
            )
        }
        
        // 添加音频轨道
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid) {
            
            try? compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: asset.duration),
                of: audioTrack,
                at: .zero
            )
        }
        
        // 导出带元数据的视频
        if let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) {
            exporter.outputURL = finalVideoURL
            exporter.outputFileType = .mov
            
            // 添加元数据
            let metadata = [
                createMetadataItem(key: "com.apple.quicktime.live-photo", value: "1"),
                createMetadataItem(key: "com.apple.quicktime.content.identifier", value: uuid),
                createMetadataItem(key: "com.apple.quicktime.still-image-time", value: "0")
            ]
            exporter.metadata = metadata
            
            await exporter.export()
        }
        
        // 保存到相册
        var assetID: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: finalPhotoURL, options: nil)
            request.addResource(with: .pairedVideo, fileURL: finalVideoURL, options: nil)
            assetID = request.placeholderForCreatedAsset?.localIdentifier
        }
        
        // 清理临时文件
        try? FileManager.default.removeItem(at: finalPhotoURL)
        try? FileManager.default.removeItem(at: finalVideoURL)
        
        // 返回asset ID
        return assetID ?? uuid
    }
    
    // 获取时间范围
    
    
    // 在 MediaAssetProcessor 类中添加权限检查方法
    private func checkPhotoLibraryPermission() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized
    }
    
    // 添加这个辅助方法到类中
    private func createMetadataItem(key: String, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.key = key as NSString
        item.keySpace = AVMetadataKeySpace.quickTimeMetadata
        item.value = value as NSString
        return item
    }
    
    // 增强checkFile方法
    private func checkFile(_ url: URL) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            log("文件大小: \(attributes[.size] ?? 0) bytes")
            log("文件类型: \(url.pathExtension)")
        } catch {
            log("❌ 检查文件失败: \(error)")
        }
    }
    
    // 修改 tryEnhancedLivePhoto 方法
    private func tryEnhancedLivePhoto(
        asset: AVAsset,
        timeRange: CMTimeRange,
        outputURL: URL
    ) async throws {
        // 创建唯一的临时文件
        let tempDir = FileManager.default.temporaryDirectory
        let uuid = UUID().uuidString
        let sourceURL = tempDir.appendingPathComponent("source_\(uuid).mov")
        let photoURL = tempDir.appendingPathComponent("photo_\(uuid).jpg")
        let livePhotoID = UUID().uuidString
        
        // 首先导出原始段
        let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)!
        exportSession.outputURL = sourceURL
        exportSession.outputFileType = .mov
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            throw MediaProcessingError.exportFailed
        }
        
        // 使用 AVFoundation 处理视频
        try await LivePhotoEnhanced.shared.processVideoWithAVFoundation(
            inputURL: sourceURL,
            outputURL: outputURL,
            startTime: timeRange.start.seconds,
            duration: timeRange.duration.seconds
        )
        
        // 处理图片 - 确保 livePhotoID 参数正确传递
        try await LivePhotoEnhanced.shared.extractAndProcessImage(
            from: asset,
            at: timeRange.start,
            outputURL: photoURL,
            livePhotoID: livePhotoID
        )
        
        // 保存为 Live Photo，获取asset ID
        let newAssetID = try await saveToLibrary(
            image: UIImage(contentsOfFile: photoURL.path)!,
            videoURL: outputURL,
            livePhotoID: livePhotoID
        )
        
        // 清理临时文件
        try? FileManager.default.removeItem(at: sourceURL)
    }
    
    // 修改 createLivePhotoDirectly 方法
    func createLivePhotoDirectly(
        from videoURL: URL,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        Task {
            do {
                log("=== createLivePhotoDirectly 开始 ===")
                log("视频URL: \(videoURL.path)")
                
                // 预检视频文件
                guard FileManager.default.fileExists(atPath: videoURL.path) else {
                    log("❌ 视频文件不存在")
                    throw NSError(domain: "FileNotFound", code: -1, userInfo: [NSLocalizedDescriptionKey: "视频文件不存在"])
                }
                
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
                    if let fileSize = attributes[.size] as? Int64 {
                        let sizeInMB = Double(fileSize) / 1024.0 / 1024.0
                        log("视频文件大小: \(String(format: "%.2f", sizeInMB)) MB")
                        
                        if sizeInMB < 0.1 {
                            log("⚠️ 文件太小，可能不是有效视频", level: "WARNING")
                        }
                    }
                } catch {
                    log("⚠️ 无法获取文件大小: \(error)", level: "WARNING")
                }
                
                // 加载视频
                log("创建AVAsset...")
                let asset = AVAsset(url: videoURL)
                
                // 检查视频轨道
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                log("视频轨道数量: \(videoTracks.count)")
                
                if videoTracks.isEmpty {
                    log("❌ 没有找到视频轨道", level: "ERROR")
                    throw NSError(domain: "InvalidVideo", code: -1, userInfo: [NSLocalizedDescriptionKey: "视频文件没有视频轨道"])
                }
                
                let duration = try await asset.load(.duration)
                log("视频时长: \(duration.seconds) 秒")
                
                if duration.seconds < 1.0 {
                    log("⚠️ 视频太短（<1秒）", level: "WARNING")
                }
                
                // 使用整个视频，不再有时间段选择
                let timeRange = CMTimeRange(start: .zero, duration: duration)
                
                // 创建临时文件
                let tempDir = FileManager.default.temporaryDirectory
                let uuid = UUID().uuidString
                let photoURL = tempDir.appendingPathComponent("IMG_\(uuid).JPG")
                let clipURL = tempDir.appendingPathComponent("IMG_\(uuid).MOV")
                
                // 提取关键帧并保存
                log("提取关键帧，时间点: \(timeRange.start.seconds) 秒...")
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                
                do {
                    let cgImage = try await imageGenerator.image(at: timeRange.start).image
                    let image = UIImage(cgImage: cgImage)
                    log("✅ 关键帧提取成功，尺寸: \(image.size)")
                    
                    // 保存图片并添加 MakerApple 元数据（确保与视频使用相同 content identifier）
                    log("保存图片并添加 MakerApple 元数据...")
                    guard let imageData = image.jpegData(compressionQuality: 0.9) else {
                        log("❌ 无法创建图片数据", level: "ERROR")
                        throw MediaProcessingError.exportFailed
                    }
                    
                    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
                        log("❌ 无法创建图片源", level: "ERROR")
                        throw MediaProcessingError.exportFailed
                    }
                    
                    guard let destination = CGImageDestinationCreateWithURL(photoURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                        log("❌ 无法创建图片目标", level: "ERROR")
                        throw MediaProcessingError.exportFailed
                    }
                    
                    // Apple 要求：MakerApple 字典 "17"=contentID，"21"=still image time
                    let makerApple: [String: Any] = [
                        "17": uuid,
                        "21": 0
                    ]
                    let metadata: [String: Any] = [
                        kCGImagePropertyMakerAppleDictionary as String: makerApple
                    ]
                    
                    CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)
                    
                    if !CGImageDestinationFinalize(destination) {
                        log("❌ 图片保存失败", level: "ERROR")
                        throw MediaProcessingError.exportFailed
                    }
                    
                    log("✅ 图片保存成功")
                } catch {
                    log("❌ 关键帧提取失败: \(error)", level: "ERROR")
                    throw error
                }
                
                // 保存图片并添加元数据 - 图片已经在上面保存过了，跳过这一步
                
                // 导出视频片段
                let composition = AVMutableComposition()
                
                // 添加视频轨道并保留原始方向
                if let videoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ), let assetVideoTrack = try? await asset.loadTracks(withMediaType: .video).first {
                    try videoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: .zero)
                    if let t = try? await assetVideoTrack.load(.preferredTransform) {
                        videoTrack.preferredTransform = t
                    }
                }
                
                // 添加音频轨道
                if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
                   let compositionAudioTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    ) {
                    try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
                }
                
                // 导出视频
                log("创建视频导出会话...")
                guard let exporter = AVAssetExportSession(
                    asset: composition,
                    presetName: AVAssetExportPresetPassthrough
                ) else {
                    log("❌ 无法创建导出会话", level: "ERROR")
                    throw MediaProcessingError.exportFailed
                }
                
                exporter.outputURL = clipURL
                exporter.outputFileType = .mov
                
                // 添加元数据
                let metadata = [
                    createMetadataItem(key: "com.apple.quicktime.live-photo", value: "1"),
                    createMetadataItem(key: "com.apple.quicktime.content.identifier", value: uuid),
                    createMetadataItem(key: "com.apple.quicktime.still-image-time", value: "0")
                ]
                exporter.metadata = metadata
                
                log("开始导出视频...")
                await exporter.export()
                
                log("导出状态: \(exporter.status.rawValue)")
                if let error = exporter.error {
                    log("导出错误: \(error)", level: "ERROR")
                }
                
                guard exporter.status == .completed else {
                    let error = exporter.error ?? NSError(domain: "ExportError", code: -1, userInfo: [NSLocalizedDescriptionKey: "视频导出失败"])
                    log("❌ 视频导出失败: \(error)", level: "ERROR")
                    throw error
                }
                
                log("✅ 视频导出成功")
                
                // 保存到相册，获取asset ID
                log("保存到相册...")
                var assetID: String?
                
                // 检查文件是否存在
                if !FileManager.default.fileExists(atPath: photoURL.path) {
                    log("❌ 图片文件不存在: \(photoURL.path)", level: "ERROR")
                    throw MediaProcessingError.saveFailed
                }
                
                if !FileManager.default.fileExists(atPath: clipURL.path) {
                    log("❌ 视频文件不存在: \(clipURL.path)", level: "ERROR")
                    throw MediaProcessingError.saveFailed
                }
                
                // 检查文件大小
                do {
                    let photoAttributes = try FileManager.default.attributesOfItem(atPath: photoURL.path)
                    let videoAttributes = try FileManager.default.attributesOfItem(atPath: clipURL.path)
                    
                    if let photoSize = photoAttributes[.size] as? Int64 {
                        log("图片文件大小: \(photoSize) bytes")
                    }
                    
                    if let videoSize = videoAttributes[.size] as? Int64 {
                        log("视频文件大小: \(videoSize) bytes")
                    }
                } catch {
                    log("⚠️ 无法检查文件大小: \(error)", level: "WARNING")
                }
                
                try await PHPhotoLibrary.shared().performChanges {
                    [self] in
                    self.log("创建PHAssetCreationRequest...")
                    let request = PHAssetCreationRequest.forAsset()
                    
                    self.log("添加图片资源...")
                    request.addResource(with: .photo, fileURL: photoURL, options: nil)
                    
                    self.log("添加配对视频资源...")
                    request.addResource(with: .pairedVideo, fileURL: clipURL, options: nil)
                    
                    assetID = request.placeholderForCreatedAsset?.localIdentifier
                    self.log("获取到Asset ID: \(assetID ?? "nil")")
                }
                
                // 清理临时文件
                try? FileManager.default.removeItem(at: photoURL)
                try? FileManager.default.removeItem(at: clipURL)
                
                let assetIDToReturn = assetID ?? ""
                await MainActor.run {
                    completion(.success(assetIDToReturn))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // 添加一个极简方法，专注于解决PHPhotosErrorDomain错误，返回asset ID
    private func saveWithUltraSimpleMethod(videoURL: URL) async throws -> String {
        // 1. 创建临时文件 - 使用完全符合Apple标准的命名
        let tempDir = FileManager.default.temporaryDirectory
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        
        // 使用标准命名格式 - 必须使用相同的前缀
        let photoFileName = "IMG_\(uuid).JPG"
        let videoFileName = "IMG_\(uuid).MOV"
        
        let photoURL = tempDir.appendingPathComponent(photoFileName)
        let newVideoURL = tempDir.appendingPathComponent(videoFileName)
        
        // 2. 从视频中提取第一帧作为图片
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        let cgImage = try await imageGenerator.image(at: time).image
        let image = UIImage(cgImage: cgImage)
        
        // 3. 保存图片 - 不添加任何元数据
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw MediaProcessingError.exportFailed
        }
        try imageData.write(to: photoURL)
        
        // 4. 复制视频 - 不添加任何元数据
        try FileManager.default.copyItem(at: videoURL, to: newVideoURL)
        
        // 5. 添加延迟确保文件写入完成
        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5秒
        
        // 6. 检查文件
        log("📊 极简方法 - 图片路径: \(photoURL.path)")
        log("📊 极简方法 - 视频路径: \(newVideoURL.path)")
        
        let photoSize = (try? FileManager.default.attributesOfItem(atPath: photoURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let videoSize = (try? FileManager.default.attributesOfItem(atPath: newVideoURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        
        log("📊 极简方法 - 图片大小: \(photoSize) bytes, 视频大小: \(videoSize) bytes")
        
        // 7. 使用最简单的方法保存到相册
        var assetID: String?
        try await PHPhotoLibrary.shared().performChanges {
            // 创建资源请求
            let request = PHAssetCreationRequest.forAsset()
            
            // 添加资源 - 不使用任何选项
            request.addResource(with: .photo, fileURL: photoURL, options: nil)
            request.addResource(with: .pairedVideo, fileURL: newVideoURL, options: nil)
            assetID = request.placeholderForCreatedAsset?.localIdentifier
        }
        
        log("✅ 极简方法 - 资源已成功保存到相册")
        
        // 返回asset ID
        return assetID ?? String(uuid)
    }
}

// 在类外部添加这个扩展
extension NSObject {
    @discardableResult
    func apply(_ block: (Self) -> Void) -> Self {
        block(self)
        return self
    }
} 
