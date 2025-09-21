import SwiftUI

struct SettingsView: View {
    // 用户设置状态
    @AppStorage("enableWatermark") private var enableWatermark = false
    @AppStorage("watermarkText") private var watermarkText = "Video2Live"
    @AppStorage("outputQuality") private var outputQuality = 1.0
    @AppStorage("enableAutoSave") private var enableAutoSave = true
    
    // 应用信息
    @State private var appVersion = "1.0"
    @State private var buildNumber = "1"
    
    var body: some View {
        NavigationView {
            Form {
                // 转换设置
                Section(header: Text("转换设置")) {
                    Toggle("自动保存到相册", isOn: $enableAutoSave)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("输出质量")
                        Slider(value: $outputQuality, in: 0.1...1.0, step: 0.1) {
                            Text("输出质量")
                        }
                        Text("质量: \(Int(outputQuality * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 水印设置
                Section(header: Text("水印设置")) {
                    Toggle("添加水印", isOn: $enableWatermark)
                    
                    if enableWatermark {
                        TextField("水印文字", text: $watermarkText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                
                // 关于应用
                Section(header: Text("关于应用")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("\(appVersion) (\(buildNumber))")
                            .foregroundColor(.secondary)
                    }
                    
                    Link("隐私政策", destination: URL(string: "https://www.example.com/privacy")!)
                    
                    Link("用户协议", destination: URL(string: "https://www.example.com/terms")!)
                }
                
                // 操作按钮
                Section {
                    Button("清除缓存") {
                        clearCache()
                    }
                    
                    Button("反馈问题") {
                        sendFeedback()
                    }
                    .foregroundColor(.blue)
                    
                    Button("评分支持") {
                        openAppStore()
                    }
                    .foregroundColor(.green)
                }
            }
            .navigationTitle("设置")
            .onAppear {
                loadAppInfo()
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
    
    // 发送反馈
    private func sendFeedback() {
        // 打开邮件应用发送反馈
        if let url = URL(string: "mailto:feedback@example.com?subject=Video2Live Feedback") {
            UIApplication.shared.open(url)
        }
    }
    
    // 打开App Store评分
    private func openAppStore() {
        // 打开App Store进行评分
        if let url = URL(string: "itms-apps://itunes.apple.com/app/id123456789") {
            UIApplication.shared.open(url)
        }
    }
    
    // 显示提示信息
    private func showAlert(message: String) {
        // 在实际应用中，这里应该显示一个UIAlertController或自定义的提示视图
        print(message)
    }
}

#Preview {
    SettingsView()
}