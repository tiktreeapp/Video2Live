import SwiftUI
import PhotosUI
import AVFoundation



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
                                    ForEach(Array(videoThumbnails.enumerated()), id: \.element.id) { index, thumbnail in
                                        ZStack(alignment: .bottomLeading) {
                                            Image(uiImage: thumbnail.image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 100, height: 100)
                                                .clipped()
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        .offset(y: 90)
                        .onChange(of: selectedVideos) { videos in
                            if videos.count > 6 {
                                selectedVideos = Array(videos.prefix(6))
                            }
                            // 先铺设占位缩略图，提升首屏可见性
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
                

                // 转换按钮
                Button(action: {
                    if let firstVideo = selectedVideos.first {
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
            .navigationTitle("Video to Wallpaper")
        }
        .sheet(isPresented: $showingConversion) {
            // 优先使用带每个视频进度的视图；如编译报错可暂时改回 TitledConversionProgressView
            ConversionProgressView(
                isPresented: $showingConversion,
                previewImages: videoThumbnails.map { $0.image },
                onConversionStart: { progressAndIndexHandler, completionHandler in
                    LivePhotoConverter.shared.convertVideosToLivePhotos(
                        videos: selectedVideos,
                        timeSegment: .middle,
                        progressHandler: { progress in
                            // 将总体进度映射到第一个条目的索引；若多视频，内部会按 index 更新
                            progressAndIndexHandler(progress, 0)
                        },
                        completion: { result in
                            switch result {
                            case .success:
                                completionHandler(.success([]))
                            case .failure(let error):
                                completionHandler(.failure(error))
                            }
                        }
                    )
                }
            )
        }
    }
    
    // 加载视频缩略图（并发生成，按索引回填占位）
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
                                print("❌ 写入/处理临时文件失败: \(error)")
                            }
                        }
                    } catch {
                        print("❌ 加载视频失败: \(error)")
                    }
                    return (index, nil)
                }
            }
            
            for await result in group {
                if let (index, item) = result, let item = item {
                    await MainActor.run {
                        if index < videoThumbnails.count {
                            videoThumbnails[index] = item
                        } else {
                            videoThumbnails.append(item)
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
}

/*
    @Binding var isPresented: Bool
    let previewImages: [UIImage]
    // progress(overall, index), completion(result with [assetIDs])
    let onConversionStart: (@escaping (Double, Int) -> Void, @escaping (Result<[String], Error>) -> Void) -> Void

    @State private var overallProgress: Double = 0
    @State private var currentIndex: Int = 0
    @State private var total: Int = 0
    @State private var state: LocalState = .converting
    @State private var assetIDs: [String] = []

    enum LocalState { case converting, completed, failed }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Converting to Live Photo")
                    .font(.headline)
                Spacer()
                if state == .converting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 24)
            .background(Color(.systemGray6))

            // Content
            VStack(spacing: 16) {
                if state == .converting {
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
                }

                if !previewImages.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(previewImages.indices, id: \.self) { i in
                            Image(uiImage: previewImages[i])
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 40)
                                .cornerRadius(8)
                                .clipped()
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                                )
                        }
                        Spacer()
                    }
                }

                Group {
                    switch state {
                    case .converting:
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.blue)
                            Text("Converting item \(min(currentIndex + 1, max(total,1))) of \(max(total,1))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    case .completed:
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("All items converted successfully")
                                .font(.subheadline)
                                .foregroundColor(.green)
                            Spacer()
                        }
                    case .failed:
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Conversion failed")
                                .font(.subheadline)
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)

            if state != .converting {
                Divider()
                    .background(Color(.systemGray4))
                HStack(spacing: 8) {
                    Button("Close") {
                        isPresented = false
                    }
                    .frame(maxWidth: .infinity)
                    if state == .completed && !assetIDs.isEmpty {
                        Button("View in Photos") {
                            if let photosURL = URL(string: "photos-redirect://") {
                                UIApplication.shared.open(photosURL)
                            }
                        }
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
        .frame(maxWidth: 400, maxHeight: 500)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .onAppear { start() }
    }

    private func start() {
        total = previewImages.count
        onConversionStart(
            { overall, index in
                withAnimation {
                    self.overallProgress = overall
                    self.currentIndex = index
                }
            },
            { result in
                withAnimation {
                    switch result {
                    case .success(let ids):
                        self.assetIDs = ids
                        self.state = .completed
                        self.overallProgress = 1.0
                    case .failure(let error):
                        self.state = .failed
                        print("❌ Conversion failed: \(error)")
                    }
                }
            }
        )
    }
}

*/
#Preview {
    VideoToWallpaperView()
}