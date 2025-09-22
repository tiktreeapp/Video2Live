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
import UIKit



struct ContentView: View {
    @State private var selectedVideos: [PhotosPickerItem] = []
    @State private var videoThumbnails: [VideoThumbnail] = []

    @State private var selectedTab: Int = 0
    @State private var showingConversion = false
    @State private var selectedPreviewImage: UIImage?
    

    
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
                                        ForEach(Array(videoThumbnails.enumerated()), id: \.element.id) { index, thumbnail in
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
                                                                let _ = (width - size.width) / 2
                                                                let _ = (height - size.height) / 2
                                                            }
                                                        }
                                                    )
                                                    .overlay(alignment: .topTrailing) {
                                                        Button(action: {
                                                            withAnimation {
                                                                if index < videoThumbnails.count { videoThumbnails.remove(at: index) }
                                                                if index < selectedVideos.count { selectedVideos.remove(at: index) }
                                                            }
                                                        }) {
                                                            Image(systemName: "xmark.circle.fill")
                                                                .font(.system(size: 16, weight: .bold))
                                                                .foregroundColor(.white)
                                                                .padding(6)
                                                                .background(Color.black.opacity(0.6))
                                                                .clipShape(Circle())
                                                        }
                                                        .padding(6)
                                                    }
                                                
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
                            .onChange(of: selectedVideos) { videos in
                                if videos.count > 6 {
                                    selectedVideos = Array(videos.prefix(6))
                                }
                                // 先铺设占位缩略图，提升首屏感知
                                videoThumbnails = videos.map { _ in
                                    VideoThumbnail(
                                        image: UIImage(systemName: "video") ?? UIImage(),
                                        duration: "--:--"
                                    )
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
                        .frame(height: 30)
                    

                    
                    Spacer()
                        .frame(height: 30)
                    
                    // 转换按钮
                    Button(action: {
                        if let firstVideo = selectedVideos.first {
                            // 加载视频数据并转换
                            Task {
                                do {
                                    guard let videoData = try await firstVideo.loadTransferable(type: Data.self) else { return }
                                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                                    try videoData.write(to: tempURL)

                                    // 获取视频时长
                                    let asset = AVAsset(url: tempURL)
                                    let duration = try await asset.load(.duration).seconds

                                    // Choose middle point by default
                                    let time: Double = duration / 2

                                    // 提取关键帧
                                    let imageGenerator = AVAssetImageGenerator(asset: asset)
                                    let cgImage = try await imageGenerator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
                                    selectedPreviewImage = UIImage(cgImage: cgImage)
                                    showingConversion = true

                                    // 清理临时文件
                                    try FileManager.default.removeItem(at: tempURL)
                                } catch {
                                    print("Conversion failed: \(error)")
                                }
                            }
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
                .navigationTitle("Video to Live")
            }
            .tabItem {
                Image(systemName: "play.circle.fill")
                Text("Video to Live")
            }
            .tag(0)
            
            VideoToWallpaperView()
                .tabItem {
                    Image(systemName: "square.grid.2x2.fill")
                    Text("Video to Wallpaper")
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(2)
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
        
        // 转换进度（使用带列表行的进度视图）
        .sheet(isPresented: $showingConversion) {
            Video2Live.ConversionProgressView(
                isPresented: $showingConversion,
                previewImages: videoThumbnails.map { $0.image },
                onConversionStart: { progressAndIndexHandler, completionHandler in
                    LivePhotoConverter.shared.convertVideosToLivePhotos(
                        videos: selectedVideos,
                        timeSegment: .middle,
                        progressHandler: { progress in
                            // 单/多视频：将总体进度映射到当前索引（简化为0）
                            progressAndIndexHandler(progress, 0)
                        },
                        completion: { result in
                            switch result {
                            case .success:
                                completionHandler(Result.success([]))
                            case .failure(let error):
                                completionHandler(.failure(error))
                            }
                        }
                    )
                }
            )
        }
    }
    
    // 加载视频缩略图（并发生成，按索引回填之前的占位）
    private func loadVideoThumbnails() async {
        await withTaskGroup(of: (Int, VideoThumbnail?)?.self) { group in
            for (index, video) in selectedVideos.enumerated() {
                group.addTask {
                    do {
                        if let videoData = try await video.loadTransferable(type: Data.self) {
                            let tempDir = FileManager.default.temporaryDirectory
                            let tempURL = tempDir.appendingPathComponent(UUID().uuidString + ".mov")
                            do {
                                try videoData.write(to: tempURL)
                                let asset = AVAsset(url: tempURL)
                                defer { try? FileManager.default.removeItem(at: tempURL) }
                                
                                if let thumbnail = try await asset.generateThumbnail() {
                                    let duration = asset.duration.seconds
                                    let formattedDuration = formatDuration(duration)
                                    return (index, VideoThumbnail(image: thumbnail, duration: formattedDuration))
                                }
                            } catch {
                                print("Write/process temp file failed: \(error)")
                            }
                        }
                    } catch {
                        print("Load video failed: \(error)")
                    }
                    return (index, nil)
                }
            }
            
            for await result in group {
                if let (index, thumb) = result, let thumb = thumb {
                    await MainActor.run {
                        if index < videoThumbnails.count {
                            videoThumbnails[index] = thumb
                        } else {
                            videoThumbnails.append(thumb)
                        }
                    }
                }
            }
        }
    }
    
    // 辅助函数：格式化视频时长
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
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
                                      of: asset.tracks(withMediaType: .video)[0],
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
                Label("Share Image", systemImage: "square.and.arrow.up")
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

