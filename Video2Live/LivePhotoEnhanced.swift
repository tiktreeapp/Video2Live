import Foundation
import AVFoundation
import Photos
import UIKit

class LivePhotoEnhanced {
    // 单例模式
    static let shared = LivePhotoEnhanced()
    private init() {}
    
    // 日志工具
    private func log(_ message: String) {
        print("📝 [LivePhotoEnhanced] \(message)")
    }
    
    // 只保留AVFoundation处理方法
    func processVideoWithAVFoundation(
        inputURL: URL,
        outputURL: URL,
        startTime: Double,
        duration: Double
    ) async throws {
        // 创建AVAsset
        let asset = AVAsset(url: inputURL)
        
        // 创建时间范围
        let timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        
        // 使用AVFoundation导出
        let composition = AVMutableComposition()
        
        // 添加视频轨道
        if let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let assetVideoTrack = try? await asset.loadTracks(withMediaType: .video).first {
            let preferredTransform = try? await assetVideoTrack.load(.preferredTransform)
            videoTrack.preferredTransform = preferredTransform ?? .identity
            try? videoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: .zero)
        }
        
        // 添加音频轨道
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }
        
        // 导出
        if let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) {
            exporter.outputURL = outputURL
            exporter.outputFileType = .mov
            await exporter.export()
            
            if exporter.status == .completed {
                log("✅ 视频处理成功")
            } else {
                throw NSError(domain: "ExportError", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "视频导出失败"])
            }
        }
    }
    
    // 保留图片处理方法
    func extractAndProcessImage(
        from asset: AVAsset,
        at time: CMTime,
        outputURL: URL,
        livePhotoID: String
    ) async throws {
        // 使用AVFoundation提取关键帧
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        let cgImage = try await imageGenerator.image(at: time).image
        let image = UIImage(cgImage: cgImage)
        
        // 创建一个带有额外元数据的图片
        guard let source = CGImageSourceCreateWithData(image.jpegData(compressionQuality: 1.0)! as CFData, nil) else {
            throw NSError(domain: "ImageError", code: -1, userInfo: nil)
        }
        
        let metadata = NSMutableDictionary()
        metadata["com.apple.quicktime.live-photo"] = "1"
        metadata["com.apple.quicktime.content.identifier"] = livePhotoID
        
        let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImageFromSource(destination, source, 0, metadata)
        CGImageDestinationFinalize(destination)
        
        log("✅ 图片处理成功")
    }
} 
