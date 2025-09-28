import Foundation
import AVFoundation
import Photos
import UIKit

/// 增强的Video转Live Photo转换器 - 带有详细日志
class EnhancedVideoToLivePhotoConverter {
    
    // 单例模式
    static let shared = EnhancedVideoToLivePhotoConverter()
    private init() {}
    
    // 详细的日志记录
    private func log(_ message: String, level: String = "INFO") {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("🔄 [EnhancedConverter] [\(level)] [\(timestamp)] \(message)")
    }
    
    /// 测试转换 - 带有详细诊断
    func testConvertVideoToLivePhoto(
        videoURL: URL,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        log("=== 开始Video转Live Photo测试转换 ===")
        log("视频URL: \(videoURL.path)")
        
        // 检查文件是否存在
        if !FileManager.default.fileExists(atPath: videoURL.path) {
            log("❌ 视频文件不存在", level: "ERROR")
            completion(.failure(NSError(domain: "FileNotFound", code: -1, userInfo: [NSLocalizedDescriptionKey: "视频文件不存在"])))
            return
        }
        
        // 检查文件大小
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
            if let fileSize = attributes[.size] as? Int64 {
                log("视频文件大小: \(Double(fileSize) / 1024.0 / 1024.0) MB")
            }
        } catch {
            log("⚠️ 无法获取文件大小: \(error)", level: "WARNING")
        }
        
        // 使用MediaAssetProcessor进行转换
        log("使用MediaAssetProcessor.createLivePhotoDirectly进行转换...")
        
        MediaAssetProcessor.shared.createLivePhotoDirectly(from: videoURL) { result in
            switch result {
            case .success(let assetID):
                self.log("✅ 转换成功! Asset ID: \(assetID)")
                completion(.success(assetID))
                
                // 验证创建的Live Photo
                self.verifyLivePhoto(assetID: assetID)
                
            case .failure(let error):
                self.log("❌ 转换失败: \(error)", level: "ERROR")
                self.log("错误详情: \(String(describing: error))", level: "ERROR")
                
                if let nsError = error as NSError? {
                    self.log("错误域: \(nsError.domain), 错误码: \(nsError.code)", level: "ERROR")
                    self.log("错误描述: \(nsError.localizedDescription)", level: "ERROR")
                    self.log("用户信息: \(nsError.userInfo)", level: "ERROR")
                }
                
                completion(.failure(error))
            }
        }
    }
    
    /// 验证创建的Live Photo
    private func verifyLivePhoto(assetID: String) {
        log("验证创建的Live Photo...")
        
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        if let asset = result.firstObject {
            let isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
            log("Live Photo验证结果: \(isLivePhoto ? "✅ 是Live Photo" : "❌ 不是Live Photo")")
            
            if !isLivePhoto {
                log("⚠️ 创建的资产不是Live Photo，可能是普通照片", level: "WARNING")
            }
        } else {
            log("❌ 无法找到创建的资产", level: "ERROR")
        }
    }
    
    /// 诊断视频文件
    func diagnoseVideoFile(_ videoURL: URL) {
        log("=== 开始视频文件诊断 ===")
        
        // 基本文件检查
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: videoURL.path) {
            log("✅ 文件存在")
        } else {
            log("❌ 文件不存在", level: "ERROR")
            return
        }
        
        // 文件大小
        do {
            let attributes = try fileManager.attributesOfItem(atPath: videoURL.path)
            if let fileSize = attributes[.size] as? Int64 {
                let sizeInMB = Double(fileSize) / 1024.0 / 1024.0
                log("文件大小: \(String(format: "%.2f", sizeInMB)) MB")
                
                if sizeInMB < 0.1 {
                    log("⚠️ 文件太小，可能不是有效视频", level: "WARNING")
                } else if sizeInMB > 100 {
                    log("⚠️ 文件很大，转换可能需要较长时间", level: "WARNING")
                }
            }
        } catch {
            log("⚠️ 无法获取文件属性: \(error)", level: "WARNING")
        }
        
        // 视频格式检查
        let asset = AVAsset(url: videoURL)
        
        Task {
            do {
                // 检查视频轨道
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                log("视频轨道数量: \(videoTracks.count)")
                
                if videoTracks.isEmpty {
                    log("❌ 没有找到视频轨道", level: "ERROR")
                    return
                }
                
                // 检查音频轨道
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                log("音频轨道数量: \(audioTracks.count)")
                
                // 检查时长
                let duration = try await asset.load(.duration)
                let durationInSeconds = duration.seconds
                log("视频时长: \(String(format: "%.2f", durationInSeconds)) 秒")
                
                if durationInSeconds < 1.0 {
                    log("⚠️ 视频太短（<1秒），可能不适合做Live Photo", level: "WARNING")
                } else if durationInSeconds > 5.0 {
                    log("⚠️ 视频较长（>5秒），Live Photo通常较短", level: "WARNING")
                }
                
                // 检查视频格式
                if let videoTrack = videoTracks.first {
                    let formatDescriptions = try await videoTrack.load(.formatDescriptions)
                    log("视频格式描述数量: \(formatDescriptions.count)")
                    
                    for (index, formatDesc) in formatDescriptions.enumerated() {
                        log("格式 \(index): \(formatDesc)")
                    }
                }
                
                log("=== 视频文件诊断完成 ===")
                
            } catch {
                log("❌ 视频诊断失败: \(error)", level: "ERROR")
            }
        }
    }
    
    /// 检查系统权限和状态
    func checkSystemStatus() {
        log("=== 系统状态检查 ===")
        
        // 检查相册权限
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        log("相册权限状态: \(status.rawValue)")
        
        switch status {
        case .authorized:
            log("✅ 相册权限已授权")
        case .notDetermined:
            log("⚠️ 相册权限未确定，需要请求")
        case .denied, .restricted:
            log("❌ 相册权限被拒绝或限制", level: "ERROR")
        case .limited:
            log("⚠️ 相册权限有限")
        @unknown default:
            log("⚠️ 未知的权限状态")
        }
        
        // 检查设备容量
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory() as String)
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
            
            if let available = values.volumeAvailableCapacity {
                let availableMB = Double(available) / 1024.0 / 1024.0
                log("可用存储空间: \(String(format: "%.2f", availableMB)) MB")
                
                if availableMB < 100 {
                    log("⚠️ 存储空间不足（<100MB）", level: "WARNING")
                }
            }
        } catch {
            log("⚠️ 无法检查存储空间: \(error)", level: "WARNING")
        }
        
        log("=== 系统状态检查完成 ===")
    }
}