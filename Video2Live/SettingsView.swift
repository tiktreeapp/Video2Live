import SwiftUI

struct SettingsView: View {
    // 用户设置状态
    @AppStorage("enableWatermark") private var enableWatermark = false
    @AppStorage("watermarkText") private var watermarkText = "Video2Live"
    @AppStorage("outputQuality") private var outputQuality = 1.0
    @AppStorage("enableAutoSave") private var enableAutoSave = true
    // Share sheet state
    @State private var isShareSheetPresented = false
    @State private var shareItems: [Any] = []
    
    // 应用信息
    @State private var appVersion = "1.0"
    @State private var buildNumber = "1"
    
    var body: some View {
        NavigationView {
            Form {
                // Conversion Settings
                Section(header: Text("Conversion Settings")) {
                    Toggle("Auto-save to Photos", isOn: $enableAutoSave)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Output Quality")
                        Slider(value: $outputQuality, in: 0.1...1.0, step: 0.1) {
                            Text("Output Quality")
                        }
                        Text("Quality: \(Int(outputQuality * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Actions
                Section {
                    Button("Share") {
                        shareApp()
                    }
                    
                    Button("Rate us") {
                        openAppStore()
                    }
                    .foregroundColor(.green)
                }
            }
            .navigationTitle("Settings")
            .onAppear { loadAppInfo() }
            .sheet(isPresented: $isShareSheetPresented) {
                ShareSheet(items: shareItems)
            }
            // 复用与首页一致的纯白底栏样式
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 0)
                    Color(.systemGray5)
                        .frame(height: 0.5)
                        .offset(y: -48)
                }
                .background(.white)
            }
        }
    }
    
    // 加载应用信息
    private func loadAppInfo() {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            appVersion = version
        }
        
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            buildNumber = build
        }
    }
    
    // 清除缓存
    private func clearCache() {
        // 清除临时文件和缓存
        let tempDir = FileManager.default.temporaryDirectory
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for file in contents {
                try FileManager.default.removeItem(at: file)
            }
            
            // 显示成功提示
            showAlert(message: "缓存已清除")
        } catch {
            showAlert(message: "清除缓存失败: \(error.localizedDescription)")
        }
    }
    
    // Share via system share sheet
    private func shareApp() {
        // Replace with your app link or any content you want to share
        let text = "One tap to convert Video to Live Photo by https://apps.apple.com/app/id6752836382"
        shareItems = [text]
        isShareSheetPresented = true
    }
    
    // 打开App Store评分
    private func openAppStore() {
        // 打开App Store进行评分
        if let url = URL(string: "itms-apps://itunes.apple.com/app/id6752836382") {
            UIApplication.shared.open(url)
        }
    }
    
    // 显示提示信息
    private func showAlert(message: String) {
        // 在实际应用中，这里应该显示一个UIAlertController或自定义的提示视图
        print(message)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView()
}