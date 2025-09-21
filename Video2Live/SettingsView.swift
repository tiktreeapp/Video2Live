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
                // Conversion Settings
                Section(header: Text("Conversion Settings")) {
                    Toggle("Auto Save to Album", isOn: $enableAutoSave)
                    
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
                
                // Watermark Settings
                Section(header: Text("Watermark Settings")) {
                    Toggle("Add Watermark", isOn: $enableWatermark)
                    
                    if enableWatermark {
                        TextField("Watermark Text", text: $watermarkText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                
                // About App
                Section(header: Text("About App")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(appVersion) (\(buildNumber))")
                            .foregroundColor(.secondary)
                    }
                    
                    Link("Privacy Policy", destination: URL(string: "https://www.example.com/privacy")!)
                    
                    Link("Terms of Service", destination: URL(string: "https://www.example.com/terms")!)
                }
                
                // Action Buttons
                Section {
                    Button("Clear Cache") {
                        clearCache()
                    }
                    
                    Button("Send Feedback") {
                        sendFeedback()
                    }
                    .foregroundColor(.blue)
                    
                    Button("Rate App") {
                        openAppStore()
                    }
                    .foregroundColor(.green)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                loadAppInfo()
            }
        }
    }
    
    // Load app information
    private func loadAppInfo() {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            appVersion = version
        }
        
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            buildNumber = build
        }
    }
    
    // Clear cache
    private func clearCache() {
        // Clear temporary files and cache
        let tempDir = FileManager.default.temporaryDirectory
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for file in contents {
                try FileManager.default.removeItem(at: file)
            }
            
            // Show success message
            showAlert(message: "Cache cleared successfully")
        } catch {
            showAlert(message: "Failed to clear cache: \(error.localizedDescription)")
        }
    }
    
    // Send feedback
    private func sendFeedback() {
        // Open mail app to send feedback
        if let url = URL(string: "mailto:feedback@example.com?subject=Video2Live Feedback") {
            UIApplication.shared.open(url)
        }
    }
    
    // Open App Store for rating
    private func openAppStore() {
        // Open App Store for rating
        if let url = URL(string: "itms-apps://itunes.apple.com/app/id123456789") {
            UIApplication.shared.open(url)
        }
    }
    
    // Show alert message
    private func showAlert(message: String) {
        // In a real app, this should show a UIAlertController or custom alert view
        print(message)
    }
}

#Preview {
    SettingsView()
}