import SwiftUI
import SwiftUI
import PhotosUI
import AVFoundation

struct VideoThumbnail: Identifiable, Hashable {
    let id = UUID()
    let image: UIImage
    let duration: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct VideoToWallpaperView: View {
    @State private var selectedVideos: [PhotosPickerItem] = []
    @State private var videoThumbnails: [VideoThumbnail] = []
    @State private var showingConversion = false
    @State private var selectedPreviewImage: UIImage?
    
    var body: some View {
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
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 100, height: 100)
                                                .clipped()
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                            
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
                        .offset(y: 90)
                        .onChange(of: selectedVideos) { videos in
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
                    .frame(height: 30)
                
                // 转换按钮
                Button(action: {
                    if let firstVideo = selectedVideos.first {
                        Task {
                            do {
                                let videoData = try await firstVideo.loadTransferable(type: Data.self)
                                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                                try videoData.write(to: tempURL)

                                // 获取视频时长
                                let asset = AVAsset(url: tempURL)
                                let duration = try await asset.load(.duration).seconds

                                // 使用视频中间点作为预览图
                                let time = duration / 2

                                // 提取关键帧
                                let imageGenerator = AVAssetImageGenerator(asset: asset)
                                let cgImage = try await imageGenerator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
                                selectedPreviewImage = UIImage(cgImage: cgImage)
                                showingConversion = true

                                // 清理临时文件
                                try FileManager.default.removeItem(at: tempURL)
                            } catch {
                                print("转换失败: \(error)")
                            }
                        }
                    }
                }) {
                    Text("Convert to Wallpaper")
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
            .navigationTitle("Video2Wallpaper")
        }
        .sheet(isPresented: $showingConversion) {
            if let previewImage = selectedPreviewImage {
                ConversionView(
                    isPresented: $showingConversion,
                    previewImage: previewImage,
                    onConversionStart: { progressHandler, completionHandler in
                        // 开始转换
                        LivePhotoConverter.shared.convertVideosToLivePhotos(
                            videos: selectedVideos,
                            timeSegment: .first, // 壁纸功能默认使用前3秒
                            progressHandler: progressHandler,
                            completion: { result in
                                switch result {
                                case .success(let assetID):
                                    completionHandler(.success(assetID))
                                case .failure(let error):
                                    completionHandler(.failure(error))
                                }
                            }
                        )
                    }
                )
            }
        }
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
                            let duration = asset.duration.seconds
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
}

#Preview {
    VideoToWallpaperView()
}