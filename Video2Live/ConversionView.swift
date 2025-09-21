import SwiftUI
import Photos

// Conversion state enum - using more explicit naming to avoid conflicts
enum VideoConversionState: Equatable {
    case ready
    case converting(progress: Double)  // Converting, with progress
    case completed                     // Conversion completed
    case failed                        // Conversion failed
}

struct ConversionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    @State private var currentConversionState: VideoConversionState = .ready
    @State private var savedAssetID: String?
    @State private var customMessage: String?
    
    let previewImage: UIImage
    let onConversionStart: (@escaping (Double) -> Void, @escaping (Result<String, Error>) -> Void) -> Void
    
    private var resultMessage: String {
        if let customMessage = customMessage {
            return customMessage
        }
        switch currentConversionState {
        case .ready:
            return "Preparing conversion..."
        case .converting(let progress):
            return "Converting... \(Int(progress * 100))%"
        case .completed:
            return "✅ Live Photo saved to your Photos!"
        case .failed:
            return "❌ Conversion failed"
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Preview Image
            Image(uiImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 200)
                .cornerRadius(15)
                .shadow(radius: 5)
                .padding(.top, 30)

            // Status Message
            Text(resultMessage)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .animation(.easeInOut, value: currentConversionState)

            // Progress View
            if case let .converting(progressValue) = currentConversionState {
                VStack(spacing: 8) {
                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .scaleEffect(x: 1, y: 2)
                    
                    Text("\(Int(progressValue * 100))% Complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 40)
                .animation(.easeInOut, value: progressValue)
            }

            // Action Buttons - 直接显示结果，没有Start Conversion按钮
            if case .completed = currentConversionState {
                VStack(spacing: 12) {
                    // View in Photos Button
                    Button(action: {
                        openInPhotos()
                    }) {
                        HStack {
                            Image(systemName: "photo")
                            Text("View in Photos")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                    }

                    // Close Button
                    Button(action: {
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Close")
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
            } else if case .failed = currentConversionState {
                VStack(spacing: 12) {
                    Button("Try Again") {
                        resetConversionState()
                        startConversion()
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        // 自动开始转换
        .onAppear {
            if case .ready = currentConversionState {
                startConversion()
            }
        }
    }
    
    // Helper function to reset conversion state
    private func resetConversionState() {
        currentConversionState = .ready
        customMessage = nil
    }
    
    // Helper function to start conversion
    private func startConversion() {
        onConversionStart(
            { progress in
                withAnimation {
                    currentConversionState = .converting(progress: progress)
                }
            },
            { result in
                withAnimation {
                    switch result {
                    case .success(let assetID):
                        savedAssetID = assetID
                        currentConversionState = .completed
                    case .failure(let error):
                        print("Conversion failed: \(error)")
                        currentConversionState = .ready
                        // Show error message
                        customMessage = "Conversion failed. Please try again."
                    }
                }
            }
        )
    }
    
    // Helper function to open in Photos app
    private func openInPhotos() {
        guard let assetID = savedAssetID else { return }
        
        // Fetch the asset and open it in Photos app
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        if result.firstObject != nil {
            // Try to open the Photos app
            if let photosURL = URL(string: "photos-redirect://") {
                UIApplication.shared.open(photosURL)
            }
        }
    }
}

// Preview
#Preview {
    ConversionView(
        isPresented: .constant(true),
        previewImage: UIImage(systemName: "photo") ?? UIImage(),
        onConversionStart: { progressHandler, completionHandler in
            // No actual conversion in preview
            progressHandler(0.5)
            completionHandler(.success("preview-asset-id"))
        }
    )
}